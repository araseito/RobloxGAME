--!strict
-- 付与と解除（サーバー権威）。
-- 付与を持てるのはプレイヤーと敵（木人・モンスター）。状態はメモリだけに置き、保存しない。
-- 付与上限は装備で増える（プレイヤーのみ）。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local GrantLogic = require(Shared:WaitForChild("Logic"):WaitForChild("GrantLogic"))

local DataService = require(script.Parent.DataService)
local BattleStateService = require(script.Parent.BattleStateService)

type Entry = {
	grants: { GrantLogic.Grant },
	cooldowns: { [string]: number },
	seq: number,
}

-- 付与を持つもの：Player か、敵の Model
type Entity = Instance

local GrantService = {}

local entries: { [Entity]: Entry } = {}

local hooks = {
	onApply = nil :: ((Entity, string) -> ())?,
	onRelease = nil :: ((Entity, { string }) -> ())?,
	onStrip = nil :: ((Player, Entity, string) -> ())?,
	onChanged = nil :: ((Entity) -> ())?,
}

function GrantService.setHooks(newHooks: any)
	hooks.onApply = newHooks.onApply
	hooks.onRelease = newHooks.onRelease
	hooks.onStrip = newHooks.onStrip
	hooks.onChanged = newHooks.onChanged
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function entryOf(entity: Entity): Entry
	local entry = entries[entity]
	if not entry then
		entry = { grants = {}, cooldowns = {}, seq = 0 }
		entries[entity] = entry
	end
	return entry
end

local function equippedOf(entity: Entity): any
	if entity:IsA("Player") then
		local profile = DataService.getProfile(entity)
		return if profile then profile.equipped else {}
	end
	return {}
end

function GrantService.capacityOf(entity: Entity): number
	return GrantLogic.capacity(Config.Grant.BaseCapacity, equippedOf(entity), ItemDefs)
end

function GrantService.list(entity: Entity): { GrantLogic.Grant }
	return table.clone(entryOf(entity).grants)
end

function GrantService.has(entity: Entity, abilityId: string): boolean
	return GrantLogic.has(entryOf(entity).grants, abilityId)
end

function GrantService.multipliers(entity: Entity): { moveSpeed: number, attack: number, damageTaken: number }
	return GrantLogic.multipliers(
		entryOf(entity).grants,
		AbilityDefs,
		equippedOf(entity),
		ItemDefs,
		Config.Combat.MinDamageTakenMultiplier
	)
end

-- 移動速度などの見た目に出る効果を反映する
function GrantService.refreshEffects(entity: Entity)
	if entity:IsA("Player") then
		local character = entity.Character
		local humanoid = character and character:FindFirstChildOfClass("Humanoid")
		if humanoid then
			humanoid.WalkSpeed = Config.Combat.BaseWalkSpeed * GrantService.multipliers(entity).moveSpeed
		end
	else
		-- 敵は頭上の表示用に属性へ書く（クライアントへは属性で届く）
		local names = {}
		for _, grant in entryOf(entity).grants do
			table.insert(names, grant.ability)
		end
		entity:SetAttribute("Grants", table.concat(names, ","))
	end
end

local function changed(entity: Entity)
	GrantService.refreshEffects(entity)
	if hooks.onChanged then
		hooks.onChanged(entity)
	end
end

function GrantService.apply(entity: Entity, abilityId: any): (boolean, string?)
	local entry = entryOf(entity)
	local ok, result = GrantLogic.apply(
		entry.grants,
		entry.cooldowns,
		abilityId,
		now(),
		GrantService.capacityOf(entity),
		AbilityDefs,
		entry.seq + 1
	)
	if not ok then
		return false, result
	end
	entry.seq += 1
	entry.grants = result
	if hooks.onApply then
		hooks.onApply(entity, abilityId)
	end
	changed(entity)
	return true, nil
end

-- which は能力 ID か "all"
function GrantService.release(entity: Entity, which: any): (boolean, string?)
	local entry = entryOf(entity)
	local ok, result, cooldowns, released = GrantLogic.release(
		entry.grants,
		entry.cooldowns,
		which,
		now(),
		Config.Grant.ReleaseCooldown
	)
	if not ok then
		return false, result
	end
	entry.grants = result
	entry.cooldowns = cooldowns :: { [string]: number }
	if hooks.onRelease then
		hooks.onRelease(entity, released :: { string })
	end
	changed(entity)
	return true, nil
end

-- 1 つ取り除く（剥がされる・必殺技の突進で剥がされる）。クールダウンは付けない
function GrantService.removeAbility(entity: Entity, abilityId: string): boolean
	local entry = entryOf(entity)
	local found, kept = GrantLogic.remove(entry.grants, abilityId)
	if found then
		entry.grants = kept
		changed(entity)
	end
	return found
end

-- actor が target の付与を剥がす。
-- ・target がプレイヤー：決闘リングの対戦相手のときだけ。代価として actor の一番安い付与を 1 つ失う
-- ・target が敵：代価なし（練習相手の役割。PHASE0_PLAN_v2 5.1）
-- 敵かどうか・距離の確認は呼び出し側（Main）で済ませておく
function GrantService.strip(actor: Player, target: Entity, abilityId: any): (boolean, string?)
	if type(abilityId) ~= "string" or AbilityDefs[abilityId] == nil then
		return false, "unknown_ability"
	end
	if target == actor then
		return false, "bad_target"
	end
	if not GrantService.has(target, abilityId) then
		return false, "not_active"
	end

	if target:IsA("Player") then
		if not BattleStateService.canAffectPlayer(actor, target) then
			return false, "not_in_battle"
		end
		local payWith = GrantLogic.pickLowest(entryOf(actor).grants, AbilityDefs)
		if payWith == nil then
			return false, "no_grant_to_pay"
		end
		GrantService.removeAbility(actor, payWith)
	end

	GrantService.removeAbility(target, abilityId)
	if hooks.onStrip then
		hooks.onStrip(actor, target, abilityId)
	end
	return true, nil
end

-- 必殺技で自分の付与をすべて消費する。戻り値：消費したコストの合計
function GrantService.consumeAll(entity: Entity): number
	local entry = entryOf(entity)
	local cost = GrantLogic.used(entry.grants, AbilityDefs)
	entry.grants = {}
	changed(entity)
	return cost
end

-- 倒れた・消えたときに全部なくす
function GrantService.clear(entity: Entity)
	local entry = entries[entity]
	if entry and #entry.grants > 0 then
		entry.grants = {}
		changed(entity)
	end
end

function GrantService.forget(entity: Entity)
	entries[entity] = nil
end

-- クライアントに送る形
function GrantService.view(entity: Entity): any
	local entry = entryOf(entity)
	local list = {}
	for _, grant in entry.grants do
		table.insert(list, grant.ability)
	end
	return {
		list = list,
		used = GrantLogic.used(entry.grants, AbilityDefs),
		capacity = GrantService.capacityOf(entity),
		cooldownEnds = table.clone(entry.cooldowns), -- workspace:GetServerTimeNow() の時刻
	}
end

function GrantService.init()
	Players.PlayerRemoving:Connect(function(player)
		entries[player] = nil
	end)
end

return GrantService
