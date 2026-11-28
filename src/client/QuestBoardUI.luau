--!strict
-- 町の掲示板：近くで「見る」を押すとクエストの一覧を開く。
-- 1 ピース目をはめたあと、クエスト 1 が終わるまで掲示板を光らせて案内する（最初の 60 秒の 4 段目）。
-- 表示だけで、進み具合はサーバーから届いた状態をそのまま見せる。

local CollectionService = game:GetService("CollectionService")
local ProximityPromptService = game:GetService("ProximityPromptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local QuestDefs = require(Shared:WaitForChild("QuestDefs"))
local MonsterDefs = require(Shared:WaitForChild("MonsterDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local AreaDefs = require(Shared:WaitForChild("AreaDefs"))
local PuzzleLogic = require(Shared:WaitForChild("Logic"):WaitForChild("PuzzleLogic"))

local StateStore = require(script.Parent.StateStore)
local Toast = require(script.Parent.Toast)

local QuestBoardUI = {}

local BOARD_TAG = "QuestBoard" -- サーバーの QuestService.BOARD_TAG と同じ
local GUIDE_QUEST = "q01"

local panel: Frame? = nil
local list: Frame? = nil
local knownDone: { [string]: boolean }? = nil
local knownGuiding: boolean? = nil

local function sortedQuests(): { any }
	local out = {}
	for _, def in QuestDefs do
		table.insert(out, def)
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

local function goalText(goal: any): string
	if goal.kind == "kill" then
		local m = MonsterDefs[goal.monster]
		return ("%sを %d 体倒す"):format(if m then m.nameJa else goal.monster, goal.count)
	elseif goal.kind == "craft" then
		local item = ItemDefs[goal.item]
		return ("%sを %d 個作る"):format(if item then item.nameJa else goal.item, goal.count)
	end
	return ""
end

local function rewardText(reward: any): string
	local parts = {}
	if reward.piece and PieceDefs[reward.piece] then
		table.insert(parts, PieceDefs[reward.piece].nameJa)
	end
	if reward.unlockArea and AreaDefs[reward.unlockArea] then
		table.insert(parts, AreaDefs[reward.unlockArea].nameJa .. "へ行けるようになる")
	end
	return table.concat(parts, "・")
end

local function refreshList()
	local frame = list
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	local quests = StateStore.state.quests or {}
	for _, def in sortedQuests() do
		local entry = quests[def.id] or { progress = 0 }
		local row = Instance.new("Frame")
		row.Name = def.id
		row.LayoutOrder = def.order
		row.Size = UDim2.new(1, 0, 0, 64)
		row.BackgroundColor3 = if entry.done then Color3.fromRGB(60, 90, 60) else Color3.fromRGB(40, 44, 64)
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
		title.TextColor3 = Color3.new(1, 1, 1)
		local status = if entry.done then "達成" else ("%d / %d"):format(entry.progress, def.goal.count)
		title.Text = ("%s  %s"):format(def.nameJa, status)
		title.Parent = row

		local body = Instance.new("TextLabel")
		body.BackgroundTransparency = 1
		body.Position = UDim2.fromOffset(10, 28)
		body.Size = UDim2.new(1, -20, 0, 32)
		body.Font = Enum.Font.Gotham
		body.TextSize = 14
		body.TextXAlignment = Enum.TextXAlignment.Left
		body.TextYAlignment = Enum.TextYAlignment.Top
		body.TextWrapped = true
		body.TextColor3 = Color3.fromRGB(220, 220, 230)
		body.Text = ("%s\n報酬：%s"):format(goalText(def.goal), rewardText(def.reward))
		body.Parent = row
	end
end

-- 1 ピース目をはめていて、クエスト 1 がまだなら掲示板を光らせる
local function shouldGuide(): boolean
	local pieces = StateStore.state.pieces
	local quests = StateStore.state.quests or {}
	if pieces == nil then
		return false
	end
	local guideDone = quests[GUIDE_QUEST] and quests[GUIDE_QUEST].done
	return PuzzleLogic.placedCount(pieces.placed, PieceDefs) >= 1 and not guideDone
end

local function refreshGuide()
	local guiding = shouldGuide()
	for _, board in CollectionService:GetTagged(BOARD_TAG) do
		local highlight = board:FindFirstChild("GuideHighlight")
		if guiding and highlight == nil then
			local h = Instance.new("Highlight")
			h.Name = "GuideHighlight"
			h.FillColor = Color3.fromRGB(255, 220, 120)
			h.FillTransparency = 0.5
			h.OutlineColor = Color3.fromRGB(255, 240, 180)
			h.Parent = board
		elseif not guiding and highlight then
			highlight:Destroy()
		end
	end
	if knownGuiding == false and guiding then
		Toast.show("掲示板が光っています。近くで「見る」を押そう", 4)
	end
	if StateStore.state.pieces ~= nil then
		knownGuiding = guiding
	end
end

local function refreshDone()
	local quests = StateStore.state.quests
	if quests == nil then
		return
	end
	if knownDone then
		for id, entry in quests do
			if entry.done and not knownDone[id] and QuestDefs[id] then
				Toast.show(("クエスト「%s」達成！"):format(QuestDefs[id].nameJa), 4)
			end
		end
	end
	local done = {}
	for id, entry in quests do
		done[id] = entry.done == true
	end
	knownDone = done
end

local function setOpen(open: boolean)
	if panel then
		panel.Visible = open
		if open then
			refreshList()
		end
	end
end

function QuestBoardUI.mount(gui: ScreenGui)
	local p = Instance.new("Frame")
	p.Name = "QuestBoard"
	p.AnchorPoint = Vector2.new(0.5, 0.5)
	p.Position = UDim2.fromScale(0.5, 0.45)
	p.Size = UDim2.fromOffset(420, 300)
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
	header.Text = "掲示板 / Quest Board"
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

	local note = Instance.new("TextLabel")
	note.BackgroundTransparency = 1
	note.Position = UDim2.fromOffset(14, 40)
	note.Size = UDim2.new(1, -28, 0, 18)
	note.Font = Enum.Font.Gotham
	note.TextSize = 13
	note.TextXAlignment = Enum.TextXAlignment.Left
	note.TextColor3 = Color3.fromRGB(190, 190, 205)
	note.Text = "受ける手続きはいりません。達成すると報酬が自動で届きます"
	note.Parent = p

	local l = Instance.new("Frame")
	l.Name = "List"
	l.BackgroundTransparency = 1
	l.Position = UDim2.fromOffset(14, 64)
	l.Size = UDim2.new(1, -28, 1, -76)
	l.Parent = p
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = l

	panel = p
	list = l

	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt)
		local parent = prompt.Parent
		if parent and CollectionService:HasTag(parent, BOARD_TAG) then
			setOpen(not p.Visible)
		end
	end)
	-- 掲示板はサーバーが作るので、後から届いたときにも光らせる
	CollectionService:GetInstanceAddedSignal(BOARD_TAG):Connect(refreshGuide)

	StateStore.Changed:Connect(function(sections: { string })
		for _, section in sections do
			if section == "quests" then
				refreshDone()
				if p.Visible then
					refreshList()
				end
			end
			if section == "quests" or section == "pieces" then
				refreshGuide()
			end
		end
	end)
	refreshDone()
	refreshGuide()
end

return QuestBoardUI
