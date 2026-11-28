--!strict
-- エリアと選択式の移動（PHASE0_PLAN_v2 5.7）。
-- ・画面の「行き先」から選ぶと、その場所の入口へ移る（同じサーバーの中）
-- ・ダンジョンはクエスト 1 の報酬で解放（profile.areas）
-- ・今いるエリアはプレイヤーの属性 "Area" に書く（表示用。判定はサーバーのこの値で行う）
-- 地形は Studio 側で作る。到着地点の印がないエリアは、仮の足場をコードで作る

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AreaDefs = require(Shared:WaitForChild("AreaDefs"))

local DataService = require(script.Parent.DataService)
local CombatService = require(script.Parent.CombatService)
local DuelRingService = require(script.Parent.DuelRingService)
local Metrics = require(script.Parent.Metrics)
local WorldMarkers = require(script.Parent.WorldMarkers)

local TravelService = {}

local AREA_ATTRIBUTE = "Area"
local HOME_AREA = "town"

local arrivals: { [string]: CFrame } = {} -- 到着地点（足元の高さ）
local lastTravelAt: { [Player]: number } = {}

local PLACEHOLDER_COLORS: { [string]: Color3 } = {
	satoyama = Color3.fromRGB(96, 150, 84),
	dungeon = Color3.fromRGB(150, 92, 70),
}

local function findSpawnMarker(name: string): BasePart?
	local folder = workspace:FindFirstChild("Spawns")
	local marker = folder and folder:FindFirstChild(name)
	if marker and marker:IsA("BasePart") then
		return marker
	end
	return nil
end

-- 印がないエリアに、目印になる仮の足場を作る
local function buildPlaceholder(areaId: string, origin: CFrame): CFrame
	local size = Config.Travel.PlaceholderSize
	local floor = Instance.new("Part")
	floor.Name = "Placeholder_" .. areaId
	floor.Anchored = true
	floor.Size = Vector3.new(size, 2, size)
	floor.CFrame = origin * CFrame.new(0, -1, 0)
	floor.Material = if areaId == "dungeon" then Enum.Material.Rock else Enum.Material.Grass
	floor.Color = PLACEHOLDER_COLORS[areaId] or Color3.fromRGB(120, 120, 120)
	floor.Parent = workspace

	local def = AreaDefs[areaId]
	local sign = Instance.new("Part")
	sign.Name = "AreaSign_" .. areaId
	sign.Anchored = true
	sign.Size = Vector3.new(10, 4, 0.5)
	sign.CFrame = origin * CFrame.new(0, 5, -12)
	sign.Material = Enum.Material.Wood
	sign.Color = Color3.fromRGB(150, 105, 60)
	sign.Parent = workspace
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.Parent = sign
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = Color3.fromRGB(255, 245, 220)
	label.Text = ("%s\n%s"):format(def.nameJa, def.nameEn)
	label.Parent = gui
	return origin
end

local function resolveArrival(areaId: string): CFrame
	local def = AreaDefs[areaId]
	local marker = findSpawnMarker(def.spawnPart)
	if marker then
		return marker.CFrame * CFrame.new(0, marker.Size.Y / 2, 0)
	end
	local spawn = WorldMarkers.spawnCFrame()
	if areaId == HOME_AREA then
		return spawn * CFrame.new(0, 0.5, 0)
	end
	local offset = Config.Travel.PlaceholderOffsets[areaId] or { 0, 0, 0 }
	local origin = CFrame.new(spawn.Position + WorldMarkers.toVector(offset) + Vector3.new(0, 0.5, 0))
	return buildPlaceholder(areaId, origin)
end

function TravelService.areaOf(player: Player): string
	local area = player:GetAttribute(AREA_ATTRIBUTE)
	return if type(area) == "string" and AreaDefs[area] then area else HOME_AREA
end

function TravelService.isInTown(player: Player): boolean
	return TravelService.areaOf(player) == HOME_AREA
end

-- エリアの到着地点（モンスターや隠し場所の置き場所の基準）
function TravelService.arrivalOf(areaId: string): CFrame?
	return arrivals[areaId]
end

function TravelService.travel(player: Player, areaId: any): (boolean, string?)
	if type(areaId) ~= "string" or AreaDefs[areaId] == nil then
		return false, "unknown_id"
	end
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	if not profile.areas[areaId] then
		return false, "area_locked"
	end
	if DuelRingService.isLocked(player) then
		return false, "ring_locked_travel"
	end
	local root = CombatService.rootOf(player)
	if root == nil then
		return false, "dead"
	end
	local t = os.clock()
	if t - (lastTravelAt[player] or -math.huge) < Config.Travel.Cooldown then
		return false, "travel_cooldown"
	end
	lastTravelAt[player] = t

	local arrival = arrivals[areaId]
	local character = player.Character :: Model
	-- 足元が地面に来るよう、HumanoidRootPart の高さ分だけ上に置く
	character:PivotTo(arrival * CFrame.new(0, 3, 0))
	player:SetAttribute(AREA_ATTRIBUTE, areaId)
	if areaId == "satoyama" then
		Metrics.onboarding(player, profile, 4) -- 最初の 60 秒の 4 段目（里山へ）
	end
	return true, nil
end

function TravelService.init()
	for areaId in AreaDefs do
		arrivals[areaId] = resolveArrival(areaId)
	end
	local function onPlayer(player: Player)
		player:SetAttribute(AREA_ATTRIBUTE, HOME_AREA)
		-- 倒れて復活すると町のスポーン地点に戻る
		player.CharacterAdded:Connect(function()
			player:SetAttribute(AREA_ATTRIBUTE, HOME_AREA)
		end)
	end
	Players.PlayerAdded:Connect(onPlayer)
	for _, player in Players:GetPlayers() do
		onPlayer(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		lastTravelAt[player] = nil
	end)
end

return TravelService
