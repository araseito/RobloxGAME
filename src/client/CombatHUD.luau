--!strict
-- 戦闘の操作ボタンと表示（仮の見た目。手触りは後でダイスケさんが調整する）
-- ・右側（パズルボックスの下）：2 列のボタン
--     攻撃 / ガード / ダッシュ / 疾風 / 剛力 / 鉄壁 / 全解除 / 剥がす / 必殺技
-- ・下中央：状態（通常・戦闘中・ガード・ひるみ）、4 段コンボの段、付与の使用量、ゲージ、装備ボタン
-- キーボード：F 攻撃（続けて押すと 4 段コンボ）、E ガード（押している間）、C ダッシュ、
--             1/2/3 付与の付け外し、R 全解除、G 剥がす、Q 必殺技
-- ボタンは「やりたいこと」をサーバーに頼むだけ。可否はすべてサーバーが決める。
-- 例外：ダッシュと吹き飛ばしの「動き」は、キャラクターを動かしている本人の端末が出す（可否はサーバー）

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local Net = require(Shared:WaitForChild("Net"))

local StateStore = require(script.Parent.StateStore)
local Toast = require(script.Parent.Toast)
local Messages = require(script.Parent.Messages)

local CombatHUD = {}

local player = Players.LocalPlayer
local ENEMY_TAG = "Enemy" -- CombatService.ENEMY_TAG と同じ

local COLOR_BUTTON = Color3.fromRGB(36, 42, 66)
local COLOR_ACTIVE = Color3.fromRGB(70, 150, 230)
local COLOR_COOLDOWN = Color3.fromRGB(60, 60, 60)
local COLOR_READY = Color3.fromRGB(235, 170, 40)

local abilityOrder: { string } = {}
for id in AbilityDefs do
	table.insert(abilityOrder, id)
end
table.sort(abilityOrder, function(a, b)
	return AbilityDefs[a].order < AbilityDefs[b].order
end)

local abilityButtons: { [string]: TextButton } = {}
local ultimateButton: TextButton? = nil
local guardButton: TextButton? = nil
local dashButton: TextButton? = nil
local grantLabel: TextLabel? = nil
local gaugeFill: Frame? = nil
local statusLabel: TextLabel? = nil
local perkLabel: TextLabel? = nil
local equipRow: Frame? = nil

-- サーバーへの依頼 -----------------------------------------------------------

local function invoke(name: string, ...: any): any
	local remote = Net.getFunction(name)
	local ok, response = pcall(remote.InvokeServer, remote, ...)
	if not ok then
		Toast.show("通信に失敗しました")
		return nil
	end
	if type(response) == "table" and not response.ok then
		Toast.show(Messages.text(response.reason))
	end
	return response
end

local function combatState(): any
	return StateStore.state.combat
end

local function grantActive(abilityId: string): boolean
	local combat = combatState()
	if not combat then
		return false
	end
	return table.find(combat.grants.list, abilityId) ~= nil
end

local function rootPart(): BasePart?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end

-- 自分のキャラクターを一定時間、決まった速度で動かす（ダッシュ・吹き飛ばし）
local function push(velocity: Vector3, duration: number)
	local root = rootPart()
	if not root then
		return
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = "PushAttachment"
	attachment.Parent = root
	local mover = Instance.new("LinearVelocity")
	mover.Name = "Push"
	mover.Attachment0 = attachment
	mover.RelativeTo = Enum.ActuatorRelativeTo.World
	mover.MaxForce = math.huge
	mover.VectorVelocity = velocity
	mover.Parent = root
	task.delay(duration, function()
		mover:Destroy()
		attachment:Destroy()
	end)
end

-- 一番近い攻撃対象：射程内の敵 → いなければ射程内の他のプレイヤー
-- （他のプレイヤーへの攻撃はサーバーで無効になる。それを確かめるためにも送る）
local function findAttackTarget(): Model?
	local root = rootPart()
	if not root then
		return nil
	end
	local range = Config.Combat.BasicRange + Config.Combat.RangeTolerance
	local best: Model? = nil
	local bestDistance = range
	for _, tagged in CollectionService:GetTagged(ENEMY_TAG) do
		if tagged:IsA("Model") and tagged:GetAttribute("Alive") then
			local d = (tagged:GetPivot().Position - root.Position).Magnitude
			if d <= bestDistance then
				best = tagged
				bestDistance = d
			end
		end
	end
	if best then
		return best
	end
	for _, other in Players:GetPlayers() do
		local otherCharacter = other.Character
		if other ~= player and otherCharacter then
			local d = (otherCharacter:GetPivot().Position - root.Position).Magnitude
			if d <= bestDistance then
				best = otherCharacter
				bestDistance = d
			end
		end
	end
	return best
