--!strict
-- プロフィールの変わったセクションをクライアントへ送る（表示専用）

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProfileSchema = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Logic"):WaitForChild("ProfileSchema"))
local DataService = require(script.Parent.DataService)
local Remotes = require(script.Parent.Remotes)

local StateSync = {}

function StateSync.push(player: Player, ...: string)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local delta = {}
	for _, section in { ... } do
		delta[section] = ProfileSchema.clientSection(profile, section)
	end
	Remotes.fire(player, "State_Delta", delta)
end

function StateSync.snapshot(player: Player): any
	local profile = DataService.getProfile(player)
	if profile == nil then
		return nil
	end
	return ProfileSchema.clientView(profile)
end

return StateSync
