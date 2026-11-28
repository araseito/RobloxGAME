--!strict
-- 町の掲示板のクエストと、探索ピースの隠し場所（PHASE0_PLAN_v2 2 章の 7・8、5.3）。
-- ・クエストは受注しない。倒した・作ったを常に数え、目標に届いたら自動で報酬を渡す
-- ・探索ピースは ProximityPrompt で拾う。拾ったかどうかは人ごとに保存し、見た目はクライアントが人ごとに隠す
-- ・ピースの増減は InventoryService を通す

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local QuestDefs = require(Shared:WaitForChild("QuestDefs"))
local AreaDefs = require(Shared:WaitForChild("AreaDefs"))
local QuestLogic = require(Shared:WaitForChild("Logic"):WaitForChild("QuestLogic"))

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local StateSync = require(script.Parent.StateSync)
local Metrics = require(script.Parent.Metrics)
local Remotes = require(script.Parent.Remotes)
local CombatService = require(script.Parent.CombatService)
local WorldMarkers = require(script.Parent.WorldMarkers)
local TravelService = require(script.Parent.TravelService)

local QuestService = {}

-- クライアントと共有するタグ名（見た目を人ごとに変えるため）
QuestService.EXPLORE_TAG = "ExploreSpot"
QuestService.BOARD_TAG = "QuestBoard"

local spots: { [string]: BasePart } = {}

local toVector = WorldMarkers.toVector
local spawnCFrame = WorldMarkers.spawnCFrame

-- 報酬 -----------------------------------------------------------------------

-- 目標に届いたクエストの報酬を渡す。ピースが持ちきれないときは渡さずに残し、次の機会にもう一度試す
local function grantPending(player: Player, profile: any)
	local changedAreas = false
	for _, questId in QuestLogic.pending(profile.quests, QuestDefs) do
		local reward = QuestDefs[questId].reward
		if reward.piece then
			local ok, reason = InventoryService.addUnplacedPiece(player, reward.piece)
			if not ok then
				Remotes.fire(player, "Toast", reason)
				continue
			end
			Metrics.event(player, Metrics.Events.PieceGained, 1, "quest")
		end
		if reward.unlockArea then
			profile.areas[reward.unlockArea] = true
			changedAreas = true
		end
		profile.quests = QuestLogic.markDone(profile.quests, questId)
		Metrics.event(player, Metrics.Events.QuestCompleted, 1, questId)
	end
	StateSync.push(player, "quests")
	if changedAreas then
		StateSync.push(player, "areas")
	end
end

-- 出来事を記録する。event = { kind = "kill", monster = id } / { kind = "craft", item = id }
function QuestService.record(player: Player, event: QuestLogic.Event)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local quests, changed = QuestLogic.record(profile.quests, QuestDefs, event)
	if not changed then
		return
	end
	profile.quests = quests
	grantPending(player, profile)
end

-- 持ちきれずに残っていた報酬を、もう一度渡してみる（読み込み時・ピースをはめた後）
function QuestService.retryPending(player: Player)
	local profile = DataService.getProfile(player)
	if profile and #QuestLogic.pending(profile.quests, QuestDefs) > 0 then
		grantPending(player, profile)
	end
end

-- 探索ピース -----------------------------------------------------------------

