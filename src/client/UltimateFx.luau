--!strict
-- 必殺技の演出（土台）：技名の大きな表示と、短いカットインの帯。
-- 同じサーバーにいる全員に見える（自分以外の発動も表示する）。
-- 見た目・効果音は後でダイスケさんが調整する前提の最小構成。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local UltimateDefs = require(Shared:WaitForChild("UltimateDefs"))
local Net = require(Shared:WaitForChild("Net"))

local UltimateFx = {}

local COLORS: { [string]: Color3 } = {
	dash = Color3.fromRGB(60, 140, 255),
	single = Color3.fromRGB(230, 90, 60),
	shield = Color3.fromRGB(240, 200, 80),
}

local banner: Frame? = nil
local nameLabel: TextLabel? = nil
local subLabel: TextLabel? = nil
local token = 0

local function casterName(userId: number): string
	local caster = Players:GetPlayerByUserId(userId)
	return if caster then caster.DisplayName else "?"
end

local function showStart(payload: any)
	local def = UltimateDefs[payload.ultimate]
	local frame, title, sub = banner, nameLabel, subLabel
	if not def or not frame or not title or not sub then
		return
	end
	token += 1
	local myToken = token

	frame.BackgroundColor3 = COLORS[def.kind] or Color3.new(1, 1, 1)
	title.Text = def.nameJa .. "！"
	sub.Text = ("%s / %s"):format(casterName(payload.userId), def.nameEn)
	frame.Position = UDim2.new(-1, 0, 0.35, 0)
	frame.Visible = true
	-- 左から滑り込むカットイン（短く保つ）
	TweenService:Create(frame, TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		Position = UDim2.new(0, 0, 0.35, 0),
	}):Play()

	local duration = if type(payload.castTime) == "number" then payload.castTime else 1.2
	task.delay(duration + 0.3, function()
		if token == myToken then
			frame.Visible = false
		end
	end)
end

local function showResolve(payload: any)
	local def = UltimateDefs[payload.ultimate]
	local sub = subLabel
	if not def or not sub then
		return
	end
	sub.Text = ("%s / 威力 %d（消費コスト %d）"):format(casterName(payload.userId), payload.power or 0, payload.consumedCost or 0)
end

function UltimateFx.mount(gui: ScreenGui)
	local frame = Instance.new("Frame")
	frame.Name = "UltimateBanner"
	frame.Size = UDim2.new(1, 0, 0, 90)
	frame.BackgroundTransparency = 0.15
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.ZIndex = 30
	frame.Parent = gui

	local title = Instance.new("TextLabel")
	title.Name = "Title"
	title.Size = UDim2.new(1, 0, 0, 56)
	title.BackgroundTransparency = 1
	title.Font = Enum.Font.GothamBlack
	title.TextSize = 44
	title.TextColor3 = Color3.new(1, 1, 1)
	title.TextStrokeTransparency = 0.2
	title.ZIndex = 31
	title.Parent = frame

	local sub = Instance.new("TextLabel")
	sub.Name = "Sub"
	sub.Position = UDim2.fromOffset(0, 58)
	sub.Size = UDim2.new(1, 0, 0, 24)
	sub.BackgroundTransparency = 1
	sub.Font = Enum.Font.GothamBold
	sub.TextSize = 16
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.ZIndex = 31
	sub.Parent = frame

	banner = frame
	nameLabel = title
	subLabel = sub

	Net.getEvent("Ultimate_Broadcast").OnClientEvent:Connect(function(payload: any)
		if type(payload) ~= "table" then
			return
		end
		if payload.phase == "start" then
			showStart(payload)
		elseif payload.phase == "resolve" then
			showResolve(payload)
		end
	end)
end

return UltimateFx
