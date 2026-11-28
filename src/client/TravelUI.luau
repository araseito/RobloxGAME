--!strict
-- 画面の「行き先」ボタン → エリアの一覧 → 選ぶと入口へ移動（PHASE0_PLAN_v2 5.7）。
-- 行けるかどうか・どこへ移すかはサーバーが決める。ここは表示と依頼だけ。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Net = require(Shared:WaitForChild("Net"))
local AreaDefs = require(Shared:WaitForChild("AreaDefs"))
local QuestDefs = require(Shared:WaitForChild("QuestDefs"))

local StateStore = require(script.Parent.StateStore)
local Toast = require(script.Parent.Toast)
local Messages = require(script.Parent.Messages)

local TravelUI = {}

local player = Players.LocalPlayer
local panel: Frame? = nil
local list: Frame? = nil
local busy = false

local function sortedAreas(): { any }
	local out = {}
	for _, def in AreaDefs do
		table.insert(out, def)
	end
	table.sort(out, function(a, b)
		return a.order < b.order
	end)
	return out
end

local function unlockText(def: any): string
	if def.unlock and def.unlock.quest and QuestDefs[def.unlock.quest] then
		return ("クエスト「%s」で行けるようになる"):format(QuestDefs[def.unlock.quest].nameJa)
	end
	return "まだ行けない"
end

local function go(areaId: string)
	if busy then
		return
	end
	busy = true
	task.spawn(function()
		local ok, response = pcall(function()
			return Net.getFunction("Action"):InvokeServer("travel", areaId)
		end)
		busy = false
		if not ok then
			Toast.show(Messages.text("server_error"))
		elseif type(response) == "table" and response.ok then
			if panel then
				panel.Visible = false
			end
		else
			Toast.show(Messages.text(if type(response) == "table" then response.reason else nil))
		end
	end)
end

local function refresh()
	local frame = list
	if frame == nil then
		return
	end
	for _, child in frame:GetChildren() do
		if child:IsA("TextButton") then
			child:Destroy()
		end
	end
	local unlocked = StateStore.state.areas or {}
	local here = player:GetAttribute("Area")
	for _, def in sortedAreas() do
		local open = unlocked[def.id] == true
		local button = Instance.new("TextButton")
		button.Name = def.id
		button.LayoutOrder = def.order
		button.Size = UDim2.new(1, 0, 0, 52)
		button.AutoButtonColor = open
		button.BackgroundColor3 = if def.id == here
			then Color3.fromRGB(70, 110, 170)
			elseif open then Color3.fromRGB(40, 44, 64)
			else Color3.fromRGB(30, 30, 36)
		button.Font = Enum.Font.GothamBold
		button.TextSize = 15
		button.TextColor3 = if open then Color3.new(1, 1, 1) else Color3.fromRGB(130, 130, 140)
		local suffix = if def.id == here then "（今いる場所）" elseif open then "" else ("\n" .. unlockText(def))
		button.Text = ("%s / %s%s"):format(def.nameJa, def.nameEn, suffix)
		button.Parent = frame
		local corner = Instance.new("UICorner")
		corner.CornerRadius = UDim.new(0, 6)
		corner.Parent = button
		if open and def.id ~= here then
			button.Activated:Connect(function()
				go(def.id)
			end)
		end
	end
end

function TravelUI.mount(gui: ScreenGui)
	local open = Instance.new("TextButton")
	open.Name = "TravelButton"
	open.Position = UDim2.fromOffset(12, 60)
	open.Size = UDim2.fromOffset(110, 40)
	open.BackgroundColor3 = Color3.fromRGB(60, 120, 90)
	open.Font = Enum.Font.GothamBold
	open.TextSize = 16
	open.TextColor3 = Color3.new(1, 1, 1)
	open.Text = "行き先"
	open.Parent = gui
	local openCorner = Instance.new("UICorner")
	openCorner.CornerRadius = UDim.new(0, 8)
	openCorner.Parent = open

	local p = Instance.new("Frame")
	p.Name = "TravelPanel"
	p.Position = UDim2.fromOffset(12, 106)
	p.Size = UDim2.fromOffset(300, 0)
	p.AutomaticSize = Enum.AutomaticSize.Y
	p.BackgroundColor3 = Color3.fromRGB(16, 20, 36)
	p.BackgroundTransparency = 0.05
	p.Visible = false
	p.ZIndex = 30
	p.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = p
	local padding = Instance.new("UIPadding")
	padding.PaddingTop = UDim.new(0, 10)
	padding.PaddingBottom = UDim.new(0, 10)
	padding.PaddingLeft = UDim.new(0, 10)
	padding.PaddingRight = UDim.new(0, 10)
	padding.Parent = p
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = p
	panel = p
	list = p

	open.Activated:Connect(function()
		p.Visible = not p.Visible
		if p.Visible then
			refresh()
		end
	end)
	StateStore.Changed:Connect(function(sections: { string })
		if p.Visible and table.find(sections, "areas") then
			refresh()
		end
	end)
	player:GetAttributeChangedSignal("Area"):Connect(function()
		if p.Visible then
			refresh()
		end
	end)
end

return TravelUI
