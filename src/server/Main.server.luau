--!strict
-- サーバーの起動順と、サービスどうしのつなぎ込み、Remote の受け口だけを書く

local Server = script.Parent

local Remotes = require(Server.Remotes)
Remotes.init() -- Net フォルダを最初に作る（クライアントが待っている）

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local DataService = require(Server.DataService)
local StateSync = require(Server.StateSync)
local Metrics = require(Server.Metrics)
local BattleStateService = require(Server.BattleStateService)
local GrantService = require(Server.GrantService)
local CombatService = require(Server.CombatService)
local UltimateService = require(Server.UltimateService)
local EquipmentService = require(Server.EquipmentService)
local CombatSync = require(Server.CombatSync)
local TrainingDummy = require(Server.TrainingDummy)
local PuzzleBoxService = require(Server.PuzzleBoxService)
local QuestService = require(Server.QuestService)
local DevTools = require(Server.DevTools)

type Result = Remotes.Result

local function isPlayer(entity: Instance): boolean
	return entity:IsA("Player")
end

-- サービスどうしのつなぎ込み ---------------------------------------------------
-- （互いに require し合うと循環するので、ゲージの加算や表示の更新はここでつなぐ）

GrantService.setHooks({
	onApply = function(entity: Instance)
		if isPlayer(entity) then
			UltimateService.add(entity :: Player, Config.Ultimate.OnGrant)
		end
	end,
	onRelease = function(entity: Instance)
		if isPlayer(entity) then
			UltimateService.add(entity :: Player, Config.Ultimate.OnRelease)
		end
	end,
	onStrip = function(actor: Player)
		UltimateService.add(actor, Config.Ultimate.OnStrip)
	end,
	onChanged = function(entity: Instance)
		if isPlayer(entity) then
			CombatService.refreshSpeed(entity :: Player) -- 疾風の付け外しで移動速度が変わる
			CombatSync.push(entity :: Player)
		end
	end,
})

CombatService.setHooks({
	onDealt = function(player: Player, amount: number)
		UltimateService.add(player, amount * Config.Ultimate.PerDamageDealt)
	end,
	onTaken = function(player: Player, amount: number)
		UltimateService.add(player, amount * Config.Ultimate.PerDamageTaken)
	end,
	onKill = function(player: Player, enemy: any)
		UltimateService.add(player, Config.Ultimate.OnMonsterKill)
		QuestService.record(player, { kind = "kill", monster = enemy.id })
	end,
	onStateChanged = function(player: Player)
		CombatSync.push(player)
	end,
})

BattleStateService.setHooks({
	onStarted = function(player: Player)
		CombatSync.push(player)
	end,
	onEnded = function(player: Player)
		UltimateService.reset(player) -- 戦闘が終わるとゲージは 0 に戻る
		CombatSync.push(player)
	end,
})

UltimateService.setHooks({
	onChanged = function(player: Player)
		CombatSync.push(player)
	end,
})

EquipmentService.setHooks({
	onChanged = function(player: Player)
		CombatService.refreshSpeed(player)
		CombatSync.push(player)
	end,
})

DataService.Loaded:Connect(function(player: Player)
	Metrics.onboarding(player, DataService.getProfile(player), 1)
	EquipmentService.validate(player)
	CombatService.refreshSpeed(player)
	CombatSync.push(player)
	QuestService.retryPending(player)
end)

-- Remote の受け口 ---------------------------------------------------------------

local function result(ok: boolean, reason: string?): Result
	return { ok = ok, reason = reason }
end

Remotes.onInvoke("GetSnapshot", function(player: Player): Result
	local profile = DataService.waitForProfile(player, Config.Data.ProfileWaitTimeout)
	if profile == nil then
		return result(false, "not_loaded")
	end
	CombatSync.push(player)
	return { ok = true, state = StateSync.snapshot(player) }
end)

Remotes.onInvoke("Grant_Apply", function(player: Player, abilityId: any): Result
	if CombatService.rootOf(player) == nil then
		return result(false, "dead")
	end
	return result(GrantService.apply(player, abilityId))
end)

Remotes.onInvoke("Grant_Release", function(player: Player, which: any): Result
	return result(GrantService.release(player, which))
end)

-- 剥がす相手はサーバーが決める：決闘リングの対戦相手 → 今戦っている敵、の順
Remotes.onInvoke("Grant_Strip", function(player: Player, abilityId: any): Result
	if CombatService.rootOf(player) == nil then
		return result(false, "dead")
	end

	local opponent = BattleStateService.getPvpOpponent(player)
	if opponent then
		return result(GrantService.strip(player, opponent, abilityId))
	end

	local target = BattleStateService.getPveTarget(player)
	local enemy = CombatService.getEnemy(target)
	if target == nil or enemy == nil or not enemy.alive then
		return result(false, "no_target")
	end
	if CombatService.distance(player, target) > Config.Grant.StripRange then
		return result(false, "out_of_range")
	end
	return result(GrantService.strip(player, target, abilityId))
end)

Remotes.onInvoke("Piece_Place", function(player: Player, pieceId: any): Result
	local ok, reason = PuzzleBoxService.place(player, pieceId)
	if ok then
		QuestService.retryPending(player) -- 未装着の枠が空いたので、持ちきれなかった報酬をもう一度
	end
	return result(ok, reason)
end)

Remotes.onInvoke("Ultimate_Cast", function(player: Player): Result
	local ok, reason, ultimateId = UltimateService.cast(player)
	return { ok = ok, reason = reason, ultimate = ultimateId }
end)

-- まとめて受ける操作（kind ごとにサーバーで検証する）
local actions: { [string]: (Player, any) -> (boolean, string?) } = {
	equip = EquipmentService.equip,
	unequip = EquipmentService.unequip,
	guard = CombatService.setGuard, -- id = true（押した）/ false（離した）
	dash = function(player: Player)
		return CombatService.dash(player)
	end,
}

Remotes.onInvoke("Action", function(player: Player, kind: any, id: any): Result
	local handler = if type(kind) == "string" then actions[kind] else nil
	if handler == nil then
		return result(false, "unknown_action")
	end
	return result(handler(player, id))
end)

Remotes.onEvent("Attack", function(player: Player, target: any)
	local outcome = CombatService.basicAttack(player, target)
	if outcome == "not_in_battle" then
		-- 戦闘状態でない相手を攻撃した（何も起きない）ことを本人にだけ知らせる
		Remotes.fire(player, "Toast", "not_in_battle")
	end
end)

-- 起動 -----------------------------------------------------------------------

BattleStateService.init()
GrantService.init()
CombatService.init()
UltimateService.init()
DataService.init()
TrainingDummy.init()
QuestService.init()
DevTools.init()

print("[Server] Phase 0 起動完了（Step 3）")
