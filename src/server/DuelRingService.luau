--!strict
-- 決闘リング（PHASE0_PLAN_v2 5.4）。
-- ・町の広場の中央。両側の台に 1 人ずつ乗ると、サーバーがそれぞれの未装着ピースから賭けを 1 つ選ぶ（重複を優先）
-- ・5 秒のカウントダウン中に台を降りれば何も起きない
-- ・対戦の開始と同時に HP は満タン、付与は空、ゲージは 0
-- ・決着：HP 0、リングの外に出る、90 秒たって HP の割合が少ない方。勝者は相手の賭けピースをもらう
-- ・敗者は Config.Ring.LoserCooldown 秒リングに乗れない
-- 対人の効果は BattleStateService.canAffectPlayer（対戦相手どうしだけ）を通るので、リングの外の人には何も入らない。
-- 台に乗る・降りるは、サーバーがキャラクターの位置を見て決める（Remote は使わない）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local DuelLogic = require(Shared:WaitForChild("Logic"):WaitForChild("DuelLogic"))

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local BattleStateService = require(script.Parent.BattleStateService)
local CombatService = require(script.Parent.CombatService)
local GrantService = require(script.Parent.GrantService)
local UltimateService = require(script.Parent.UltimateService)
local Metrics = require(script.Parent.Metrics)
local Remotes = require(script.Parent.Remotes)
local WorldMarkers = require(script.Parent.WorldMarkers)

local DuelRingService = {}

local PAD_COLORS = { Color3.fromRGB(220, 80, 70), Color3.fromRGB(70, 120, 230) }

local center = Vector3.zero -- 床の上面の中心
local padPositions: { Vector3 } = {} -- 台の上面の中心
local statusLabel: TextLabel? = nil

local phase = "idle" -- "idle" | "countdown" | "fight"
local fighters: { Player } = {} -- [1] = 赤の台、[2] = 青の台
local bets: { string } = {}
local phaseEndsAt = 0
local loserUntil: { [Player]: number } = {}
local lostAt: { [Player]: number } = {}
local noticeAt: { [Player]: number } = {}
local betTags: { BillboardGui } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end

local function pieceName(pieceId: string?): string
	local def = if pieceId then PieceDefs[pieceId] else nil
	return if def then def.nameJa else "?"
end

local function humanoidOf(player: Player): Humanoid?
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	return humanoid
end

local function offset(player: Player, from: Vector3): Vector3?
	local root = CombatService.rootOf(player)
	return if root then root.Position - from else nil
end

local function onPad(player: Player, index: number): boolean
	local d = offset(player, padPositions[index])
	return d ~= nil and DuelLogic.isOnPad(d.X, d.Z, d.Y, Config.Ring.PadRadius, Config.Ring.PadMaxHeight)
end

local function inRing(player: Player): boolean
	local d = offset(player, center)
	return d ~= nil and DuelLogic.isInside(d.X, d.Z, d.Y, Config.Ring.Radius, Config.Ring.FallDepth)
end

local function isAlive(player: Player): boolean
	local humanoid = humanoidOf(player)
	return player.Parent ~= nil and humanoid ~= nil and humanoid.Health > 0
end

-- 乗れるか。乗れなければ理由コード
local function eligibility(player: Player): string?
	local profile = DataService.getProfile(player)
	if profile == nil then
		return "not_loaded"
	end
	if not isAlive(player) then
		return "dead"
	end
	if (loserUntil[player] or 0) > now() then
		return "ring_cooldown"
	end
	if DuelLogic.pickBet(profile.pieces, PieceDefs) == nil then
		return "ring_need_piece"
	end
	return nil
end

local function notify(player: Player, reason: string)
	if (noticeAt[player] or 0) <= now() then
		noticeAt[player] = now() + Config.Ring.NoticeSeconds
		Remotes.fire(player, "Toast", reason)
	end
end

local function setStatus(text: string)
	if statusLabel then
		statusLabel.Text = text
	end
end

local function broadcast(extra: { [string]: any }?)
	local payload: { [string]: any } = {
		phase = phase,
		a = if fighters[1] then fighters[1].UserId else nil,
		b = if fighters[2] then fighters[2].UserId else nil,
		betA = bets[1],
		betB = bets[2],
		endsAt = phaseEndsAt,
	}
	if extra then
		for k, v in extra do
			payload[k] = v
		end
	end
	Remotes.fireAll("Ring_Update", payload)
end

-- 賭けたピースを頭の上に出す（全員に見える）
local function showBet(player: Player, pieceId: string, color: Color3)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "RingBet"
	gui.Size = UDim2.fromOffset(160, 36)
	gui.StudsOffset = Vector3.new(0, 3.2, 0)
	gui.AlwaysOnTop = true
	gui.Parent = head
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundColor3 = color
	label.BackgroundTransparency = 0.15
	label.Font = Enum.Font.GothamBold
	label.TextSize = 16
	label.TextColor3 = Color3.new(1, 1, 1)
	label.Text = "賭け：" .. pieceName(pieceId)
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = label
	table.insert(betTags, gui)
