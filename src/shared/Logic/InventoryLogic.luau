--!strict
-- カードとピースの増減の計算。require を使わない（定義データは引数で受け取る）。
-- 元のテーブルは書き換えず、成功したときだけ新しいテーブルを返す。
-- サーバーは戻り値を yield なしで profile に代入するので、増減は途中で割り込まれない。

local InventoryLogic = {}

export type Change = {
	consume: { [string]: number }?,
	grant: { [string]: number }?,
}

local function isValidAmount(n: any, maxAmount: number): boolean
	-- NaN と無限大は n % 1 ~= 0 で弾かれる
	return type(n) == "number" and n > 0 and n % 1 == 0 and n <= maxAmount
end

local function validateMap(map: any, defs: any, maxAmount: number): (boolean, string?)
	if map == nil then
		return true, nil
	end
	if type(map) ~= "table" then
		return false, "bad_change"
	end
	for id, n in map do
		if type(id) ~= "string" or defs[id] == nil then
			return false, "unknown_id"
		end
		if not isValidAmount(n, maxAmount) then
			return false, "bad_amount"
		end
	end
	return true, nil
end

local function categoryTotals(items: { [string]: number }, itemDefs: any): { [string]: number }
	local totals = {}
	for id, n in items do
		local def = itemDefs[id]
		if def then
			totals[def.category] = (totals[def.category] or 0) + n
		end
	end
	return totals
end

-- 素材・装備・アイテムの増減。consume を先に引いてから grant を足す。
function InventoryLogic.applyItems(
	items: { [string]: number },
	change: Change,
	itemDefs: any,
	categoryLimit: { [string]: number },
	maxAmount: number
): (boolean, any)
	if type(change) ~= "table" then
		return false, "bad_change"
	end
	local ok, reason = validateMap(change.consume, itemDefs, maxAmount)
	if not ok then
		return false, reason
	end
	ok, reason = validateMap(change.grant, itemDefs, maxAmount)
	if not ok then
		return false, reason
	end

	local before = categoryTotals(items, itemDefs)
	local result = table.clone(items)

	if change.consume then
		for id, n in change.consume do
			local have = result[id] or 0
			if have < n then
				return false, "insufficient"
			end
			local left = have - n
			result[id] = if left > 0 then left else nil
		end
	end

	if change.grant then
		for id, n in change.grant do
			result[id] = (result[id] or 0) + n
		end
	end

	-- 上限を超えて「増えた」種別だけを拒否する（上限を下げた後でも消費はできるように）
	local after = categoryTotals(result, itemDefs)
	for category, total in after do
		local limit = categoryLimit[category]
		if limit and total > limit and total > (before[category] or 0) then
			return false, "category_full"
		end
	end

	return true, result
end

local function unplacedTotal(unplaced: { [string]: number }): number
	local total = 0
	for _, n in unplaced do
		total += n
	end
	return total
end

-- 未装着ピースを 1 枚足す
function InventoryLogic.addUnplacedPiece(pieces: any, pieceId: string, pieceDefs: any, limit: number): (boolean, any)
	if type(pieceId) ~= "string" or pieceDefs[pieceId] == nil then
		return false, "unknown_id"
	end
	if unplacedTotal(pieces.unplaced) >= limit then
		return false, "pieces_full"
	end
	local result = {
		placed = table.clone(pieces.placed),
		unplaced = table.clone(pieces.unplaced),
	}
	result.unplaced[pieceId] = (result.unplaced[pieceId] or 0) + 1
	return true, result
end

-- 未装着ピースを 1 枚減らす（はめる・賭けで失う）
function InventoryLogic.removeUnplacedPiece(pieces: any, pieceId: string): (boolean, any)
	local have = if type(pieceId) == "string" then pieces.unplaced[pieceId] or 0 else 0
	if have < 1 then
		return false, "insufficient"
	end
	local result = {
		placed = table.clone(pieces.placed),
		unplaced = table.clone(pieces.unplaced),
	}
	result.unplaced[pieceId] = if have > 1 then have - 1 else nil
	return true, result
end

return InventoryLogic