function QuestService.pickUp(player: Player, spotId: string): (boolean, string?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	if profile.exploreFound[spotId] then
		return false, "already_found"
	end
	local pieceId = QuestLogic.explorePiece(spotId, PieceDefs)
	local spot = spots[spotId]
	if pieceId == nil or spot == nil then
		return false, "unknown_id"
	end
	local root = CombatService.rootOf(player)
	if root == nil then
		return false, "dead"
	end
	if (root.Position - spot.Position).Magnitude > Config.Explore.PromptDistance + Config.Explore.PickupTolerance then
		return false, "out_of_range"
	end
	local ok, reason = InventoryService.addUnplacedPiece(player, pieceId)
	if not ok then
		return false, reason
	end
	profile.exploreFound[spotId] = true
	StateSync.push(player, "exploreFound")
	Metrics.event(player, Metrics.Events.PieceGained, 1, "explore")
	Metrics.onboarding(player, profile, 2)
	return true, nil
end

local function spotPosition(spotId: string): Vector3?
	local marker = WorldMarkers.find("ExploreSpot_" .. spotId)
	if marker then
		return marker.Position + Vector3.new(0, marker.Size.Y / 2 + 1.5, 0)
	end
	-- 印がないときは、町の隠し場所（最初の 1 つ）はスポーン地点の目の前に出す
	if table.find(AreaDefs.town.exploreSpots, spotId) then
		return spawnCFrame() * toVector(Config.Explore.SpawnOffset)
	end
	-- それ以外は、そのエリアの到着地点から決まった位置（固定の隠し場所）
	local offset = Config.Explore.AreaOffsets[spotId]
	for areaId, area in AreaDefs do
		local arrival = TravelService.arrivalOf(areaId)
		if offset and arrival and table.find(area.exploreSpots, spotId) then
			return arrival * toVector(offset)
		end
	end
	return nil
end

local function buildSpot(spotId: string, position: Vector3): BasePart
	local part = Instance.new("Part")
	part.Name = "Piece_" .. spotId
	part.Shape = Enum.PartType.Ball
	part.Size = Vector3.new(1.6, 1.6, 1.6)
	part.Anchored = true
	part.CanCollide = false
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(150, 200, 255)
	part.Position = position
	part:SetAttribute("SpotId", spotId)

	local light = Instance.new("PointLight")
	light.Color = part.Color
	light.Range = 10
	light.Brightness = 2
	light.Parent = part

	local sparkles = Instance.new("Sparkles")
	sparkles.SparkleColor = part.Color
	sparkles.Parent = part

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "拾う"
	prompt.ObjectText = "光るピース"
	prompt.MaxActivationDistance = Config.Explore.PromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = part
	prompt.Triggered:Connect(function(player: Player)
		local ok, reason = QuestService.pickUp(player, spotId)
		if not ok then
			Remotes.fire(player, "Toast", reason)
		end
	end)

	CollectionService:AddTag(part, QuestService.EXPLORE_TAG)
	part.Parent = workspace
	return part
end

-- 掲示板 ---------------------------------------------------------------------

local function buildBoard()
	local marker = WorldMarkers.find("QuestBoard")
	local board: BasePart
	if marker then
		board = marker
	else
		local base = spawnCFrame() * CFrame.new(toVector(Config.QuestBoard.SpawnOffset))
		local part = Instance.new("Part")
		part.Name = "QuestBoard"
		part.Size = Vector3.new(7, 5, 0.6)
		part.Anchored = true
		part.Material = Enum.Material.Wood
		part.Color = Color3.fromRGB(150, 105, 60)
		-- 地面から少し浮かせて立て、スポーン地点の方を向ける
		local center = base.Position + Vector3.new(0, 3.5, 0)
		local spawnPos = spawnCFrame().Position
		part.CFrame = CFrame.lookAt(center, Vector3.new(spawnPos.X, center.Y, spawnPos.Z))
		part.Parent = workspace

		local gui = Instance.new("SurfaceGui")
		gui.Face = Enum.NormalId.Front
		gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		gui.PixelsPerStud = 40
		gui.Parent = part
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(255, 245, 220)
		label.Text = "掲示板\nQuest Board"
		label.Parent = gui
		board = part
	end

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "見る"
	prompt.ObjectText = "掲示板"
	prompt.MaxActivationDistance = Config.QuestBoard.PromptDistance
	prompt.HoldDuration = 0
	prompt.RequiresLineOfSight = false
	prompt.Parent = board
	CollectionService:AddTag(board, QuestService.BOARD_TAG)
end

function QuestService.init()
	buildBoard()
	for _, area in AreaDefs do
		for _, spotId in area.exploreSpots do
			local position = spotPosition(spotId)
			if position then
				spots[spotId] = buildSpot(spotId, position)
			end
		end
	end
end

return QuestService
