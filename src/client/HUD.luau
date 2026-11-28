--!strict
-- HUD：画面右上に 3×3 のパズルボックス、その左に「ボックスにはめる」ボタン、左下に持っているカード。
-- 見た目は後でダイスケさんが調整する前提の最小構成（絵はまだないので、はめたマスは色と番号で示す）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local PuzzleLogic = require(Shared:WaitForChild("Logic"):WaitForChild("PuzzleLogic"))

local StateStore = require(script.Parent.StateStore)
local Toast = require(script.Parent.Toast)
local Messages = require(script.Parent.Messages)

local HUD = {}

local COLOR_PLACED = Color3.fromRGB(240, 196, 110)
local COLOR_UNPLACED = Color3.fromRGB(70, 80, 140)
local COLOR_MISSING = Color3.fromRGB(28, 28, 34)
local CELL = 40
local GAP = 4

local cells: { [string]: TextLabel } = {}
local progressLabel: TextLabel? = nil
local itemsLabel: TextLabel? = nil
local placeButton: TextButton? = nil
local rootGui: ScreenGui? = nil

-- 前回の状態（増えた・はまった・完成した瞬間だけ演出するため。最初の表示では演出しない）
local knownPlaced: { [string]: boolean }? = nil
local knownUnplacedTotal = 0
local knownTitles: { [string]: boolean }? = nil
local knownItems: { [string]: number }? = nil
local placing = false

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

-- はまったマスが大きく光ってから落ち着く
local function popCell(cell: TextLabel)
	local flash = Instance.new("Frame")
	flash.Size = UDim2.fromScale(1, 1)
	flash.BackgroundColor3 = Color3.new(1, 1, 1)
	flash.BackgroundTransparency = 0
	flash.ZIndex = cell.ZIndex + 1
	flash.Parent = cell
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = flash
	TweenService:Create(flash, TweenInfo.new(0.6, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		BackgroundTransparency = 1,
	}):Play()
	task.delay(0.7, flash.Destroy, flash)

	local scale = Instance.new("UIScale")
	scale.Scale = 1.6
	scale.Parent = cell
	local tween = TweenService:Create(scale, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
		Scale = 1,
	})
	tween:Play()
	tween.Completed:Connect(function()
		scale:Destroy()
	end)
end

