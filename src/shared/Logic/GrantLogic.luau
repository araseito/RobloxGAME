--!strict
-- 付与と解除の計算。require を使わない（定義データは引数で受け取る）。
-- 付与は「自分にだけ」かける（PHASE0_PLAN_v2 5.1）。同じ能力は 1 つまで。
-- 元のテーブルは書き換えず、新しいテーブルを返す。

local GrantLogic = {}

export type Grant = { ability: string, seq: number }

-- 付与上限 = 基本値 + 装備の capacityBonus
function GrantLogic.capacity(base: number, equipped: any, itemDefs: any): number
	local total = base
	if type(equipped) == "table" then
		for _, itemId in equipped do
			local def = itemDefs[itemId]
			if def and type(def.capacityBonus) == "number" then
				total += def.capacityBonus
			end
		end
	end
	return total
end

function GrantLogic.used(grants: { Grant }, abilityDefs: any): number
	local total = 0
	for _, grant in grants do
		local def = abilityDefs[grant.ability]
		if def then
			total += def.cost
		end
	end
	return total
end

function GrantLogic.has(grants: { Grant }, abilityId: string): boolean
	for _, grant in grants do
		if grant.ability == abilityId then
			return true
		end
	end
	return false
end

-- 付与する。成功したら新しい一覧を返す
function GrantLogic.apply(
	grants: { Grant },
	cooldowns: { [string]: number },
	abilityId: any,
	now: number,
	capacity: number,
	abilityDefs: any,
	seq: number
): (boolean, any)
	if type(abilityId) ~= "string" or abilityDefs[abilityId] == nil then
		return false, "unknown_ability"
	end
	if GrantLogic.has(grants, abilityId) then
		return false, "already_active"
	end
	local readyAt = cooldowns[abilityId]
	if readyAt and readyAt > now then
		return false, "cooldown"
	end
	if GrantLogic.used(grants, abilityDefs) + abilityDefs[abilityId].cost > capacity then
		return false, "over_capacity"
	end
	local result = table.clone(grants)
	table.insert(result, { ability = abilityId, seq = seq })
	return true, result
end

-- 自分の意思で解除する。which は能力 ID か "all"。
-- 解除した能力には cooldown 秒の再付与不可を付ける
-- 戻り値：成功, 新しい一覧 or 理由, 新しいクールダウン, 解除した能力の一覧
function GrantLogic.release(
	grants: { Grant },
	cooldowns: { [string]: number },
	which: any,
	now: number,
	cooldown: number
): (boolean, any, { [string]: number }?, { string }?)
	if type(which) ~= "string" then
		return false, "bad_target", nil, nil
	end
	local kept = {}
	local released = {}
	for _, grant in grants do
		if which == "all" or grant.ability == which then
			table.insert(released, grant.ability)
		else
			table.insert(kept, grant)
		end
	end
	if #released == 0 then
		return false, "not_active", nil, nil
	end
	local newCooldowns = table.clone(cooldowns)
	for _, abilityId in released do
		newCooldowns[abilityId] = now + cooldown
	end
	return true, kept, newCooldowns, released
end

-- 1 つ取り除く（剥がされたとき・代価で失うとき）。クールダウンは付けない
function GrantLogic.remove(grants: { Grant }, abilityId: string): (boolean, { Grant })
	local kept = {}
	local found = false
	for _, grant in grants do
		if not found and grant.ability == abilityId then
			found = true
		else
			table.insert(kept, grant)
		end
	end
	return found, kept
end

-- コストの一番低い付与（同じなら古いもの）。剥がしの代価で失うもの
function GrantLogic.pickLowest(grants: { Grant }, abilityDefs: any): string?
	local best: Grant? = nil
	for _, grant in grants do
		local cost = abilityDefs[grant.ability].cost
		if best == nil then
			best = grant
		else
			local bestCost = abilityDefs[best.ability].cost
			if cost < bestCost or (cost == bestCost and grant.seq < best.seq) then
				best = grant
			end
		end
	end
	return if best then best.ability else nil
end

-- コストの一番高い付与（同じなら新しいもの）。必殺技の種類を決める
function GrantLogic.pickHighest(grants: { Grant }, abilityDefs: any): string?
	local best: Grant? = nil
	for _, grant in grants do
		local cost = abilityDefs[grant.ability].cost
		if best == nil then
			best = grant
		else
			local bestCost = abilityDefs[best.ability].cost
			if cost > bestCost or (cost == bestCost and grant.seq > best.seq) then
				best = grant
			end
		end
	end
	return if best then best.ability else nil
end

-- 付与と装備から倍率を求める（足し算で重ねる）
function GrantLogic.multipliers(
	grants: { Grant },
	abilityDefs: any,
	equipped: any,
	itemDefs: any,
	minDamageTaken: number
): { moveSpeed: number, attack: number, damageTaken: number }
	local bonus = { moveSpeed = 0, attack = 0, damageTaken = 0 }
	for _, grant in grants do
		local def = abilityDefs[grant.ability]
		if def and bonus[def.stat] ~= nil then
			bonus[def.stat] += def.amount
		end
	end
	if type(equipped) == "table" then
		for _, itemId in equipped do
			local def = itemDefs[itemId]
			if def and def.stat and bonus[def.stat] ~= nil then
				bonus[def.stat] += def.amount
			end
		end
	end
	return {
		moveSpeed = math.max(0, 1 + bonus.moveSpeed),
		attack = math.max(0, 1 + bonus.attack),
		damageTaken = math.max(minDamageTaken, 1 + bonus.damageTaken),
	}
end

return GrantLogic