end

local function attack()
	local target = findAttackTarget()
	if target == nil then
		Toast.show("近くに攻撃できる相手がいません", 1)
		return
	end
	Net.getEvent("Attack"):FireServer(target)
end

local guardHeld = false
local function setGuard(on: boolean)
	if guardHeld == on then
		return
	end
	guardHeld = on
	task.spawn(invoke, "Action", "guard", on)
end

local function dash()
	task.spawn(function()
		local response = invoke("Action", "dash")
		if not (type(response) == "table" and response.ok) then
			return
		end
		local root = rootPart()
		local character = player.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if not root or not humanoid then
			return
		end
		-- 動いている方向へ。止まっていれば向いている方向へ
		local direction = humanoid.MoveDirection
		if direction.Magnitude < 0.1 then
			direction = root.CFrame.LookVector
		end
		direction = Vector3.new(direction.X, 0, direction.Z).Unit
		push(direction * Config.Combat.Dash.Speed, Config.Combat.Dash.Duration)
	end)
end

local function toggleAbility(abilityId: string)
	task.spawn(function()
		if grantActive(abilityId) then
			invoke("Grant_Release", abilityId)
		else
			invoke("Grant_Apply", abilityId)
		end
	end)
end

-- 剥がす：近くの敵の付与のうち、一番コストの高いものを頼む。
-- 剥がす相手（今戦っている敵）はサーバーが決める。食い違えば not_active で返る
local function strip()
	local candidates: { string } = {}
	local root = rootPart()
	if root then
		local bestDistance = Config.Grant.StripRange
		for _, tagged in CollectionService:GetTagged(ENEMY_TAG) do
			local grants = tagged:GetAttribute("Grants")
			if tagged:IsA("Model") and type(grants) == "string" and grants ~= "" then
				local d = (tagged:GetPivot().Position - root.Position).Magnitude
				if d <= bestDistance then
					bestDistance = d
					candidates = string.split(grants, ",")
				end
			end
		end
	end
	if #candidates == 0 then
		Toast.show(Messages.text("no_target"))
		return
	end
	table.sort(candidates, function(a, b)
		local ca = if AbilityDefs[a] then AbilityDefs[a].cost else 0
		local cb = if AbilityDefs[b] then AbilityDefs[b].cost else 0
		return ca > cb
	end)
	task.spawn(invoke, "Grant_Strip", candidates[1])
end

local function castUltimate()
	task.spawn(invoke, "Ultimate_Cast")
end

-- 見た目 --------------------------------------------------------------------

-- 先頭の 2 文字（「疾風付与」→「疾風」）。日本語は 1 文字が複数バイトなので utf8 で数える
local function shortName(name: string): string
	local cut = utf8.offset(name, 3)
	return if cut then string.sub(name, 1, cut - 1) else name
end

local function makeButton(parent: Instance, name: string, text: string, order: number, onClick: (() -> ())?): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(88, 36)
	button.BackgroundColor3 = COLOR_BUTTON
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 13
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	if onClick then
		button.Activated:Connect(onClick)
	end
	return button
end

local function refreshEquipRow()
	local row = equipRow
	if not row then
		return
	end
	for _, child in row:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local items = StateStore.state.items or {}
	local equipped = StateStore.state.equipped or {}
	local order = 0
	for _, slot in { "weapon", "armor" } do
		for itemId, def in ItemDefs do
			if def.category == slot and (items[itemId] or 0) > 0 then
				order += 1
				local isOn = equipped[slot] == itemId
				local button = makeButton(row, itemId, (if isOn then "外す：" else "装備：") .. def.nameJa, order, function()
					if isOn then
						task.spawn(invoke, "Action", "unequip", slot)
					else
						task.spawn(invoke, "Action", "equip", itemId)
					end
				end)
				button.Size = UDim2.fromOffset(130, 28)
				button.BackgroundColor3 = if isOn then COLOR_ACTIVE else COLOR_BUTTON
			end
		end
	end
end

