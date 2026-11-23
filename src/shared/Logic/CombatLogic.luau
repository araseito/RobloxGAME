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

-- 4 段コンボの次の段。前の段から resetSeconds 以上あいた・最後の段まで行った・初回なら 1 段目
function CombatLogic.nextComboStep(prevStep: number?, lastAt: number?, now: number, resetSeconds: number, hits: number): number
	if prevStep == nil or lastAt == nil or now - lastAt > resetSeconds or prevStep >= hits then
		return 1
	end
	return prevStep + 1
end

export type HitInput = {
	finisher: boolean, -- 締めの一撃か（4 段目・敵の大振り・単体の必殺技）
	guarding: boolean, -- 受ける側がガード中か
	front: boolean, -- 攻撃が受ける側の正面から来たか
	guardBreak: boolean, -- 攻める側が剛力付与（ガードを割れる）を持っているか
	noKnockback: boolean, -- 受ける側が鉄壁付与（吹き飛ばない）を持っているか
}

export type HitResult = {
	damageMultiplier: number,
	guardBroken: boolean, -- ガードを割った（受ける側は長く動けなくなる）
	knockback: boolean, -- 吹き飛ばす（受ける側は短く動けなくなる）
}

-- 1 回の攻撃が当たったときの結果を決める
--   正面からのガード：ダメージ減。ただし剛力の締めならガードを割る
--   締め：吹き飛ばす。ただし鉄壁なら吹き飛ばない
function CombatLogic.resolveHit(input: HitInput, guardMultiplier: number): HitResult
	if input.guarding and input.front then
		if input.finisher and input.guardBreak then
			return { damageMultiplier = 1, guardBroken = true, knockback = false }
		end
		return { damageMultiplier = guardMultiplier, guardBroken = false, knockback = false }
	end
	if input.finisher and not input.noKnockback then
		return { damageMultiplier = 1, guardBroken = false, knockback = true }
	end
	return { damageMultiplier = 1, guardBroken = false, knockback = false }
end

-- 攻撃が正面から来たか。look は受ける側の向き、toAttacker は受ける側から攻める側への向き（どちらも水平の x, z）
function CombatLogic.isFront(lookX: number, lookZ: number, toAttackerX: number, toAttackerZ: number): boolean
	return lookX * toAttackerX + lookZ * toAttackerZ > 0
end

function CombatLogic.dashCooldown(base: number, hasDashPerk: boolean, perkMultiplier: number): number
	return if hasDashPerk then base * perkMultiplier else base
end

return CombatLogic
