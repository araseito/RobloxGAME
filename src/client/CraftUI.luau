--!strict
-- クラフトの画面（PHASE0_PLAN_v2 5.6）：レシピ・持っている数・足りない素材の入手先・合成ボタンを 1 画面に。
-- 足りなければボタンは押せない。合成できるかの最終判断はサーバー。
-- あわせて、回復薬を使うボタン（H キー）を左下に出す。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local RecipeDefs = require(Shared:WaitForChild("RecipeDefs"))
local MonsterDefs = require(Shared:WaitForChild("MonsterDefs"))
local AreaDefs = require(Shared:WaitForChild("AreaDefs"))
local CraftLogic = require(Shared:WaitForChild("Logic"):WaitForChild("CraftLogic"))

local StateStore = require(script.Parent.StateStore)
local Toast = require(script.Parent.Toast)
local Messages = require(script.Parent.Messages)

local CraftUI = {}

local panel: Frame? = nil
local list: Frame? = nil
local potionButton: TextButton? = nil
local busy = false

local function action(kind: string, id: any, onOk: (() -> ())?)
	task.spawn(function()
		local ok, response = pcall(function()
			return Net.getFunction("Action"):InvokeServer(kind, id)
		end)
		if not ok then
			Toast.show(Messages.text("server_error"))
		elseif type(response) == "table" and response.ok then
			if onOk then
				onOk()
			end
		else
			Toast.show(Messages.text(if type(response) == "table" then response.reason else nil))
		end
	end)
end

local function itemName(id: string): string
	local def = ItemDefs[id]
	return if def then def.nameJa else id
end

local function effectText(def: any): string
	if def.category == "weapon" then
		return ("攻撃 +%d%%・付与上限 +%d"):format(math.round(def.amount * 100), def.capacityBonus)
	elseif def.category == "armor" then
		return ("被ダメージ %d%%・付与上限 +%d"):format(math.round(def.amount * 100), def.capacityBonus)
	elseif def.category == "consumable" then
		return ("使うと HP %d%% 回復（戦闘中のみ・リングでは使えない）"):format(math.round(def.healRatio * 100))
	end
	return ""
end

local function sourceText(itemId: string): string
	local names = {}
	for _, monsterId in CraftLogic.sources(itemId, MonsterDefs) do
		local m = MonsterDefs[monsterId]
		local area = AreaDefs[m.area]
		table.insert(names, ("%s（%s）"):format(m.nameJa, if area then area.nameJa else m.area))
	end
	return table.concat(names, "・")
end

local function sortedRecipes(): { any }
	local out = {}
	for _, recipe in RecipeDefs do
		table.insert(out, recipe)
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

local function sortedInputs(recipe: any): { string }
	local ids = {}
	for id in recipe.inputs do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function refresh()
	local frame = list
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local items = StateStore.state.items or {}
	for _, recipe in sortedRecipes() do
		local output = ItemDefs[recipe.output]
		local missing = CraftLogic.missing(items, recipe)
		local can = next(missing) == nil

		local row = Instance.new("Frame")
		row.Name = recipe.id
		row.LayoutOrder = recipe.order
		row.Size = UDim2.new(1, 0, 0, 84)
		row.BackgroundColor3 = Color3.fromRGB(40, 44, 64)
		row.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(10, 4)
		title.Size = UDim2.new(1, -120, 0, 22)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = Color3.new(1, 1, 1)
		title.Text = ("%s（持っている数 %d）"):format(output.nameJa, items[recipe.output] or 0)
		title.Parent = row

		local lines = { effectText(output) }
		local needs = {}
		for _, id in sortedInputs(recipe) do
			table.insert(needs, ("%s %d / %d"):format(itemName(id), items[id] or 0, recipe.inputs[id]))
		end
		table.insert(lines, "必要：" .. table.concat(needs, "　"))
		for _, id in sortedInputs(recipe) do
			if missing[id] then
				table.insert(lines, ("%sはあと %d：%s が落とす"):format(itemName(id), missing[id], sourceText(id)))
			end
		end
		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromOffset(10, 26)
		body.Size = UDim2.new(1, -120, 0, 56)
		body.Font = Enum.Font.Gotham
		body.TextSize = 13
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextWrapped = true
		body.TextColor3 = Color3.fromRGB(215, 215, 225)
		body.Text = table.concat(lines, "\n")
		body.Parent = row

		local button = Instance.new("TextButton")
		button.Name = "Craft"
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, -10, 0.5, 0)
		button.Size = UDim2.fromOffset(96, 40)
		button.AutoButtonColor = can
		button.Active = can
		button.BackgroundColor3 = if can then Color3.fromRGB(70, 150, 90) else Color3.fromRGB(60, 60, 66)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 16
		button.TextColor3 = if can then Color3.new(1, 1, 1) else Color3.fromRGB(140, 140, 150)
		button.Text = "合成"
		button.Parent = row
		local buttonCorner = Instance.new("UICorner")
		buttonCorner.CornerRadius = UDim.new(0, 6)
		buttonCorner.Parent = button
		if can then
			button.Activated:Connect(function()
				if busy then
					return
				end
				busy = true
				action("craft", recipe.id, function()
					Toast.show(output.nameJa .. "を作った！")
				end)
				task.delay(0.3, function()
					busy = false
				end)
			end)
		end
	end
