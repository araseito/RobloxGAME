--!strict
-- 仮の HUD（Step 1）：画面上部に 3×3 のパズルボックス、左下に持っているカード。
-- 見た目は後でダイスケさんが調整する前提の最小構成。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))

local StateStore = require(script.Parent.StateStore)

local HUD = {}

local COLOR_PLACED = Color3.fromRGB(240, 196, 110)
local COLOR_UNPLACED = Color3.fromRGB(70, 80, 140)
local COLOR_MISSING = Color3.fromRGB(28, 28, 34)
local CELL = 40
local GAP = 4

local cells: { [string]: TextLabel } = {}
local progressLabel: TextLabel? = nil
local itemsLabel: TextLabel? = nil

local function sortedPieces(): { any }
	local list = {}
	for _, def in PieceDefs do
		table.insert(list, def)
	end
	table.sort(list, function(a, b)
		return a.grid < b.grid
	end)
	return list
end

local function sortedItemIds(): { string }
	local ids = {}
	for id in ItemDefs do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

local function refreshPieces()
	local pieces = StateStore.state.pieces
	if pieces == nil then
		return
	end
	local placedCount = 0
	for pieceId, cell in cells do
		local stroke = cell:FindFirstChildOfClass("UIStroke")
		local unplaced = pieces.unplaced[pieceId] or 0
		if pieces.placed[pieceId] then
			placedCount += 1
			cell.BackgroundColor3 = COLOR_PLACED
			cell.TextColor3 = Color3.new(0, 0, 0)
			cell.Text = tostring(PieceDefs[pieceId].grid)
			if stroke then
				stroke.Enabled = false
			end
		elseif unplaced > 0 then
			cell.BackgroundColor3 = COLOR_UNPLACED
			cell.TextColor3 = Color3.new(1, 1, 1)
			cell.Text = if unplaced > 1 then ("×" .. unplaced) else "!"
			if stroke then
				stroke.Enabled = true
			end
		else
			cell.BackgroundColor3 = COLOR_MISSING
			cell.TextColor3 = Color3.fromRGB(90, 90, 100)
			cell.Text = "?"
			if stroke then
				stroke.Enabled = false
			end
		end
	end
	if progressLabel then
		progressLabel.Text = ("%d / 9"):format(placedCount)
	end
end

local function refreshItems()
	local items = StateStore.state.items
	if items == nil or itemsLabel == nil then
		return
	end
	local lines = {}
	for _, id in sortedItemIds() do
		local n = items[id]
		if n and n > 0 then
			table.insert(lines, ("%s ×%d"):format(ItemDefs[id].nameJa, n))
		end
	end
	itemsLabel.Text = if #lines > 0 then table.concat(lines, "\n") else "（カードなし）"
end

function HUD.mount(playerGui: PlayerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling

	-- パズルボックス
	local boxSize = CELL * 3 + GAP * 2
	local box = Instance.new("Frame")
	box.Name = "PuzzleBox"
	box.AnchorPoint = Vector2.new(0.5, 0)
	box.Position = UDim2.new(0.5, 0, 0, 8)
	box.Size = UDim2.fromOffset(boxSize + 12, boxSize + 34)
	box.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	box.BackgroundTransparency = 0.2
	box.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = box

	local grid = Instance.new("Frame")
	grid.Name = "Grid"
	grid.BackgroundTransparency = 1
	grid.Position = UDim2.fromOffset(6, 6)
	grid.Size = UDim2.fromOffset(boxSize, boxSize)
	grid.Parent = box
	local layout = Instance.new("UIGridLayout")
	layout.CellSize = UDim2.fromOffset(CELL, CELL)
	layout.CellPadding = UDim2.fromOffset(GAP, GAP)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = grid

	for _, def in sortedPieces() do
		local cell = Instance.new("TextLabel")
		cell.Name = def.id
		cell.LayoutOrder = def.grid
		cell.BackgroundColor3 = COLOR_MISSING
		cell.Font = Enum.Font.GothamBold
		cell.TextSize = 16
		cell.Text = "?"
		cell.Parent = grid
		local cellCorner = Instance.new("UICorner")
		cellCorner.CornerRadius = UDim.new(0, 4)
		cellCorner.Parent = cell
		local stroke = Instance.new("UIStroke")
		stroke.Color = Color3.fromRGB(150, 200, 255)
		stroke.Thickness = 2
		stroke.Enabled = false
		stroke.Parent = cell
		cells[def.id] = cell
	end

	local progress = Instance.new("TextLabel")
	progress.Name = "Progress"
	progress.BackgroundTransparency = 1
	progress.Position = UDim2.fromOffset(6, boxSize + 8)
	progress.Size = UDim2.fromOffset(boxSize, 22)
	progress.Font = Enum.Font.GothamBold
	progress.TextSize = 16
	progress.TextColor3 = Color3.new(1, 1, 1)
	progress.Text = "0 / 9"
	progress.Parent = box
	progressLabel = progress

	-- カード一覧
	local items = Instance.new("TextLabel")
	items.Name = "Items"
	items.AnchorPoint = Vector2.new(0, 1)
	items.Position = UDim2.new(0, 12, 1, -12)
	items.Size = UDim2.fromOffset(180, 0)
	items.AutomaticSize = Enum.AutomaticSize.Y
	items.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	items.BackgroundTransparency = 0.3
	items.Font = Enum.Font.Gotham
	items.TextSize = 14
	items.TextColor3 = Color3.new(1, 1, 1)
	items.TextXAlignment = Enum.TextXAlignment.Left
	items.TextWrapped = true
	items.Text = "読み込み中…"
	items.Parent = gui
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 6)
	padding.PaddingBottom = UDim.new(0, 6)
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = items
	itemsLabel = items

	gui.Parent = playerGui

	StateStore.Changed:Connect(function(sections: { string })
		for _, section in sections do
			if section == "pieces" then
				refreshPieces()
			elseif section == "items" then
				refreshItems()
			end
		end
	end)
	refreshPieces()
	refreshItems()
end

return HUD
