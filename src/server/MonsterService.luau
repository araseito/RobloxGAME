--!strict
-- モンスター 4 体と図鑑（PHASE0_PLAN_v2 5.5）。
-- ・出現：エリアごとの出現点に置く。同じエリアにいるプレイヤーだけを狙う（町には出ないので、町は安全なまま）
-- ・攻撃：光る予備動作のあとに当てる。サンドホーンは砂の弾（狙った地点にいなければ当たらない）。
--   オオヌシは HP が減ると、ときどき周り全員への大技（吹き飛ばす）
-- ・自分に付与をかけるモンスター（アオハネ＝疾風、オオヌシ＝鉄壁）は「剥がす」の練習相手。剥がされたら少し後にかけ直す
-- ・倒すと素材とピースを抽選（DropLogic）。ボスはダメージを一定以上与えた全員がもらう
-- ・図鑑：出会った（狙われた・倒した）と、倒した数を保存する
-- ダメージは CombatService、カードとピースの増減は InventoryService を通す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local MonsterDefs = require(Shared:WaitForChild("MonsterDefs"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local DropLogic = require(Shared:WaitForChild("Logic"):WaitForChild("DropLogic"))

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local StateSync = require(script.Parent.StateSync)
local CombatService = require(script.Parent.CombatService)
local GrantService = require(script.Parent.GrantService)
local TravelService = require(script.Parent.TravelService)
local Metrics = require(script.Parent.Metrics)
local Remotes = require(script.Parent.Remotes)
local WorldMarkers = require(script.Parent.WorldMarkers)

local MonsterService = {}

local WARNING = Color3.fromRGB(230, 50, 40)
local RANGED_THRESHOLD = 20 -- 射程がこれ以上なら弾を撃つ

type Monster = {
	def: any,
	model: Model,
	body: BasePart,
	color: Color3,
	home: Vector3,
	height: number, -- 体の中心の高さ（地面からの高さ＋浮く高さ）
	target: Player?,
	nextAttackAt: number,
	attacking: boolean,
	attacks: number,
	strippedAt: number?,
}

local monsters: { Monster } = {}
local random = Random.new()

local function rng(): number
	return random:NextNumber()
end

local function toColor(rgb: { number }): Color3
	return Color3.fromRGB(rgb[1], rgb[2], rgb[3])
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function setColor(m: Monster, color: Color3)
	for _, part in m.model:GetDescendants() do
		if part:IsA("BasePart") and part.Name ~= "Eye" then
			part.Color = color
		end
	end
end

local function setVisible(m: Monster, visible: boolean)
	for _, part in m.model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 1
		elseif part:IsA("BillboardGui") then
			part.Enabled = visible
		end
	end
end

-- 図鑑 ------------------------------------------------------------------------

local function dexEntry(profile: any, monsterId: string): any
	local entry = profile.dex[monsterId]
	if type(entry) ~= "table" then
		entry = { seen = false, kills = 0 }
		profile.dex[monsterId] = entry
	end
	return entry
end

local function markSeen(player: Player, monsterId: string)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local entry = dexEntry(profile, monsterId)
	if not entry.seen then
		entry.seen = true
		StateSync.push(player, "dex")
	end
end

local function markKill(player: Player, monsterId: string)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local entry = dexEntry(profile, monsterId)
	entry.seen = true
	entry.kills = (entry.kills or 0) + 1
	StateSync.push(player, "dex")
end

-- ドロップ --------------------------------------------------------------------

local function giveDrops(player: Player, def: any)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local drop = DropLogic.roll(def, PieceDefs, Config.Drops.NormalPieceChance, profile.bossKills or 0, rng)
	if next(drop.items) ~= nil then
		local ok, reason = InventoryService.applyItems(player, { grant = drop.items })
		if not ok then
			Remotes.fire(player, "Toast", reason)
		end
	end
	if drop.piece then
		local ok, reason = InventoryService.addUnplacedPiece(player, drop.piece)
		if ok then
			Metrics.event(player, Metrics.Events.PieceGained, 1, if def.role == "boss" then "boss" else "drop")
		else
			Remotes.fire(player, "Toast", reason)
		end
	end
	if def.role == "boss" then
		profile.bossKills = (profile.bossKills or 0) + 1
		StateSync.push(player, "bossKills")
	end
	markKill(player, def.id)
end

-- 自分への付与（剥がされたら少し待ってかけ直す。TrainingDummy と同じ考え方）---------

local function regrant(m: Monster)
	local grant = m.def.selfGrant
	if grant and m.model:GetAttribute("Alive") and not GrantService.has(m.model, grant) then
		GrantService.apply(m.model, grant)
	end
end

-- 攻撃 ------------------------------------------------------------------------

local function rootPosition(player: Player): Vector3?
	local root = CombatService.rootOf(player)
	return if root then root.Position else nil
end

local function face(m: Monster, position: Vector3)
	local origin = m.model:GetPivot().Position
	local target = Vector3.new(position.X, origin.Y, position.Z)
	if (target - origin).Magnitude > 0.1 then
		m.model:PivotTo(CFrame.lookAt(origin, target))
	end
end

local function shootProjectile(from: Vector3, to: Vector3)
	local ball = Instance.new("Part")
	ball.Name = "SandShot"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.new(1.4, 1.4, 1.4)
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.Material = Enum.Material.Sand
	ball.Color = Color3.fromRGB(215, 185, 120)
	ball.Position = from
	ball.Parent = workspace
	TweenService:Create(ball, TweenInfo.new(Config.Monsters.ProjectileSeconds, Enum.EasingStyle.Linear), {
		Position = to,
	}):Play()
	task.delay(Config.Monsters.ProjectileSeconds + 0.1, ball.Destroy, ball)
end

-- 生きているか。倒れた体も自然回復で HP が 1 に戻ることがあるので、状態も見る
local function isAlive(player: Player): boolean
	local humanoid = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	return humanoid ~= nil and humanoid.Health > 0 and humanoid:GetState() ~= Enum.HumanoidStateType.Dead
end

-- 同じエリアにいて、生きているプレイヤー
local function playersInArea(areaId: string): { Player }
	local out = {}
	for _, player in Players:GetPlayers() do
		if isAlive(player) and TravelService.areaOf(player) == areaId and CombatService.rootOf(player) then
			table.insert(out, player)
		end
	end
	return out
end

local function attack(m: Monster, target: Player)
	m.attacking = true
	local def = m.def
	local boss = Config.Monsters.Boss
	local healthRatio = (m.model:GetAttribute("Health") or 0) / def.maxHealth
	local big = def.role == "boss" and healthRatio < boss.BigAttackBelow and (m.attacks % boss.BigAttackEvery) == boss.BigAttackEvery - 1
	local windup = if big then boss.BigWindupSeconds else Config.Monsters.WindupSeconds
	local aim = rootPosition(target)
	if aim then
		face(m, aim)
	end

	-- 予備動作：光る。アオハネは急降下のために少し下がる
	setColor(m, WARNING)
	m.model:SetAttribute("Telegraph", true)
	if def.id == "aohane" then
		m.model:PivotTo(m.model:GetPivot() - Vector3.new(0, Config.Monsters.Looks.aohane.hover * 0.6, 0))
	end
	local interrupted = false
	local elapsed = 0
	while elapsed < windup do
		elapsed += task.wait(0.05)
		if not m.model:GetAttribute("Alive") or CombatService.isStunned(m.model) then
			interrupted = true -- 締めで吹き飛ばされると攻撃は止まる
			break
		end
	end
	m.model:SetAttribute("Telegraph", false)
	setColor(m, m.color)

	if not interrupted and m.model:GetAttribute("Alive") then
		local origin = m.model:GetPivot().Position
		local damage = def.damage * (if big then boss.BigDamageMultiplier else 1)
		if def.attackRange >= RANGED_THRESHOLD then
			-- 砂の弾：撃った時点の位置を狙う。その間に動けば避けられる
			local aimAt = rootPosition(target) or aim
			if aimAt then
				shootProjectile(origin, aimAt)
				task.wait(Config.Monsters.ProjectileSeconds)
				local now = rootPosition(target)
				if now and (now - aimAt).Magnitude <= Config.Monsters.ProjectileHitRadius then
					CombatService.hitPlayer(nil, target, damage, m.model, { fromPosition = origin })
				end
			end
		elseif big then
			-- 大技：周りにいる全員を吹き飛ばす
			local range = def.attackRange * boss.BigRangeMultiplier
			for _, player in playersInArea(def.area) do
				local pos = rootPosition(player)
				if pos and (flat(pos) - flat(origin)).Magnitude <= range then
					CombatService.hitPlayer(nil, player, damage, m.model, { finisher = true, fromPosition = origin })
				end
			end
		else
			local pos = rootPosition(target)
			if pos and (flat(pos) - flat(origin)).Magnitude <= def.attackRange + 2 then
				CombatService.hitPlayer(nil, target, damage, m.model, { fromPosition = origin })
			end
		end
	end

	if def.id == "aohane" and m.model.Parent then
		local p = m.model:GetPivot()
		m.model:PivotTo(CFrame.new(p.Position.X, m.height, p.Position.Z) * p.Rotation)
	end
	m.attacks += 1
	m.nextAttackAt = os.clock() + def.attackInterval
	m.attacking = false
end

-- 動き ------------------------------------------------------------------------

local function validTarget(m: Monster, player: Player?): boolean
	if player == nil or player.Parent == nil then
		return false
	end
	local pos = rootPosition(player)
	if pos == nil or TravelService.areaOf(player) ~= m.def.area then
		return false
	end
	if not isAlive(player) then
		return false
	end
	return (flat(pos) - flat(m.home)).Magnitude <= Config.Monsters.LeashRange
end

local function findTarget(m: Monster): Player?
	local here = m.model:GetPivot().Position
	local best: Player? = nil
	local bestDistance = Config.Monsters.AggroRange
	for _, player in playersInArea(m.def.area) do
		local pos = rootPosition(player)
		if pos and validTarget(m, player) then
			local d = (flat(pos) - flat(here)).Magnitude
			if d <= bestDistance then
				best = player
				bestDistance = d
			end
		end
	end
	return best
end

local function moveToward(m: Monster, goal: Vector3, dt: number)
	local pivot = m.model:GetPivot()
	local here = pivot.Position
	local delta = flat(goal) - flat(here)
	if delta.Magnitude < 0.1 then
		return
	end
	local step = math.min(delta.Magnitude, m.def.moveSpeed * dt)
	local nextPos = Vector3.new(here.X, m.height, here.Z) + delta.Unit * step
	m.model:PivotTo(CFrame.lookAt(nextPos, nextPos + delta.Unit))
end

local function tickMonster(m: Monster, dt: number)
	if m.attacking or not m.model:GetAttribute("Alive") or CombatService.isStunned(m.model) then
		return
	end
	if not validTarget(m, m.target) then
		m.target = findTarget(m)
		if m.target then
			markSeen(m.target :: Player, m.def.id)
		end
	end
	local target = m.target
	if target == nil then
		-- 狙う相手がいなければ出現点へ戻る
		if (flat(m.model:GetPivot().Position) - flat(m.home)).Magnitude > 1 then
			moveToward(m, m.home, dt)
		end
		return
	end
	local pos = rootPosition(target) :: Vector3
	local distance = (flat(pos) - flat(m.model:GetPivot().Position)).Magnitude
	local reach = if m.def.attackRange >= RANGED_THRESHOLD then m.def.attackRange else math.max(2, m.def.attackRange * 0.8)
	if distance > reach then
		moveToward(m, pos, dt)
	elseif os.clock() >= m.nextAttackAt then
		task.spawn(attack, m, target)
	else
		face(m, pos)
	end
end

-- 作る ------------------------------------------------------------------------

local function buildModel(def: any, look: any, position: Vector3): (Model, BasePart)
	local model = Instance.new("Model")
	model.Name = def.id
	local size = WorldMarkers.toVector(look.size)
	local body = Instance.new("Part")
	body.Name = "Body"
	body.Shape = if def.id == "moripon" then Enum.PartType.Ball else Enum.PartType.Block
	body.Size = if def.id == "moripon" then Vector3.new(size.X, size.X, size.X) else size
	body.Anchored = true
	body.CanCollide = false
	body.Material = Enum.Material.SmoothPlastic
	body.Color = toColor(look.color)
	body.CFrame = CFrame.new(position)
	body.Parent = model

	-- 向きが分かるように、前に目を付ける
	local eye = Instance.new("Part")
	eye.Name = "Eye"
	eye.Size = Vector3.new(size.X * 0.5, size.Y * 0.2, 0.2)
	eye.Anchored = true
	eye.CanCollide = false
	eye.Material = Enum.Material.Neon
	eye.Color = Color3.fromRGB(255, 240, 200)
	eye.CFrame = CFrame.new(position + Vector3.new(0, size.Y * 0.15, -size.Z / 2 - 0.05))
	eye.Parent = model
	model.PrimaryPart = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(200, 44)
	billboard.StudsOffset = Vector3.new(0, size.Y / 2 + 2, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 70
	billboard.Parent = body
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	local function update()
		local health = model:GetAttribute("Health") or 0
		local grants = model:GetAttribute("Grants")
		local extra = if type(grants) == "string" and grants ~= "" then "  [付与中]" else ""
		local status = if model:GetAttribute("Telegraph") then "\n⚠ 攻撃の構え" else ""
		label.Text = ("%s  HP %d/%d%s%s"):format(def.nameJa, math.ceil(health :: number), def.maxHealth, extra, status)
	end
	model.AttributeChanged:Connect(update)
	model.Parent = workspace
	update()
	return model, body
end

local function spawnBase(entry: any): Vector3?
	local folder = workspace:FindFirstChild("MonsterSpawns")
	local marker = folder and folder:FindFirstChild(entry.monster)
	if marker and marker:IsA("BasePart") then
		return marker.Position + Vector3.new(0, marker.Size.Y / 2, 0)
	end
	local arrival = TravelService.arrivalOf(entry.area)
	if arrival == nil then
		return nil
	end
	return (arrival * CFrame.new(WorldMarkers.toVector(entry.offset))).Position
end

local function spawnMonster(def: any, ground: Vector3)
	local look = Config.Monsters.Looks[def.id]
	local height = ground.Y + look.size[2] / 2 + look.hover
	local home = Vector3.new(ground.X, height, ground.Z)
	local model, body = buildModel(def, look, home)
	local m: Monster = {
		def = def,
		model = model,
		body = body,
		color = toColor(look.color),
		home = home,
		height = height,
		target = nil,
		nextAttackAt = 0,
		attacking = false,
		attacks = 0,
		strippedAt = nil,
	}

	CombatService.registerEnemy(model, def.id, def.maxHealth, function(deadModel: Model, killer: Player?)
		-- ボスはダメージを一定以上与えた全員、通常は倒した人がドロップをもらう
		local recipients: { Player } = {}
		if def.role == "boss" then
			for player, dealt in CombatService.contributionsOf(deadModel) do
				if DropLogic.qualifies(dealt, def.maxHealth, Config.Drops.BossContributionRatio) then
					table.insert(recipients, player)
				end
			end
		elseif killer then
			table.insert(recipients, killer)
		end
		for _, player in recipients do
			giveDrops(player, def)
		end
		if killer then
			Metrics.event(killer, Metrics.Events.MonsterKilled, 1, def.id)
		end

		m.target = nil
		m.attacking = false
		deadModel:SetAttribute("Telegraph", false)
		setColor(m, m.color)
		setVisible(m, false)
		task.wait(if def.role == "boss" then Config.Monsters.BossRespawnSeconds else Config.Monsters.RespawnSeconds)
		deadModel:PivotTo(CFrame.new(home))
		m.attacks = 0
		m.nextAttackAt = 0
		CombatService.reviveEnemy(deadModel)
		setVisible(m, true)
		regrant(m)
	end)

	if def.selfGrant then
		model:GetAttributeChangedSignal("Grants"):Connect(function()
			if GrantService.has(model, def.selfGrant) then
				m.strippedAt = nil
			elseif m.strippedAt == nil then
				m.strippedAt = os.clock()
			end
		end)
		regrant(m)
	end
	table.insert(monsters, m)
end

function MonsterService.init()
	for _, entry in Config.Monsters.Spawns do
		local def = MonsterDefs[entry.monster]
		local base = spawnBase(entry)
		if def and base then
			for i = 1, entry.count do
				local angle = (i - 1) / entry.count * math.pi * 2
				local offset = if entry.spread > 0 then Vector3.new(math.cos(angle), 0, math.sin(angle)) * entry.spread else Vector3.zero
				spawnMonster(def, base + offset)
			end
		end
	end

	task.spawn(function()
		local last = os.clock()
		while true do
			task.wait(Config.Monsters.TickInterval)
			local t = os.clock()
			local dt = t - last
			last = t
			for _, m in monsters do
				local ok, err = pcall(tickMonster, m, dt)
				if not ok then
					warn("[MonsterService] " .. m.def.id .. ": " .. tostring(err))
				end
				if m.strippedAt and t - m.strippedAt >= Config.Monsters.RegrantSeconds then
					regrant(m)
				end
			end
		end
	end)
end

return MonsterService