local function showBanner(title: string, subtitle: string)
	local gui = rootGui
	if gui == nil then
		return
	end
	local banner = Instance.new("Frame")
	banner.Name = "CompletionBanner"
	banner.AnchorPoint = Vector2.new(0.5, 0.5)
	banner.Position = UDim2.fromScale(0.5, 0.4)
	banner.Size = UDim2.new(1, 0, 0, 120)
	banner.BackgroundColor3 = Color3.fromRGB(240, 196, 110)
	banner.BackgroundTransparency = 0.1
	banner.ZIndex = 50
	banner.Parent = gui
	local big = Instance.new("TextLabel")
	big.BackgroundTransparency = 1
	big.Size = UDim2.new(1, 0, 0, 70)
	big.Font = Enum.Font.GothamBlack
	big.TextSize = 44
	big.TextColor3 = Color3.fromRGB(40, 24, 8)
	big.Text = title
	big.ZIndex = 51
	big.Parent = banner
	local small = Instance.new("TextLabel")
	small.BackgroundTransparency = 1
	small.Position = UDim2.fromOffset(0, 70)
	small.Size = UDim2.new(1, 0, 0, 36)
	small.Font = Enum.Font.GothamBold
	small.TextSize = 22
	small.TextColor3 = Color3.fromRGB(40, 24, 8)
	small.Text = subtitle
	small.ZIndex = 51
	small.Parent = banner
	task.delay(4, function()
		TweenService:Create(banner, TweenInfo.new(0.5), { BackgroundTransparency = 1 }):Play()
		TweenService:Create(big, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		TweenService:Create(small, TweenInfo.new(0.5), { TextTransparency = 1 }):Play()
		task.delay(0.6, banner.Destroy, banner)
	end)
end

local function refreshPieces()
	local pieces = StateStore.state.pieces
	if pieces == nil then
		return
	end
	local placedCount = 0
	local unplacedTotal = 0
	for pieceId, cell in cells do
		local stroke = cell:FindFirstChildOfClass("UIStroke")
		local unplaced = pieces.unplaced[pieceId] or 0
		unplacedTotal += unplaced
		if pieces.placed[pieceId] then
			placedCount += 1
			cell.BackgroundColor3 = COLOR_PLACED
			cell.TextColor3 = Color3.new(0, 0, 0)
			-- 重複して持っている分（賭けに使える）は「+n」で示す
			cell.Text = tostring(PieceDefs[pieceId].grid) .. (if unplaced > 0 then (" +" .. unplaced) else "")
			if stroke then
				stroke.Enabled = false
			end
			if knownPlaced and not knownPlaced[pieceId] then
				popCell(cell)
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
	if placeButton then
		-- はめられるのは町だけなので、町にいるときだけ出す（判定はサーバーでもしている）
		local inTown = (Players.LocalPlayer:GetAttribute("Area") or "town") == "town"
		placeButton.Visible = inTown and PuzzleLogic.nextPlaceable(pieces, PieceDefs) ~= nil
	end
	if knownPlaced and unplacedTotal > knownUnplacedTotal then
		Toast.show("ピースを手に入れた！")
	end

	knownPlaced = table.clone(pieces.placed)
	knownUnplacedTotal = unplacedTotal
end

local function refreshTitles()
	local titles = StateStore.state.titles
	if titles == nil then
		return
	end
	if knownTitles then
		for titleId in titles do
			if not knownTitles[titleId] then
				local def = Config.Titles[titleId]
				showBanner("パズルボックス完成！", "称号「" .. (if def then def.nameJa else titleId) .. "」を手に入れた")
			end
		end
	end
	knownTitles = table.clone(titles)
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

	-- 増えたカードを知らせる（最初の表示では知らせない）
	if knownItems then
		local gained = {}
		for _, id in sortedItemIds() do
			local diff = (items[id] or 0) - (knownItems[id] or 0)
			if diff > 0 then
				table.insert(gained, ("%s ×%d"):format(ItemDefs[id].nameJa, diff))
			end
		end
		if #gained > 0 then
			Toast.show(table.concat(gained, "・") .. " を手に入れた")
		end
	end
	knownItems = table.clone(items)
end

-- 次にはめられるピースを 1 つはめる（どのピースかはサーバーが確かめる）
local function placeNext()
	local pieces = StateStore.state.pieces
	if placing or pieces == nil then
		return
	end
	local pieceId = PuzzleLogic.nextPlaceable(pieces, PieceDefs)
	if pieceId == nil then
		return
	end
	placing = true
	task.spawn(function()
		local ok, response = pcall(function()
			return Net.getFunction("Piece_Place"):InvokeServer(pieceId)
		end)
		placing = false
		if not ok then
			Toast.show(Messages.text("server_error"))
		elseif not (type(response) == "table" and response.ok) then
			Toast.show(Messages.text(if type(response) == "table" then response.reason else nil))
		end
	end)
end

function HUD.mount(playerGui: PlayerGui): ScreenGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "HUD"
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	rootGui = gui

	-- パズルボックス
	local boxSize = CELL * 3 + GAP * 2
	local box = Instance.new("Frame")
	box.Name = "PuzzleBox"
	-- 画面中央だとキャラクターの頭と重なるので右上に置く（Step 1 のテストで気づいた点）
	box.AnchorPoint = Vector2.new(1, 0)
	box.Position = UDim2.new(1, -12, 0, 8)
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

	-- 「ボックスにはめる」ボタン（未装着のピースがあるときだけ出る）。ボックスの下には戦闘ボタンがあるので左隣に置く
	local button = Instance.new("TextButton")
	button.Name = "PlaceButton"
	button.AnchorPoint = Vector2.new(1, 1)
	button.Position = UDim2.new(1, -(12 + boxSize + 12 + 8), 0, 8 + boxSize + 34)
	button.Size = UDim2.fromOffset(150, 44)
	button.BackgroundColor3 = Color3.fromRGB(90, 150, 255)
	button.Font = Enum.Font.GothamBold
	button.TextSize = 16
	button.TextColor3 = Color3.new(1, 1, 1)
	button.Text = "ボックスにはめる"
	button.Visible = false
	button.Parent = gui
	local buttonCorner = Instance.new("UICorner")
	buttonCorner.CornerRadius = UDim.new(0, 8)
	buttonCorner.Parent = button
	local buttonStroke = Instance.new("UIStroke")
	buttonStroke.Color = Color3.new(1, 1, 1)
	buttonStroke.Thickness = 2
	buttonStroke.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	buttonStroke.Parent = button
	-- 目に入るように縁取りを点滅させる
	TweenService:Create(buttonStroke, TweenInfo.new(0.6, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true), {
		Transparency = 0.8,
	}):Play()
	button.Activated:Connect(placeNext)
	placeButton = button

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
			elseif section == "titles" then
				refreshTitles()
			end
		end
	end)
	Players.LocalPlayer:GetAttributeChangedSignal("Area"):Connect(refreshPieces)
	refreshPieces()
	refreshItems()
	refreshTitles()
	return gui
end

return HUD
