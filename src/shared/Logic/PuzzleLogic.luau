--!strict
-- パズルボックスの計算（はめる・完成判定）。require を使わない（定義データは引数で受け取る）。
-- 元のテーブルは書き換えず、成功したときだけ新しいテーブルを返す。

local PuzzleLogic = {}

-- 未装着のピースを 1 枚はめる。同じピースがすでにはまっていれば、重複なのではめられない
function PuzzleLogic.place(pieces: any, pieceId: any, pieceDefs: any): (boolean, any)
	if type(pieceId) ~= "string" or pieceDefs[pieceId] == nil then
		return false, "unknown_id"
	end
	if pieces.placed[pieceId] then
		return false, "already_placed"
	end
	local have = pieces.unplaced[pieceId] or 0
	if have < 1 then
		return false, "piece_not_owned"
	end
	local result = {
		placed = table.clone(pieces.placed),
		unplaced = table.clone(pieces.unplaced),
	}
	result.placed[pieceId] = true
	result.unplaced[pieceId] = if have > 1 then have - 1 else nil
	return true, result
end

function PuzzleLogic.placedCount(placed: { [string]: any }, pieceDefs: any): number
	local n = 0
	for id in pieceDefs do
		if placed[id] then
			n += 1
		end
	end
	return n
end

function PuzzleLogic.isComplete(placed: { [string]: any }, pieceDefs: any): boolean
	for id in pieceDefs do
		if not placed[id] then
			return false
		end
	end
	return true
end

-- 次にはめられるピース（grid の小さい順）。なければ nil
function PuzzleLogic.nextPlaceable(pieces: any, pieceDefs: any): string?
	local best: string? = nil
	local bestGrid = math.huge
	for id, def in pieceDefs do
		if not pieces.placed[id] and (pieces.unplaced[id] or 0) > 0 and def.grid < bestGrid then
			best = id
			bestGrid = def.grid
		end
	end
	return best
end

return PuzzleLogic
