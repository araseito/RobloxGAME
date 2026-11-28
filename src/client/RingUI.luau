--!strict
-- 決闘リングの表示（自分が対戦するときだけ、画面の上に大きく出す）。
-- 見物している人には、サーバーがリングの上に出す看板で状態を見せる。
-- 表示だけで、決着や賭けはサーバーが決める。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local Net = require(Shared:WaitForChild("Net"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))

local RingUI = {}

local player = Players.LocalPlayer

local banner: TextLabel? = nil
local current: { [string]: any }? = nil
local resultUntil = 0

local function pieceName(pieceId: any): string
	local def = if type(pieceId) == "string" then PieceDefs[pieceId] else nil
	return if def then def.nameJa else "?"
end

-- 自分は a と b のどちらか（どちらでもなければ nil）
local function mySide(update: { [string]: any }): string?
	if update.a == player.UserId then
		return "a"
	elseif update.b == player.UserId then
		return "b"
	end
	return nil
end

local function show(text: string, color: Color3)
	local label = banner
	if label then
		label.Text = text
		label.BackgroundColor3 = color
		label.Visible = true
	end
end

local function hide()
	if banner then
		banner.Visible = false
	end
end

local function showResult(result: { [string]: any })
	local text: string
	local color: Color3
	if result.draw then
		text = "引き分け（賭けはそのまま）"
		color = Color3.fromRGB(90, 90, 110)
	elseif result.winner == player.UserId then
		text = if result.moved
			then ("勝ち！ %sをもらった"):format(pieceName(result.piece))
			else "勝ち！（ピースが持ちきれず、相手に残りました）"
		color = Color3.fromRGB(70, 150, 80)
	elseif result.loser == player.UserId then
		text = if result.moved
			then ("負け… %sを取られた（%d 秒後にまた乗れます）"):format(pieceName(result.piece), Config.Ring.LoserCooldown)
			else "負け…"
		color = Color3.fromRGB(170, 60, 60)
	else
		return
	end
	show(text, color)
	resultUntil = os.clock() + 4
end

local function refresh()
	if os.clock() < resultUntil then
		return
	end
	local update = current
	local side = if update then mySide(update) else nil
	if update == nil or side == nil or update.phase == "idle" then
		hide()
		return
	end
	local left = math.max(0, math.ceil((update.endsAt or 0) - workspace:GetServerTimeNow()))
	local myBet = if side == "a" then update.betA else update.betB
	local theirBet = if side == "a" then update.betB else update.betA
	if update.phase == "countdown" then
		-- 「(」で始まる行を作らないよう、文字列はいったん変数に入れる（ERROR_LOG #1）
		local text = string.format("決闘まで %d\n賭け：自分 %s ／ 相手 %s（台を降りれば取りやめ）", left, pieceName(myBet), pieceName(theirBet))
		show(text, Color3.fromRGB(180, 120, 40))
	elseif update.phase == "fight" then
		show(("決闘中  残り %d 秒\nリングから出ると負け"):format(left), Color3.fromRGB(150, 50, 50))
	end
end

function RingUI.mount(gui: ScreenGui)
	local label = Instance.new("TextLabel")
	label.Name = "RingBanner"
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 104)
	label.Size = UDim2.fromOffset(460, 64)
	label.BackgroundTransparency = 0.1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 18
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextWrapped = true
	label.Visible = false
	label.ZIndex = 25
	label.Parent = gui
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 8)
	corner.Parent = label
	banner = label

	Net.getEvent("Ring_Update").OnClientEvent:Connect(function(update: any)
		if type(update) ~= "table" then
			return
		end
		if type(update.result) == "table" then
			showResult(update.result)
		end
		current = update
		refresh()
	end)

	local accumulated = 0
	RunService.Heartbeat:Connect(function(dt)
		accumulated += dt
		if accumulated >= 0.2 then
			accumulated = 0
			refresh()
		end
	end)
end

return RingUI
