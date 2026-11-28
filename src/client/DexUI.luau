--!strict
-- 図鑑（PHASE0_PLAN_v2 5.5）：出会った・倒したの記録、棲む場所、落とすもの。戦闘力には関係しない。
-- 出会っていないモンスターは名前を伏せる。表示だけで、記録はサーバーが付ける。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local MonsterDefs = require(Shared:WaitForChild("MonsterDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local AreaDefs = require(Shared:WaitForChild("AreaDefs"))

local StateStore = require(script.Parent.StateStore)

local DexUI = {}

local ORDER = { "moripon", "aohane", "sandhorn", "oonushi" }

local panel: Frame? = nil
local list: Frame? = nil

local function dropText(def: any): string
	local parts = {}
	for _, entry in def.drops or {} do
		local item = ItemDefs[entry.item]
		table.insert(parts, if item then item.nameJa else entry.item)
	end
	if def.pieceDrop and PieceDefs[def.pieceDrop] then
		table.insert(parts, PieceDefs[def.pieceDrop].nameJa .. "（まれに）")
	end
	if def.role == "boss" then
		local pieces = {}
		for _, piece in PieceDefs do
			if piece.route == "boss" and piece.source == def.id then
				table.insert(pieces, piece)
			end
		end
		table.sort(pieces, function(a, b)
			return a.bossKill < b.bossKill
		end)
		for _, piece in pieces do
			table.insert(parts, ("%s（%d 回目の撃破で確定）"):format(piece.nameJa, piece.bossKill))
		end
	end
	return table.concat(parts, "・")
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
	local dex = StateStore.state.dex or {}
	for i, id in ORDER do
		local def = MonsterDefs[id]
		local entry = dex[id] or {}
		local seen = entry.seen == true
		local row = Instance.new("Frame")
		row.Name = id
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, 70)
		row.BackgroundColor3 = if seen then Color3.fromRGB(40, 44, 64) else Color3.fromRGB(28, 28, 34)
		row.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = row

		local title = Instance.new("TextLabel")
		title.BackgroundTransparency = 1
		title.Position = UDim2.fromOffset(10, 4)
		title.Size = UDim2.new(1, -20, 0, 22)
		title.Font = Enum.Font.GothamBold
		title.TextSize = 16
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.TextColor3 = if seen then Color3.new(1, 1, 1) else Color3.fromRGB(130, 130, 140)
		local boss = if def.role == "boss" then "（ボス）" else ""
		title.Text = if seen then ("%s / %s%s　倒した数 %d"):format(def.nameJa, def.nameEn, boss, entry.kills or 0) else "？？？"
		title.Parent = row

		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromOffset(10, 28)
		body.Size = UDim2.new(1, -20, 0, 38)
		body.Font = Enum.Font.Gotham
		body.TextSize = 13
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextWrapped = true
		body.TextColor3 = Color3.fromRGB(215, 215, 225)
		local area = AreaDefs[def.area]
		body.Text = if seen
			then ("%s\n棲む場所：%s　落とすもの：%s"):format(def.descJa, if area then area.nameJa else def.area, dropText(def))
			else ("棲む場所：%s（まだ出会っていない）"):format(if area then area.nameJa else def.area)
		body.Parent = row
	end
end

function DexUI.mount(gui: ScreenGui)
	local open = Instance.new("TextButton")
	open.Name = "DexButton"
	open.Position = UDim2.fromOffset(128, 60)
	open.Size = UDim2.fromOffset(90, 40)
	open.BackgroundColor3 = Color3.fromRGB(110, 90, 50)
	open.Font = Enum.Font.GothamBold
	open.TextSize = 16
	open.TextColor3 = Color3.new(1, 1, 1)
	open.Text = "図鑑"
	open.Parent = gui
	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0, 8)
	openCorner.Parent = open

	local p = Instance.new("Frame")
	p.Name = "DexPanel"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.45)
	p.Size = UDim2.fromOffset(480, 360)
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
	header.Text = "図鑑 / Monster Book"
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
		p.Visible = false
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
		p.Visible = not p.Visible
		if p.Visible then
			refresh()
		end
	end)
	StateStore.Changed:Connect(function(sections: { string })
		if p.Visible and table.find(sections, "dex") then
			refresh()
		end
	end)
end

return DexUI
