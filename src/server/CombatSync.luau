--!strict
-- 戦闘まわりの表示用データ（付与・ゲージ・戦闘状態・シールド）をクライアントへ送る。
-- 保存はしないので、プロフィールの StateSync とは分けている。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

local BattleStateService = require(script.Parent.BattleStateService)
local GrantService = require(script.Parent.GrantService)
local CombatService = require(script.Parent.CombatService)
local UltimateService = require(script.Parent.UltimateService)
local Remotes = require(script.Parent.Remotes)

local CombatSync = {}

local pending: { [Player]: boolean } = {}

local function send(player: Player)
	pending[player] = nil
	if player.Parent == nil then
		return
	end
	local fighter = CombatService.view(player)
	Remotes.fire(player, "State_Delta", {
		combat = {
			grants = GrantService.view(player),
			gauge = UltimateService.get(player),
			gaugeMax = Config.Ultimate.GaugeMax,
			inCombat = BattleStateService.inCombat(player),
			casting = UltimateService.isCasting(player),
			shield = fighter.shield,
			guarding = fighter.guarding,
			stunnedUntil = fighter.stunnedUntil,
			dashReadyAt = fighter.dashReadyAt,
			comboStep = fighter.comboStep,
			comboHits = fighter.comboHits,
		},
	})
end

-- 同じフレームで何度呼ばれても 1 回だけ送る
function CombatSync.push(player: Player)
	if pending[player] then
		return
	end
	pending[player] = true
	task.defer(send, player)
end

return CombatSync