end

local function reset()
	for _, gui in betTags do
		gui:Destroy()
	end
	betTags = {}
	fighters = {}
	bets = {}
	phase = "idle"
	phaseEndsAt = 0
	setStatus("決闘リング\n赤と青の台に 1 人ずつ乗ると始まります")
end

local function cancel()
	reset()
	broadcast({ cancelled = true })
end

local function startCountdown(a: Player, b: Player)
	local betA = DuelLogic.pickBet((DataService.getProfile(a) :: any).pieces, PieceDefs)
	local betB = DuelLogic.pickBet((DataService.getProfile(b) :: any).pieces, PieceDefs)
	if betA == nil or betB == nil then
		return
	end
	fighters = { a, b }
	bets = { betA, betB }
	phase = "countdown"
	phaseEndsAt = now() + Config.Ring.CountdownSeconds
	showBet(a, betA, PAD_COLORS[1])
	showBet(b, betB, PAD_COLORS[2])
	broadcast()
end

-- 外での準備を持ち込まない：HP 満タン、付与は空、ゲージ 0
local function prepare(player: Player)
	local humanoid = humanoidOf(player)
	if humanoid then
		humanoid.Health = humanoid.MaxHealth
	end
	GrantService.clear(player)
	UltimateService.reset(player)
end

local function startFight()
	local a, b = fighters[1], fighters[2]
	-- カウントダウン中に賭けピースを失っていないか、もう一度確かめる
	for i, player in fighters do
		local profile = DataService.getProfile(player)
		if eligibility(player) ~= nil or profile == nil or (profile.pieces.unplaced[bets[i]] or 0) < 1 then
			cancel()
			return
		end
	end
	local t = now()
	for _, player in fighters do
		prepare(player)
		Metrics.event(player, Metrics.Events.RingJoined)
		if DuelLogic.isRematch(lostAt[player], t, Config.Ring.RematchWindowSeconds) then
			Metrics.event(player, Metrics.Events.RingRematch)
		end
	end
	BattleStateService.setPvpPair(a, b)
	phase = "fight"
	phaseEndsAt = t + Config.Ring.MatchSeconds
	broadcast()
end

-- 決着。loserIndex が nil なら引き分け
local function finish(loserIndex: number?, reason: string)
	if phase ~= "fight" then
		return
	end
	local a, b = fighters[1], fighters[2]
	local betList = bets
	phase = "idle" -- 二重に決着しないよう、先に変える
	BattleStateService.clearPvp(a)

	local result: { [string]: any } = { reason = reason }
	if loserIndex then
		local loser = fighters[loserIndex]
		local winner = fighters[3 - loserIndex]
		local piece = betList[loserIndex]
		-- ピースの増減は InventoryService を通す。勝者が持ちきれなければ敗者に戻す
		local moved = false
		if InventoryService.removeUnplacedPiece(loser, piece) then
			moved = InventoryService.addUnplacedPiece(winner, piece)
			if not moved then
				InventoryService.addUnplacedPiece(loser, piece)
			end
		end
		local t = now()
		loserUntil[loser] = t + Config.Ring.LoserCooldown
		lostAt[loser] = t
		Metrics.event(winner, Metrics.Events.RingWon)
		Metrics.event(loser, Metrics.Events.RingLost)
		result.winner = winner.UserId
		result.loser = loser.UserId
		result.piece = piece
		result.moved = moved
	else
		result.draw = true
	end
	reset()
	broadcast({ result = result })
end

local function tickIdle()
	local candidates: { Player? } = { nil, nil }
	for _, player in Players:GetPlayers() do
		for i = 1, 2 do
			if onPad(player, i) then
				local reason = eligibility(player)
				if reason then
					notify(player, reason)
				elseif candidates[i] == nil then
					candidates[i] = player
				end
			end
		end
	end
	local a, b = candidates[1], candidates[2]
	if a and b and a ~= b then
		startCountdown(a, b)
	elseif a or b then
		local waiting = (a or b) :: Player
		setStatus(("決闘リング\n%s が相手を待っています"):format(waiting.DisplayName))
	else
		setStatus("決闘リング\n赤と青の台に 1 人ずつ乗ると始まります")
	end
end

local function tickCountdown()
	for i, player in fighters do
		if player.Parent == nil or not isAlive(player) or not onPad(player, i) then
			cancel()
			return
		end
	end
	local left = phaseEndsAt - now()
	if left <= 0 then
		startFight()
	else
		setStatus(("決闘まで %d\n台を降りれば取りやめ"):format(math.ceil(left)))
	end
