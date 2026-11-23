--!strict
-- 練習用の木人（Step 2 改訂：反撃してくる練習相手）。
-- ・自分を攻撃したプレイヤー（＝この木人と戦闘中のプレイヤー）にだけ反撃する。通りがかりの人は攻撃しない
-- ・反撃の流れ：相手の方を向く → 赤く光る予備動作（Config.Dummy.TelegraphSeconds 秒）→ 大振り
--   大振りは締め扱い（当たると吹き飛ばされる）。正面からガードすれば大きく減らせる。ダッシュで離れれば当たらない
--   予備動作中に 4 段コンボの締めで吹き飛ばせば、大振りを止められる
-- ・自分に鉄壁付与をかけている間は吹き飛ばない ＝ 大振りを止められない。先に「剥がす」と止められるようになる
-- ・倒されると Config.Dummy.RespawnSeconds 秒後に元の位置で復活する
-- 置き場所：Workspace に「DummySpawn」という Part があればその上、なければ Config.Dummy.DefaultPosition

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))

local BattleStateService = require(script.Parent.BattleStateService)
local CombatService = require(script.Parent.CombatService)
local GrantService = require(script.Parent.GrantService)

local TrainingDummy = {}

local WOOD = Color3.fromRGB(160, 116, 72)
local WARNING = Color3.fromRGB(230, 50, 40)

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

	-- 向きが分かるように「腕」を前に出す（大振りの向き）
	local arm = Instance.new("Part")
	arm.Name = "Arm"
	arm.Size = Vector3.new(0.8, 0.8, 3)
	arm.Anchored = true
	arm.Color = WOOD
	arm.Material = Enum.Material.Wood
	arm.CFrame = CFrame.new(position + Vector3.new(0, 1, -2.4))
	arm.Parent = model

	model.PrimaryPart = body

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Info"
	billboard.Size = UDim2.fromOffset(220, 60)
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
	local status = ""
	if model:GetAttribute("Stunned") then
		status = "\nひるみ！"
	elseif model:GetAttribute("Telegraph") then
		status = "\n⚠ 大振りの構え"
	end
	label.Text = ("練習用の木人  HP %d/%d\n%s%s"):format(math.ceil(health :: number), maxHealth :: number, grantText, status)
end

local function setColor(model: Model, color: Color3)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Color = color
		end
	end
end

local function setVisible(model: Model, visible: boolean)
	for _, part in model:GetDescendants() do
		if part:IsA("BasePart") then
			part.Transparency = if visible then 0 else 0.8
			part.CanCollide = visible
		end
	end
end

-- この木人と戦っている（＝この木人を攻撃した）プレイヤーのうち、一番近い人
local function findTarget(model: Model, range: number): Player?
	local origin = model:GetPivot().Position
	local best: Player? = nil
	local bestDistance = range
	for _, player in Players:GetPlayers() do
		local root = CombatService.rootOf(player)
		if root and BattleStateService.getPveTarget(player) == model then
			local d = (root.Position - origin).Magnitude
			if d <= bestDistance then
				best = player
				bestDistance = d
			end
		end
	end
	return best
end

-- 水平方向だけ相手の方を向く
local function face(model: Model, position: Vector3)
	local origin = model:GetPivot().Position
	local target = Vector3.new(position.X, origin.Y, position.Z)
	if (target - origin).Magnitude > 0.1 then
		model:PivotTo(CFrame.lookAt(origin, target))
	end
end

function TrainingDummy.init()
	local home = spawnPosition()
	local model, label = buildModel(home)

	local function regrant()
		if model:GetAttribute("Alive") and not GrantService.has(model, Config.Dummy.SelfGrant) then
			GrantService.apply(model, Config.Dummy.SelfGrant)
		end
	end

	CombatService.registerEnemy(model, "dummy", Config.Dummy.MaxHealth, function(deadModel: Model)
		deadModel:SetAttribute("Telegraph", false)
		setColor(deadModel, WOOD)
		setVisible(deadModel, false)
		task.wait(Config.Dummy.RespawnSeconds)
		deadModel:PivotTo(CFrame.new(home))
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

	-- 反撃のループ
	task.spawn(function()
		while model.Parent do
			task.wait(Config.Dummy.AttackInterval)
			if not model:GetAttribute("Alive") then
				continue
			end
			-- 押し出されすぎたら元の位置に戻る
			if (model:GetPivot().Position - home).Magnitude > Config.Dummy.ReturnDistance then
				model:PivotTo(CFrame.new(home))
			end
			if CombatService.isStunned(model) then
				continue
			end
			local target = findTarget(model, Config.Dummy.AttackRange + 6)
			local root = target and CombatService.rootOf(target)
			if not root then
				continue
			end

			face(model, root.Position)
			model:SetAttribute("Telegraph", true)
			setColor(model, WARNING)

			-- 予備動作の間ずっと見張る。一度でもひるんだ（締めで吹き飛ばされた）・倒されたら大振りは出ない
			-- （ひるみ 0.6 秒は予備動作 0.8 秒より短いので、最後に 1 回確かめるだけだと止められないことがある）
			local interrupted = false
			local elapsed = 0
			while elapsed < Config.Dummy.TelegraphSeconds do
				elapsed += task.wait(0.05)
				if CombatService.isStunned(model) or not model:GetAttribute("Alive") then
					interrupted = true
					break
				end
			end
			model:SetAttribute("Telegraph", false)
			setColor(model, WOOD)

			if not interrupted then
				CombatService.enemySwing(model, Config.Dummy.AttackDamage, Config.Dummy.AttackRange)
			end
		end
	end)
end

return TrainingDummy