end

local function setOpen(open: boolean)
	local p = panel
	if p == nil or p.Visible == open then
		return
	end
	p.Visible = open
	if open then
		refresh()
	end
	-- 開いた・閉じたを計測用に知らせる（開いたが合成しなかった、を数える）
	action(if open then "craft_open" else "craft_close", nil, nil)
end

local function usePotion()
	action("use_item", "potion", function()
		Toast.show("回復薬を使った")
	end)
end

local function refreshPotion()
	local button = potionButton
	if button == nil then
		return
	end
	local n = (StateStore.state.items or {}).potion or 0
	button.Visible = n > 0
	button.Text = ("回復薬 ×%d [H]"):format(n)
end

function CraftUI.mount(gui: ScreenGui)
	local open = Instance.new("TextButton")
	open.Name = "CraftButton"
	open.Position = UDim2.fromOffset(224, 60)
	open.Size = UDim2.fromOffset(90, 40)
	open.BackgroundColor3 = Color3.fromRGB(70, 90, 140)
	open.Font = Enum.Font.GothamBold
	open.TextSize = 16
	open.TextColor3 = Color3.new(1, 1, 1)
	open.Text = "合成"
	open.Parent = gui
	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0, 8)
	openCorner.Parent = open

	local p = Instance.new("Frame")
	p.Name = "CraftPanel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.45)
	p.Size = UDim2.fromOffset(500, 344)
	p.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	p.BackgroundTransparency = 0.05
	p.Visible = false
	p.ZIndex = 30
	p.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = p

	local header = Instance.new("TextLabel")
	header.BackgroundTransparency = 1
	header.Position = UDim2.fromOffset(14, 8)
	header.Size = UDim2.new(1, -60, 0, 30)
	header.Font = Enum.Font.GothamBold
	header.TextSize = 20
	header.TextXAlignment = Enum.TextXAlignment.Left
	header.TextColor3 = Color3.new(1, 1, 1)
	header.Text = "合成 / Craft"
	header.Parent = p

	local close = Instance.new("TextButton")
	close.AnchorPoint = Vector2.new(1, 0)
	close.Position = UDim2.new(1, -8, 0, 8)
	close.Size = UDim2.fromOffset(32, 32)
	close.BackgroundColor3 = Color3.fromRGB(60, 60, 80)
	close.Font = Enum.Font.GothamBold
	close.TextSize = 18
	close.TextColor3 = Color3.new(1, 1, 1)
	close.Text = "×"
	close.Parent = p
	close.Activated:Connect(function()
		setOpen(false)
	end)

	local l = Instance.new("Frame")
	l.Name = "List"
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(14, 46)
	l.Size = UDim2.new(1, -28, 1, -56)
	l.Parent = p
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = l
	panel = p
	list = l

	open.Activated:Connect(function()
		setOpen(not p.Visible)
	end)

	-- 回復薬（持っているときだけ出る）。左下のカード一覧の上
	local potion = Instance.new("TextButton")
	potion.Name = "PotionButton"
	potion.AnchorPoint = Vector2.new(0, 1)
	potion.Position = UDim2.new(0, 12, 1, -64)
	potion.Size = UDim2.fromOffset(150, 36)
	potion.BackgroundColor3 = Color3.fromRGB(170, 70, 90)
	potion.Font = Enum.Font.GothamBold
	potion.TextSize = 15
	potion.TextColor3 = Color3.new(1, 1, 1)
	potion.Visible = false
	potion.Parent = gui
	local potionCorner = Instance.new("UICorner")
	potionCorner.CornerRadius = UDim.new(0, 8)
	potionCorner.Parent = potion
	potion.Activated:Connect(usePotion)
	potionButton = potion

	UserInputService.InputBegan:Connect(function(input, processed)
		if not processed and input.KeyCode == Enum.KeyCode.H then
			usePotion()
		end
	end)

	StateStore.Changed:Connect(function(sections: { string })
		if table.find(sections, "items") then
			refreshPotion()
			if p.Visible then
				refresh()
			end
		end
	end)
	refreshPotion()
end

return CraftUI