local function refreshCombat()
	local combat = combatState()
	if not combat then
		return
	end
	local now = workspace:GetServerTimeNow()
	local stunned = (combat.stunnedUntil or 0) > now

	for abilityId, button in abilityButtons do
		local def = AbilityDefs[abilityId]
		local readyAt = combat.grants.cooldownEnds[abilityId]
		local name = shortName(def.nameJa)
		if grantActive(abilityId) then
			button.BackgroundColor3 = COLOR_ACTIVE
			button.Text = ("%s ON (%d)"):format(name, def.cost)
		elseif readyAt and readyAt > now then
			button.BackgroundColor3 = COLOR_COOLDOWN
			button.Text = ("%s %ds"):format(name, math.ceil(readyAt - now))
		else
			button.BackgroundColor3 = COLOR_BUTTON
			button.Text = ("%s (%d) [%d]"):format(name, def.cost, def.order)
		end
	end

	if guardButton then
		guardButton.BackgroundColor3 = if combat.guarding then COLOR_ACTIVE else COLOR_BUTTON
	end
	if dashButton then
		local readyAt = combat.dashReadyAt or 0
		if readyAt > now then
			dashButton.BackgroundColor3 = COLOR_COOLDOWN
			dashButton.Text = ("ダッシュ %.1fs"):format(readyAt - now)
		else
			dashButton.BackgroundColor3 = COLOR_BUTTON
			dashButton.Text = "ダッシュ [C]"
		end
	end

	-- 付けている付与の「できること」
	if perkLabel then
		local perks = {}
		for _, abilityId in combat.grants.list do
			local def = AbilityDefs[abilityId]
			if def then
				table.insert(perks, shortName(def.nameJa) .. "：" .. def.perkJa)
			end
		end
		perkLabel.Text = if #perks > 0 then table.concat(perks, "\n") else "付与なし"
	end

	if grantLabel then
		grantLabel.Text = ("付与 %d / %d%s"):format(
			combat.grants.used,
			combat.grants.capacity,
			if combat.shield > 0 then ("　シールド %d"):format(math.ceil(combat.shield)) else ""
		)
	end
	if gaugeFill then
		local ratio = math.clamp(combat.gauge / combat.gaugeMax, 0, 1)
		gaugeFill.Size = UDim2.fromScale(ratio, 1)
		gaugeFill.BackgroundColor3 = if ratio >= 1 then COLOR_READY else Color3.fromRGB(110, 170, 255)
	end
	if statusLabel then
		local text
		if stunned then
			text = "ひるみ！"
		elseif combat.casting then
			text = "詠唱中…"
		elseif combat.guarding then
			text = "ガード中"
		elseif combat.inCombat then
			text = "戦闘中"
		else
			text = "通常"
		end
		if combat.inCombat and (combat.comboStep or 0) > 0 then
			text ..= ("　コンボ %d/%d"):format(combat.comboStep, combat.comboHits)
		end
		statusLabel.Text = text
		statusLabel.TextColor3 = if stunned
			then Color3.fromRGB(255, 220, 80)
			elseif combat.inCombat then Color3.fromRGB(255, 120, 100)
			else Color3.fromRGB(180, 180, 190)
	end
	if ultimateButton then
		local ready = combat.inCombat and combat.gauge >= combat.gaugeMax and not combat.casting
		ultimateButton.BackgroundColor3 = if ready then COLOR_READY else COLOR_COOLDOWN
	end
end

local function makeLabel(parent: Instance, name: string, order: number, textSize: number): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.LayoutOrder = order
	label.Size = UDim2.new(1, 0, 0, 0)
	label.AutomaticSize = Enum.AutomaticSize.Y
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = textSize
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.Text = ""
	label.Parent = parent
	return label
end

