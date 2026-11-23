--!strict
-- 練習用の木人（Step 2）。モンスターを作る前に、攻撃・付与・剥がし・必殺技を試す相手。
-- ・攻撃はしてこない
-- ・自分に鉄壁付与をかけ、剥がされても Config.Dummy.RegrantSeconds 秒後にかけ直す
-- ・倒されると Config.Dummy.RespawnSeconds 秒後に復活する
-- 置き場所：Workspace に「DummySpawn」という Part があればその上、なければ Config.Dummy.DefaultPosition

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))

local CombatService = require(script.Parent.CombatService)
local GrantService = require(script.Parent.GrantService)

local TrainingDummy = {}

local WOOD = Color3.fromRGB(160, 116, 72)

local function spawnPosition(): Vector3
	local marker = workspace:FindFirstChild("DummySpawn")
	if marker and marker:IsA("BasePart") then
		return marker.Position + Vector3.new(0, marker.Size.Y / 2 + 2.5, 0)
	end
	local p = Config.Dummy.DefaultPosition
	return Vector3.new(p[1], p[2], p[3])
end

local function buildModel(position: Vector3): (Model, TextLabel)
	local model = Instance.new("Model")
	model.Name = "TrainingDummy"

	local body = Instance.new("Part")
	body.Name = "Body"
	body.Size = Vector3.new(2.5, 5, 2.5)
	body.Anchored = true
	body.Color = WOOD
	body.Material = Enum.Material.Wood
	body.CFrame = CFrame.new(position)
	body.Parent = model

	local head = Instance.new("Part")
	head.Name = "Head"
	head.Shape = Enum.PartType.Ball
	head.Size = Vector3.new(2.2, 2.2, 2.2)
	head.Anchored = true
	head.Color = WOOD
	head.Material = Enum.Material.Wood
	head.CFrame = CFrame.new(position + Vector3.new(0, 3.6, 0))
	head.Parent = model

	model.PrimaryPart = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(200, 50)
	billboard.StudsOffset = Vector3.new(0, 6, 0)
	billboard.AlwaysOnTop = true
	billboard.MaxDistance = 80
	billboard.Parent = body

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 14
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.4
	label.Parent = billboard

	model.Parent = workspace
	return model, label
end

local function updateLabel(model: Model, label: TextLabel)
	local health = model:GetAttribute("Health") or 0
	local maxHealth = model:GetAttribute("MaxHealth") or 0
	local grants = model:GetAttribute("Grants")
	local names = {}
	if type(grants) == "string" and grants ~= "" then
		for _, id in string.split(grants, ",") do
			local def = AbilityDefs[id]
			table.insert(names, if def then def.nameJa else id)
		end
	end
	local grantText = if #names > 0 then table.concat(names, "・") else "付与なし"
	label.Text = ("練習用の木人  HP %d/%d\n%s"):format(math.ceil(health :: number), maxHealth :: number, grantText)
end

local function setVisible(model: Model, visible: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 0.8
			part.CanCollide = visible
		end
	end
end

function TrainingDummy.init()
	local model, label = buildModel(spawnPosition())

	local function regrant()
		local alive = model:GetAttribute("Alive")
		if alive and not GrantService.has(model, Config.Dummy.SelfGrant) then
			GrantService.apply(model, Config.Dummy.SelfGrant)
		end
	end

	CombatService.registerEnemy(model, "dummy", Config.Dummy.MaxHealth, function(deadModel: Model)
		setVisible(deadModel, false)
		task.wait(Config.Dummy.RespawnSeconds)
		CombatService.reviveEnemy(deadModel)
		setVisible(deadModel, true)
		regrant()
	end)

	model.AttributeChanged:Connect(function()
		updateLabel(model, label)
	end)
	regrant()
	updateLabel(model, label)

	-- 剥がされたら少し待ってかけ直す
	task.spawn(function()
		while model.Parent do
			task.wait(Config.Dummy.RegrantSeconds)
			regrant()
		end
	end)
end

return TrainingDummy
