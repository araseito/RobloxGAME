--!strict
-- モンスターを倒したときのドロップの抽選。require を使わない（定義データと乱数は引数で受け取る）。
-- rng は 0 以上 1 未満を返す関数（サーバーでは Random.new():NextNumber、テストでは決まった列や大量の試行）

local DropLogic = {}

export type Drop = { items: { [string]: number }, piece: string? }

-- 通常モンスター：素材を drops どおりに、ピースを pieceChance で 1 つ
-- ボス：素材に加えて、その人の撃破回数（bossKillsBefore + 1 回目）に対応するピースを確定で
function DropLogic.roll(monsterDef: any, pieceDefs: any, pieceChance: number, bossKillsBefore: number, rng: () -> number): Drop
	local items: { [string]: number } = {}
	for _, entry in monsterDef.drops or {} do
		if rng() < entry.chance then
			local span = entry.max - entry.min + 1
			local amount = entry.min + math.min(span - 1, math.floor(rng() * span))
			if amount > 0 then
				items[entry.item] = (items[entry.item] or 0) + amount
			end
		end
	end

	local piece: string? = nil
	if monsterDef.role == "boss" then
		local nth = bossKillsBefore + 1
		for id, def in pieceDefs do
			if def.route == "boss" and def.source == monsterDef.id and def.bossKill == nth then
				piece = id
			end
		end
	elseif monsterDef.pieceDrop and rng() < pieceChance then
		piece = monsterDef.pieceDrop
	end
	return { items = items, piece = piece }
end

-- ボスのドロップをもらえるか：最大 HP に対して ratio 以上のダメージを与えた人
function DropLogic.qualifies(dealt: number, maxHealth: number, ratio: number): boolean
	return dealt >= maxHealth * ratio
end

return DropLogic
