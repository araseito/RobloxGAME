--!strict
-- Remote の受け口をまとめる。すべての受信にレート制限と pcall をかける。
-- 中身のない RemoteFunction には not_implemented を返す（クライアントが固まらないように）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Net = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Net"))
local RateLimiter = require(script.Parent.RateLimiter)

export type Result = { ok: boolean, reason: string?, [string]: any }
type InvokeHandler = (Player, ...any) -> Result
type EventHandler = (Player, ...any) -> ()

local Remotes = {}

local folder: Folder? = nil
local invokeHandlers: { [string]: InvokeHandler } = {}
local eventHandlers: { [string]: EventHandler } = {}

local function getRemote(name: string): Instance
	assert(folder, "Remotes.init() を先に呼ぶ")
	local remote = folder:FindFirstChild(name)
	assert(remote, "Remote がない: " .. name)
	return remote
end

function Remotes.init()
	assert(folder == nil, "Remotes.init() は 1 回だけ")
	folder = Net.createServerFolder()

	for _, name in Net.Functions do
		local remote = getRemote(name) :: RemoteFunction
		remote.OnServerInvoke = function(player: Player, ...: any): Result
			if not RateLimiter.allow(player, name) then
				return { ok = false, reason = "rate_limited" }
			end
			local handler = invokeHandlers[name]
			if not handler then
				return { ok = false, reason = "not_implemented" }
			end
			local ok, result = pcall(handler, player, ...)
			if not ok then
				warn(("[Remotes] %s でエラー: %s"):format(name, tostring(result)))
				return { ok = false, reason = "server_error" }
			end
			return result
		end
	end

	for _, name in Net.ClientEvents do
		local remote = getRemote(name) :: RemoteEvent
		remote.OnServerEvent:Connect(function(player: Player, ...: any)
			if not RateLimiter.allow(player, name) then
				return
			end
			local handler = eventHandlers[name]
			if not handler then
				return
			end
			local ok, err = pcall(handler, player, ...)
			if not ok then
				warn(("[Remotes] %s でエラー: %s"):format(name, tostring(err)))
			end
		end)
	end
end

function Remotes.onInvoke(name: string, handler: InvokeHandler)
	assert(Net.isFunction(name), "未定義の RemoteFunction: " .. name)
	assert(invokeHandlers[name] == nil, "二重登録: " .. name)
	invokeHandlers[name] = handler
end

function Remotes.onEvent(name: string, handler: EventHandler)
	assert(Net.isClientEvent(name), "未定義のクライアントイベント: " .. name)
	assert(eventHandlers[name] == nil, "二重登録: " .. name)
	eventHandlers[name] = handler
end

function Remotes.fire(player: Player, name: string, payload: any)
	assert(Net.isServerEvent(name), "未定義のサーバーイベント: " .. name)
	if player.Parent == nil then
		return
	end
	-- 「(」で始まる行は前の行の続きと区別できず構文エラーになるので、いったん変数に入れる（ERROR_LOG #1）
	local remote = getRemote(name) :: RemoteEvent
	remote:FireClient(player, payload)
end

function Remotes.fireAll(name: string, payload: any)
	assert(Net.isServerEvent(name), "未定義のサーバーイベント: " .. name)
	local remote = getRemote(name) :: RemoteEvent
	remote:FireAllClients(payload)
end

return Remotes
