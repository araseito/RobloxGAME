--!strict
-- 決闘リングの計算（賭けピースの選択・時間切れの判定・リングの内外）。require を使わない。

local DuelLogic = {}

-- 賭けるピースを 1 つ選ぶ（PHASE0_PLAN_v2 5.4：重複しているピースを優先）。
-- 優先の順：
--   1. もうはまっているピースの未装着の写し（はめられないので、持っていても使い道は賭けだけ）
--   2. 未装着で 2 枚以上あるピース
--   3. それ以外の未装着のピース
-- 同じ順位の中では grid の大きいものを選ぶ（毎回同じ結果になるようにするため。順番は仮置き）
function DuelLogic.pickBet(pieces: any, pieceDefs: any): string?
	local best: string? = nil
	local bestRank = math.huge
	local bestGrid = -math.huge
	for id, n in pieces.unplaced do
		local def = pieceDefs[id]
		if def and n > 0 then
			local rank = if pieces.placed[id] then 1 elseif n >= 2 then 2 else 3
			if rank < bestRank or (rank == bestRank and def.grid > bestGrid) then
				best = id
				bestRank = rank
				bestGrid = def.grid
			end
		end
	end
	return best
end

-- 時間切れの判定：HP の割合が少ない方が負け。同じなら引き分け（"draw"）
function DuelLogic.judgeTimeout(ratioA: number, ratioB: number): string
	if ratioA < ratioB then
		return "b"
	elseif ratioB < ratioA then
		return "a"
	end
	return "draw"
end

-- リングの中にいるか。dx, dz は中心からの水平のずれ、dy は床面からの高さ
function DuelLogic.isInside(dx: number, dz: number, dy: number, radius: number, fallDepth: number): boolean
	return dx * dx + dz * dz <= radius * radius and dy >= -fallDepth
end

-- 台の上に立っているか
function DuelLogic.isOnPad(dx: number, dz: number, dy: number, padRadius: number, maxHeight: number): boolean
	return dx * dx + dz * dz <= padRadius * padRadius and dy >= -1 and dy <= maxHeight
end

-- 負けてから window 秒以内にもう一度乗ったら「再戦」
function DuelLogic.isRematch(lostAt: number?, now: number, window: number): boolean
	return lostAt ~= nil and now - lostAt <= window
end

return DuelLogic
