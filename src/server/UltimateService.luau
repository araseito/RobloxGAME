--!strict
-- 必殺技のゲージと発動（サーバー権威）。
-- ・ゲージは戦闘状態のときだけ溜まり、戦闘が終わると 0 に戻る（保存しない）
-- ・ゲージ 100 かつ戦闘状態のときだけ撃てる
-- ・技の種類は撃った瞬間の「一番コストの高い付与」で決まる
-- ・詠唱（Config.Ultimate.CastTime 秒）の後に、そのとき残っている付与をすべて消費して威力が決まる。
--   詠唱中に剥がされると、消費できるコストが減って弱くなる

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))
local UltimateDefs = require(Shared:WaitForChild("UltimateDefs"))
local GrantLogic = require(Shared:WaitForChild("Logic"):WaitForChild("GrantLogic"))
local CombatLogic = require(Shared:WaitForChild("Logic"):WaitForChild("CombatLogic"))

local BattleStateService = require(script.Parent.BattleStateService)
local GrantService = require(script.Parent.GrantService)
local CombatService = require(script.Parent.CombatService)
local Remotes = require(script.Parent.Remotes)
local Metrics = require(script.Parent.Metrics)

local UltimateService = {}

local gauges: { [Player]: number } = {}
local casting: { [Player]: string } = {} -- 詠唱中の技 ID

local hooks = {
	onChanged = nil :: ((Player) -> ())?,
}

function UltimateService.setHooks(newHooks: any)
	hooks.onChanged = newHooks.onChanged
end

local function changed(player: Player)
	if hooks.onChanged then
		hooks.onChanged(player)
	end
end

function UltimateService.get(player: Player): number
	return gauges[player] or 0
end

function UltimateService.isCasting(player: Player): boolean
	return casting[player] ~= nil
end

-- 戦闘状態のときだけ溜まる（戦闘外で付与と解除を繰り返して溜める抜け道をふさぐ）
function UltimateService.add(player: Player, amount: number)
	if not BattleStateService.inCombat(player) then
		return
	end
	local before = UltimateService.get(player)
	local after = CombatLogic.addGauge(before, amount, Config.Ultimate.GaugeMax)
	if after ~= before then
		gauges[player] = after
		changed(player)
	end
end

function UltimateService.reset(player: Player)
	if (gauges[player] or 0) ~= 0 then
		gauges[player] = 0
		changed(player)
	end
end

-- 開発用（DevTools）：戦闘状態にしてゲージを満タンにする
function UltimateService.fillForTest(player: Player)
	BattleStateService.notePve(player, nil)
	gauges[player] = Config.Ultimate.GaugeMax
	changed(player)
end

local function resolve(player: Player, ultimateId: string)
	casting[player] = nil
	if player.Parent == nil or CombatService.rootOf(player) == nil then
		changed(player)
		return
	end

	local def = UltimateDefs[ultimateId]
	local consumed = GrantService.consumeAll(player)
	local power = CombatLogic.ultimatePower(consumed, Config.Ultimate.BasePower, Config.Ultimate.PowerPerCost)
	local hits = 0

	if def.kind == "dash" then
		for _, target in CombatService.targetsInDash(player, def.range, def.width) do
			if target.kind == "enemy" then
				if CombatService.hitEnemy(player, target.model, power, nil) > 0 then
					hits += 1
				end
				if def.stripsAbility then
					GrantService.removeAbility(target.model, def.stripsAbility)
				end
			elseif target.player then
				-- targetsInDash は対戦相手しか返さないが、hitPlayer でもう一度確かめる
				if CombatService.hitPlayer(player, target.player, power, nil, nil) > 0 then
					hits += 1
					if def.stripsAbility then
						GrantService.removeAbility(target.player, def.stripsAbility)
					end
				end
			end
		end
	elseif def.kind == "single" then
		-- 単体技は締め扱い：吹き飛ばす（相手が鉄壁なら吹き飛ばない）。
		-- 付与は撃つ時点で消費済みなので、剛力の「ガードを割る」は乗らない
		local target = CombatService.singleTarget(player, def.range)
		if target then
			local options = { finisher = true }
			local dealt = if target.kind == "enemy"
				then CombatService.hitEnemy(player, target.model, power, options)
				else CombatService.hitPlayer(player, target.player :: Player, power, nil, options)
			if dealt > 0 then
				hits += 1
			end
		end
	elseif def.kind == "shield" then
		CombatService.addShield(player, power, def.shieldDuration)
	end

	Remotes.fireAll("Ultimate_Broadcast", {
		phase = "resolve",
		userId = player.UserId,
		ultimate = ultimateId,
		power = power,
		consumedCost = consumed,
		hits = hits,
	})
	changed(player)
end

function UltimateService.cast(player: Player): (boolean, string?, string?)
	if casting[player] then
		return false, "casting", nil
	end
	if CombatService.rootOf(player) == nil then
		return false, "dead", nil
	end
	if not BattleStateService.inCombat(player) then
		return false, "not_in_combat", nil
	end
	if UltimateService.get(player) < Config.Ultimate.GaugeMax then
		return false, "gauge_not_full", nil
	end

	local highest = GrantLogic.pickHighest(GrantService.list(player), AbilityDefs)
	local ultimateId = if highest then AbilityDefs[highest].ultimate else Config.Ultimate.DefaultUltimate

	gauges[player] = 0
	casting[player] = ultimateId
	Metrics.event(player, Metrics.Events.UltimateCast)
	Remotes.fireAll("Ultimate_Broadcast", {
		phase = "start",
		userId = player.UserId,
		ultimate = ultimateId,
		castTime = Config.Ultimate.CastTime,
	})
	changed(player)

	task.delay(Config.Ultimate.CastTime, resolve, player, ultimateId)
	return true, nil, ultimateId
end

function UltimateService.init()
	Players.PlayerRemoving:Connect(function(player)
		gauges[player] = nil
		casting[player] = nil
	end)
end

return UltimateService