end

local function tickFight()
	local out = {}
	for i, player in fighters do
		out[i] = not isAlive(player) or not inRing(player)
	end
	if out[1] and out[2] then
		finish(nil, "both_out")
		return
	elseif out[1] then
		finish(1, "out")
		return
	elseif out[2] then
		finish(2, "out")
		return
	end

	local left = phaseEndsAt - now()
	if left <= 0 then
		local ratios = {}
		for i, player in fighters do
			local humanoid = humanoidOf(player) :: Humanoid
			ratios[i] = humanoid.Health / humanoid.MaxHealth
		end
		local judged = DuelLogic.judgeTimeout(ratios[1], ratios[2])
		finish(if judged == "a" then 2 elseif judged == "b" then 1 else nil, "timeout")
		return
	end
	setStatus(("決闘中  残り %d 秒\n%s  対  %s"):format(math.ceil(left), fighters[1].DisplayName, fighters[2].DisplayName))
end

-- 対戦中に抜けたら負け（保存の写しを取る前に賭けピースを動かす）。カウントダウン中なら取りやめ
local function onLeaving(player: Player)
	local index = table.find(fighters, player)
	if index == nil then
		return
	end
	if phase == "fight" then
		finish(index, "left")
	elseif phase == "countdown" then
		cancel()
	end
end

-- 決闘の台に乗っている間（カウントダウン・対戦中）は、ピースをはめられない（賭けを動かさないため）
function DuelRingService.isLocked(player: Player): boolean
	return phase ~= "idle" and table.find(fighters, player) ~= nil
end

local function build()
	local marker = WorldMarkers.find("DuelRing")
	local base: CFrame
	if marker then
		base = marker.CFrame * CFrame.new(0, marker.Size.Y / 2, 0)
	else
		local spawn = WorldMarkers.spawnCFrame() * CFrame.new(WorldMarkers.toVector(Config.Ring.SpawnOffset))
		local floorTop = spawn.Position.Y + 0.5
		base = CFrame.new(spawn.Position.X, floorTop, spawn.Position.Z) * spawn.Rotation

		local floor = Instance.new("Part")
		floor.Name = "DuelRing"
		floor.Shape = Enum.PartType.Cylinder
		floor.Size = Vector3.new(1, Config.Ring.Radius * 2, Config.Ring.Radius * 2)
		floor.CFrame = base * CFrame.new(0, -0.5, 0) * CFrame.Angles(0, 0, math.rad(90))
		floor.Anchored = true
		floor.Material = Enum.Material.Slate
		floor.Color = Color3.fromRGB(200, 190, 170)
		floor.Parent = workspace
	end
	center = base.Position

	padPositions = {}
	for i, side in { -1, 1 } do
		local cf = base * CFrame.new(side * Config.Ring.PadOffset, 0, 0)
		local pad = Instance.new("Part")
		pad.Name = "RingPad" .. i
		pad.Shape = Enum.PartType.Cylinder
		pad.Size = Vector3.new(0.4, Config.Ring.PadRadius * 2, Config.Ring.PadRadius * 2)
		pad.CFrame = cf * CFrame.new(0, 0.2, 0) * CFrame.Angles(0, 0, math.rad(90))
		pad.Anchored = true
		pad.Material = Enum.Material.Neon
		pad.Color = PAD_COLORS[i]
		pad.Parent = workspace
		padPositions[i] = cf.Position + Vector3.new(0, 0.4, 0)
	end

	-- 見物している人にも分かるよう、リングの上に状態を出す
	local anchor = Instance.new("Part")
	anchor.Name = "RingStatus"
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(1, 1, 1)
	anchor.Position = center + Vector3.new(0, 12, 0)
	anchor.Parent = workspace
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 70)
	gui.AlwaysOnTop = false
	gui.MaxDistance = 120
	gui.Parent = anchor
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui
	statusLabel = label
end

function DuelRingService.init()
	build()
	reset()
	DataService.onBeforeRelease(onLeaving)
	Players.PlayerRemoving:Connect(function(player)
		onLeaving(player) -- 読み込み前に抜けた人など、上で呼ばれなかったとき用
		loserUntil[player] = nil
		lostAt[player] = nil
		noticeAt[player] = nil
	end)
	task.spawn(function()
		while true do
			task.wait(Config.Ring.TickInterval)
			local ok, err = pcall(function()
				if phase == "idle" then
					tickIdle()
				elseif phase == "countdown" then
					tickCountdown()
				else
					tickFight()
				end
			end)
			if not ok then
				warn("[DuelRing] " .. tostring(err))
			end
		end
	end)
end

return DuelRingService
