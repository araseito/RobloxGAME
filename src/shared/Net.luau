--!strict
-- Remote の名前はここ以外に書かない。
-- クライアントからは ID だけを送る。数値（ダメージ・コスト・枚数）は受け取らない。

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Net = {}

Net.FOLDER = "Net"

-- クライアント → サーバー（結果を返す）
Net.Functions = table.freeze({
	"GetSnapshot",
	"Grant_Apply",
	"Grant_Release",
	"Grant_Strip",
	"Ultimate_Cast",
	"Piece_Place",
	"Action",
})

-- クライアント → サーバー（返事なし。連打されるもの）
Net.ClientEvents = table.freeze({
	"Attack",
})

-- サーバー → クライアント
Net.ServerEvents = table.freeze({
	"State_Delta",
	"Ultimate_Broadcast",
	"Ring_Update",
	"Toast",
	"Knockback", -- 吹き飛ばし（プレイヤーのキャラクターは本人の端末が動かしているので、本人に飛ばしてもらう）
	"Combat_Fx", -- 攻撃の演出（腕の振り・当たったときの光と数字）を全員に知らせる。見た目だけで、結果には関係しない
})

function Net.isFunction(name: string): boolean
	return table.find(Net.Functions, name) ~= nil
end

function Net.isClientEvent(name: string): boolean
	return table.find(Net.ClientEvents, name) ~= nil
end

function Net.isServerEvent(name: string): boolean
	return table.find(Net.ServerEvents, name) ~= nil
end

-- サーバー専用：Remote をまとめて作る
function Net.createServerFolder(): Folder
	assert(RunService:IsServer(), "Net.createServerFolder はサーバー専用")
	assert(ReplicatedStorage:FindFirstChild(Net.FOLDER) == nil, "Net フォルダがすでにある")

	local folder = Instance.new("Folder")
	folder.Name = Net.FOLDER
	for _, name in Net.Functions do
		local remote = Instance.new("RemoteFunction")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in Net.ClientEvents do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	for _, name in Net.ServerEvents do
		local remote = Instance.new("RemoteEvent")
		remote.Name = name
		remote.Parent = folder
	end
	folder.Parent = ReplicatedStorage
	return folder
end

local function getFolder(): Instance
	return ReplicatedStorage:WaitForChild(Net.FOLDER)
end

function Net.getFunction(name: string): RemoteFunction
	assert(Net.isFunction(name), "未定義の RemoteFunction: " .. name)
	return getFolder():WaitForChild(name) :: RemoteFunction
end

function Net.getEvent(name: string): RemoteEvent
	assert(Net.isClientEvent(name) or Net.isServerEvent(name), "未定義の RemoteEvent: " .. name)
	return getFolder():WaitForChild(name) :: RemoteEvent
end

return Net
