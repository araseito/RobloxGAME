--!strict
-- Studio 専用の開発コマンド。本番サーバーでは何も作らない。
-- 使い方（Studio のプレイテスト中、サーバー側のコマンドバーで）：
--   game.ServerStorage.DevTools:Invoke("give", "Player1", "leaf", 3)
--   game.ServerStorage.DevTools:Invoke("take", "Player1", "leaf", 1)
--   game.ServerStorage.DevTools:Invoke("piece", "Player1", "p01")
--   game.ServerStorage.DevTools:Invoke("show", "Player1")
--   game.ServerStorage.DevTools:Invoke("save", "Player1")
-- ※ コマンドバーから require するとモジュールが別の実体になることがあるため、BindableFunction 経由にしている

local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ServerStorage = game:GetService("ServerStorage")

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)

local DevTools = {}

local function findPlayer(name: any): Player?
	local found = Players:FindFirstChild(tostring(name))
	if found and found:IsA("Player") then
		return found
	end
	return nil
end

local commands: { [string]: (...any) -> any } = {
	give = function(name, itemId, amount)
		local player = findPlayer(name)
		if not player then
			return "player_not_found"
		end
		return InventoryService.applyItems(player, { grant = { [tostring(itemId)] = tonumber(amount) or 1 } })
	end,
	take = function(name, itemId, amount)
		local player = findPlayer(name)
		if not player then
			return "player_not_found"
		end
		return InventoryService.applyItems(player, { consume = { [tostring(itemId)] = tonumber(amount) or 1 } })
	end,
	piece = function(name, pieceId)
		local player = findPlayer(name)
		if not player then
			return "player_not_found"
		end
		return InventoryService.addUnplacedPiece(player, tostring(pieceId))
	end,
	show = function(name)
		local player = findPlayer(name)
		if not player then
			return "player_not_found"
		end
		local profile = DataService.getProfile(player)
		return if profile then HttpService:JSONEncode(profile) else "not_loaded"
	end,
	save = function(name)
		local player = findPlayer(name)
		if not player then
			return "player_not_found"
		end
		return DataService.saveNow(player)
	end,
}

function DevTools.init()
	if not RunService:IsStudio() then
		return
	end
	local bindable = Instance.new("BindableFunction")
	bindable.Name = "DevTools"
	bindable.OnInvoke = function(command: any, ...: any): any
		local fn = commands[tostring(command)]
		if not fn then
			return "unknown_command"
		end
		return fn(...)
	end
	bindable.Parent = ServerStorage
	print("[DevTools] Studio 用の開発コマンドを ServerStorage.DevTools に用意しました")
end

return DevTools
