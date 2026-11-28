--!strict
-- カードとピースの増減を受け持つ唯一の窓口。
-- InventoryLogic で新しいテーブルを計算し、成功したときだけ yield なしで差し替える。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local InventoryLogic = require(Shared:WaitForChild("Logic"):WaitForChild("InventoryLogic"))
local PuzzleLogic = require(Shared:WaitForChild("Logic"):WaitForChild("PuzzleLogic"))

local DataService = require(script.Parent.DataService)
local StateSync = require(script.Parent.StateSync)

local InventoryService = {}

-- change = { consume = { id = n }, grant = { id = n } }
function InventoryService.applyItems(player: Player, change: InventoryLogic.Change): (boolean, string?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	local ok, result = InventoryLogic.applyItems(
		profile.items,
		change,
		ItemDefs,
		Config.Inventory.CategoryLimit,
		Config.Inventory.MaxAmountPerChange
	)
	if not ok then
		return false, result
	end
	profile.items = result
	StateSync.push(player, "items")
	return true, nil
end

function InventoryService.count(player: Player, itemId: string): number
	local profile = DataService.getProfile(player)
	if profile == nil then
		return 0
	end
	return profile.items[itemId] or 0
end

function InventoryService.addUnplacedPiece(player: Player, pieceId: string): (boolean, string?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	local ok, result = InventoryLogic.addUnplacedPiece(
		profile.pieces,
		pieceId,
		PieceDefs,
		Config.Inventory.UnplacedPieceLimit
	)
	if not ok then
		return false, result
	end
	profile.pieces = result
	StateSync.push(player, "pieces")
	return true, nil
end

function InventoryService.removeUnplacedPiece(player: Player, pieceId: string): (boolean, string?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	local ok, result = InventoryLogic.removeUnplacedPiece(profile.pieces, pieceId)
	if not ok then
		return false, result
	end
	profile.pieces = result
	StateSync.push(player, "pieces")
	return true, nil
end

-- 未装着のピースを 1 枚ボックスにはめる（はめたピースは二度と失わない）
function InventoryService.placePiece(player: Player, pieceId: any): (boolean, string?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	local ok, result = PuzzleLogic.place(profile.pieces, pieceId, PieceDefs)
	if not ok then
		return false, result
	end
	profile.pieces = result
	StateSync.push(player, "pieces")
	return true, nil
end

return InventoryService
