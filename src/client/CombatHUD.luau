--!strict
-- 戦闘の操作ボタンと表示（仮の見た目。手触りは後でダイスケさんが調整する）
-- ・右側：攻撃 / 疾風 / 剛力 / 鉄壁 / 全解除 / 剥がす / 必殺技 のボタン
-- ・下中央：付与の使用量（例 7/10）、必殺技ゲージ、戦闘中の表示、装備ボタン
-- キーボード：F 攻撃、1/2/3 付与の付け外し、R 全解除、G 剥がす、Q 必殺技
-- ボタンは「やりたいこと」をサーバーに頼むだけ。可否はすべてサーバーが決める

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
local grantLabel: TextLabel? = nil
local gaugeFill: Frame? = nil
local combatLabel: TextLabel? = nil
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

-- 一番近い攻撃対象：射程内の敵 → いなければ射程内の他のプレイヤー
-- （他のプレイヤーへの攻撃はサーバーで無効になる。それを確かめるためにも送る）
local function findAttackTarget(): Model?
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
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

local function toggleAbility(abilityId: string)
	if grantActive(abilityId) then
		invoke("Grant_Release", abilityId)
	else
		invoke("Grant_Apply", abilityId)
	end
end

-- 剥がす：相手（今戦っている敵）の付与のうち、一番コストの高いものを選ぶ
local function strip()
	-- 相手の付与は敵の属性 "Grants" に出ている。剥がす相手（今戦っている敵）はサーバーが決めるので、
	-- ここでは近くの敵の付与から 1 つ選んで頼む。サーバー側の相手と違えば not_active で返る
	local candidates: { string } = {}
	local character = player.Character
	local root = character and character:FindFirstChild("HumanoidRootPart")
	if root and root:IsA("BasePart") then
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
	invoke("Grant_Strip", candidates[1])
end

local function castUltimate()
	invoke("Ultimate_Cast")
end

-- 見た目 --------------------------------------------------------------------

local function makeButton(parent: Instance, name: string, text: string, order: number, onClick: () -> ()): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.LayoutOrder = order
	button.Size = UDim2.fromOffset(96, 40)
	button.BackgroundColor3 = COLOR_BUTTON
	button.AutoButtonColor = true
	button.Font = Enum.Font.GothamBold
	button.TextSize = 14
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = text
	button.Parent = parent
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 6)
	corner.Parent = button
	button.Activated:Connect(onClick)
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
						invoke("Action", "unequip", slot)
					else
						invoke("Action", "equip", itemId)
					end
				end)
				button.Size = UDim2.fromOffset(130, 30)
				button.TextSize = 13
				button.BackgroundColor3 = if isOn then COLOR_ACTIVE else COLOR_BUTTON
			end
		end
	end
end

-- 先頭の 2 文字（「疾風付与」→「疾風」）。日本語は 1 文字が複数バイトなので utf8 で数える
local function shortName(name: string): string
	local cut = utf8.offset(name, 3)
	return if cut then string.sub(name, 1, cut - 1) else name
end

local function refreshCombat()
	local combat = combatState()
	if not combat then
		return
	end
	local now = workspace:GetServerTimeNow()

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
			button.Text = ("%s (%d)"):format(name, def.cost)
		end
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
	if combatLabel then
		combatLabel.Text = if combat.casting then "詠唱中…" elseif combat.inCombat then "戦闘中" else "通常"
		combatLabel.TextColor3 = if combat.inCombat then Color3.fromRGB(255, 120, 100) else Color3.fromRGB(180, 180, 190)
	end
	if ultimateButton then
		local ready = combat.inCombat and combat.gauge >= combat.gaugeMax and not combat.casting
		ultimateButton.BackgroundColor3 = if ready then COLOR_READY else COLOR_COOLDOWN
	end
end

function CombatHUD.mount(gui: ScreenGui)
	-- 右側のボタン列
	local column = Instance.new("Frame")
	column.Name = "CombatButtons"
	-- 右上のパズルボックス（高さ約 166px）の下から並べる。縦中央に置くとボックスと重なった（Step 2 のテストで判明）
	column.AnchorPoint = Vector2.new(1, 0)
	column.Position = UDim2.new(1, -12, 0, 184)
	column.Size = UDim2.fromOffset(96, 0)
	column.AutomaticSize = Enum.AutomaticSize.Y
	column.BackgroundTransparency = 1
	column.Parent = gui
	local list = Instance.new("UIListLayout")
	list.Padding = UDim.new(0, 6)
	list.SortOrder = Enum.SortOrder.LayoutOrder
	list.Parent = column

	makeButton(column, "Attack", "攻撃 [F]", 1, attack)
	for i, abilityId in abilityOrder do
		abilityButtons[abilityId] = makeButton(column, abilityId, AbilityDefs[abilityId].nameJa, 1 + i, function()
			toggleAbility(abilityId)
		end)
	end
	makeButton(column, "ReleaseAll", "全解除 [R]", 10, function()
		invoke("Grant_Release", "all")
	end)
	makeButton(column, "Strip", "剥がす [G]", 11, strip)
	ultimateButton = makeButton(column, "Ultimate", "必殺技 [Q]", 12, castUltimate)

	-- 下中央の表示
	local panel = Instance.new("Frame")
	panel.Name = "CombatPanel"
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -12)
	panel.Size = UDim2.fromOffset(300, 0)
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

	local status = Instance.new("TextLabel")
	status.Name = "Status"
	status.LayoutOrder = 1
	status.Size = UDim2.new(1, 0, 0, 18)
	status.BackgroundTransparency = 1
	status.Font = Enum.Font.GothamBold
	status.TextSize = 14
	status.Text = "通常"
	status.Parent = panel
	combatLabel = status

	local grantText = Instance.new("TextLabel")
	grantText.Name = "Grants"
	grantText.LayoutOrder = 2
	grantText.Size = UDim2.new(1, 0, 0, 18)
	grantText.BackgroundTransparency = 1
	grantText.Font = Enum.Font.Gotham
	grantText.TextSize = 14
	grantText.TextColor3 = Color3.new(1, 1, 1)
	grantText.Text = "付与 0 / 10"
	grantText.Parent = panel
	grantLabel = grantText

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

	local row = Instance.new("Frame")
	row.Name = "Equip"
	row.LayoutOrder = 4
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

	-- クールダウンの残り秒数を更新する
	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= 0.25 then
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
		elseif key == Enum.KeyCode.One then
			toggleAbility(abilityOrder[1])
		elseif key == Enum.KeyCode.Two then
			toggleAbility(abilityOrder[2])
		elseif key == Enum.KeyCode.Three then
			toggleAbility(abilityOrder[3])
		elseif key == Enum.KeyCode.R then
			invoke("Grant_Release", "all")
		elseif key == Enum.KeyCode.G then
			strip()
		elseif key == Enum.KeyCode.Q then
			castUltimate()
		end
	end)

	refreshCombat()
	refreshEquipRow()
end

return CombatHUD
