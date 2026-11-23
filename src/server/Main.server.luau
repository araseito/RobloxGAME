--!strict
-- サーバーの起動順だけを書く

local Server = script.Parent

local Remotes = require(Server.Remotes)
Remotes.init() -- Net フォルダを最初に作る（クライアントが待っている）

local DataService = require(Server.DataService)
local StateSync = require(Server.StateSync)
local Metrics = require(Server.Metrics)
local DevTools = require(Server.DevTools)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

DataService.Loaded:Connect(function(player: Player)
	Metrics.onboarding(player, DataService.getProfile(player), 1)
end)

Remotes.onInvoke("GetSnapshot", function(player: Player)
	local profile = DataService.waitForProfile(player, Config.Data.ProfileWaitTimeout)
	if profile == nil then
		return { ok = false, reason = "not_loaded" }
	end
	return { ok = true, state = StateSync.snapshot(player) }
end)

DataService.init()
DevTools.init()

print("[Server] Phase 0 起動完了")