function CombatHUD.mount(gui: ScreenGui)
	-- 右側（パズルボックスの下）に 2 列で並べる。縦 1 列だとボックスや画面下にはみ出す
	local grid = Instance.new("Frame")
	grid.Name = "CombatButtons"
	grid.AnchorPoint = Vector2.new(1, 0)
	grid.Position = UDim2.new(1, -12, 0, 184)
	grid.Size = UDim2.fromOffset(180, 0)
	grid.AutomaticSize = Enum.AutomaticSize.Y
	grid.BackgroundTransparency = 1
	grid.Parent = gui
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(88, 36)
	layout.CellPadding = UDim2.fromOffset(4, 4)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	makeButton(grid, "Attack", "攻撃 [F]", 1, attack)

	-- ガードは押している間だけ
	local guard = makeButton(grid, "Guard", "ガード [E]", 2, nil)
	guard.InputBegan:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setGuard(true)
		end
	end)
	guard.InputEnded:Connect(function(input)
		if input.UserInputType == Enum.UserInputType.MouseButton1 or input.UserInputType == Enum.UserInputType.Touch then
			setGuard(false)
		end
	end)
	guardButton = guard

	dashButton = makeButton(grid, "Dash", "ダッシュ [C]", 3, dash)
	makeButton(grid, "Strip", "剥がす [G]", 4, strip)
	for i, abilityId in abilityOrder do
		abilityButtons[abilityId] = makeButton(grid, abilityId, AbilityDefs[abilityId].nameJa, 4 + i, function()
			toggleAbility(abilityId)
		end)
	end
	makeButton(grid, "ReleaseAll", "全解除 [R]", 8, function()
		task.spawn(invoke, "Grant_Release", "all")
	end)
	ultimateButton = makeButton(grid, "Ultimate", "必殺技 [Q]", 9, castUltimate)

	-- 下中央の表示
	local panel = Instance.new("Frame")
	panel.Name = "CombatPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -12)
	panel.Size = UDim2.fromOffset(320, 0)
	panel.AutomaticSize = Enum.AutomaticSize.Y
	panel.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	panel.BackgroundTransparency = 0.25
	panel.Parent = gui
	local panelCorner = Instance.new("UICorner")
	panelCorner.CornerRadius = UDim.new(0, 8)
	panelCorner.Parent = panel
	local panelPadding = Instance.new("UIPadding")
	panelPadding.PaddingTop = UDim.new(0, 6)
	panelPadding.PaddingBottom = UDim.new(0, 6)
	panelPadding.PaddingLeft = UDim.new(0, 8)
	panelPadding.PaddingRight = UDim.new(0, 8)
	panelPadding.Parent = panel
	local panelList = Instance.new("UIListLayout")
	panelList.Padding = UDim.new(0, 4)
	panelList.SortOrder = Enum.SortOrder.LayoutOrder
	panelList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	panelList.Parent = panel

	statusLabel = makeLabel(panel, "Status", 1, 15)
	statusLabel.Text = "通常"
	grantLabel = makeLabel(panel, "Grants", 2, 14)

	local gaugeBack = Instance.new("Frame")
	gaugeBack.Name = "Gauge"
	gaugeBack.LayoutOrder = 3
	gaugeBack.Size = UDim2.new(1, 0, 0, 10)
	gaugeBack.BackgroundColor3 = Color3.fromRGB(40, 40, 50)
	gaugeBack.Parent = panel
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(110, 170, 255)
	fill.BorderSizePixel = 0
	fill.Parent = gaugeBack
	gaugeFill = fill

	perkLabel = makeLabel(panel, "Perks", 4, 12)
	perkLabel.Font = Enum.Font.Gotham
	perkLabel.TextColor3 = Color3.fromRGB(200, 210, 230)

	local row = Instance.new("Frame")
	row.Name = "Equip"
	row.LayoutOrder = 5
	row.Size = UDim2.new(1, 0, 0, 0)
	row.AutomaticSize = Enum.AutomaticSize.Y
	row.BackgroundTransparency = 1
	row.Parent = panel
	local rowList = Instance.new("UIListLayout")
	rowList.FillDirection = Enum.FillDirection.Horizontal
	rowList.HorizontalAlignment = Enum.HorizontalAlignment.Center
	rowList.Padding = UDim.new(0, 6)
	rowList.SortOrder = Enum.SortOrder.LayoutOrder
	rowList.Parent = row
	equipRow = row

	StateStore.Changed:Connect(function(sections: { string })
		for _, section in sections do
			if section == "combat" then
				refreshCombat()
			elseif section == "items" or section == "equipped" then
				refreshEquipRow()
			end
		end
	end)

	-- 吹き飛ばされた：サーバーから届いた速度で自分のキャラクターを動かす
	Net.getEvent("Knockback").OnClientEvent:Connect(function(payload: any)
		if type(payload) == "table" and typeof(payload.velocity) == "Vector3" and type(payload.duration) == "number" then
			push(payload.velocity, math.clamp(payload.duration, 0, 0.5))
		end
	end)

	-- クールダウンの残り秒数などを更新する
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= 0.1 then
			accumulated = 0
			refreshCombat()
		end
	end)

	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		local key = input.KeyCode
		if key == Enum.KeyCode.F then
			attack()
		elseif key == Enum.KeyCode.E then
			setGuard(true)
		elseif key == Enum.KeyCode.C then
			dash()
		elseif key == Enum.KeyCode.One then
			toggleAbility(abilityOrder[1])
		elseif key == Enum.KeyCode.Two then
			toggleAbility(abilityOrder[2])
		elseif key == Enum.KeyCode.Three then
			toggleAbility(abilityOrder[3])
		elseif key == Enum.KeyCode.R then
			task.spawn(invoke, "Grant_Release", "all")
		elseif key == Enum.KeyCode.G then
			strip()
		elseif key == Enum.KeyCode.Q then
			castUltimate()
		end
	end)
	-- ガードは離したときに解く（processed に関係なく）
	UserInputService.InputEnded:Connect(function(input)
		if input.KeyCode == Enum.KeyCode.E then
			setGuard(false)
		end
	end)

	refreshCombat()
	refreshEquipRow()
end

return CombatHUD
