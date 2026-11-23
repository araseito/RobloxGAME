--!strict
-- クライアントの起動。表示と入力だけを担当する。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local StateStore = require(script.Parent.StateStore)
local HUD = require(script.Parent.HUD)
local Toast = require(script.Parent.Toast)
local Messages = require(script.Parent.Messages)
local CombatHUD = require(script.Parent.CombatHUD)
local UltimateFx = require(script.Parent.UltimateFx)
local CombatFx = require(script.Parent.CombatFx)

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
local gui = HUD.mount(playerGui)
Toast.mount(gui)
CombatHUD.mount(gui)
UltimateFx.mount(gui)
CombatFx.mount(playerGui)

-- スナップショットより先に差分の受け口をつなぐ（取りこぼし防止）
Net.getEvent("State_Delta").OnClientEvent:Connect(function(delta: any)
	if type(delta) == "table" then
		StateStore.apply(delta)
	end
end)

Net.getEvent("Toast").OnClientEvent:Connect(function(reason: any)
	Toast.show(Messages.text(reason))
end)

local getSnapshot = Net.getFunction("GetSnapshot")
for attempt = 1, 5 do
	local ok, result = pcall(function()
		return getSnapshot:InvokeServer()
	end)
	if ok and type(result) == "table" and result.ok then
		StateStore.replace(result.state)
		break
	end
	warn(("[Client] 状態の取得に失敗（%d 回目）: %s"):format(attempt, if ok then tostring(result and result.reason) else tostring(result)))
	task.wait(2)
end
