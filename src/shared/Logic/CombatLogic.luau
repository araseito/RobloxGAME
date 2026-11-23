--!strict
-- ダメージ・必殺技ゲージ・必殺技の威力と範囲の計算。require を使わない。

local CombatLogic = {}

local function isFiniteNumber(n: any): boolean
	return type(n) == "number" and n == n and n ~= math.huge and n ~= -math.huge
end

-- 最終ダメージ = 基礎 × 攻撃倍率 × 被ダメージ倍率。対人なら最大 HP 比の上限をかける
function CombatLogic.damage(
	base: number,
	attackMultiplier: number,
	damageTakenMultiplier: number,
	pvpCap: number?
): number
	if not isFiniteNumber(base) or base <= 0 then
		return 0
	end
	local amount = base * attackMultiplier * damageTakenMultiplier
	if pvpCap then
		amount = math.min(amount, pvpCap)
	end
	-- 小数点以下 1 桁にそろえる
	return math.max(0, math.floor(amount * 10 + 0.5) / 10)
end

-- シールドで吸収する。戻り値：残りのシールド, 通るダメージ
function CombatLogic.absorb(shield: number, amount: number): (number, number)
	if shield <= 0 then
		return 0, amount
	end
	if shield >= amount then
		return shield - amount, 0
	end
	return 0, amount - shield
end

-- ゲージを足す（0〜max に収める。不正な値は無視）
function CombatLogic.addGauge(gauge: number, amount: any, max: number): number
	if not isFiniteNumber(amount) or amount <= 0 then
		return gauge
	end
	return math.min(max, gauge + amount)
end

-- 必殺技の威力 = 基礎 + 消費した付与コストの合計 × 倍率
function CombatLogic.ultimatePower(consumedCost: number, base: number, perCost: number): number
	return base + math.max(0, consumedCost) * perCost
end

-- 突進の範囲に入るか。forward は前方向の距離、lateral は横方向のずれ（どちらも stud）
function CombatLogic.inDashArea(forward: number, lateral: number, range: number, width: number): boolean
	return forward >= 0 and forward <= range and math.abs(lateral) <= width / 2
end

return CombatLogic
