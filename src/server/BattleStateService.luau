--!strict
-- 戦闘状態を判定する唯一の場所。
-- ・PvE：敵を攻撃した／されたときに入り、Config.Combat.PveCombatTimeout 秒攻撃がなければ終わる
-- ・PvP：決闘リングの対戦相手どうしだけ（Step 4 で RingService が setPvpPair を呼ぶ）
-- 対人の効果（ダメージ・ノックバック・剥がし）は canAffectPlayer が true のときだけ通す。

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"))

type PveState = { expiresAt: number, target: Model? }

local BattleStateService = {}

local pve: { [Player]: PveState } = {}
local pvpOpponent: { [Player]: Player } = {}

local hooks = {
	onStarted = nil :: ((Player) -> ())?,
	onEnded = nil :: ((Player) -> ())?,
}

function BattleStateService.setHooks(newHooks: { onStarted: ((Player) -> ())?, onEnded: ((Player) -> ())? })
	hooks.onStarted = newHooks.onStarted
	hooks.onEnded = newHooks.onEnded
end

function BattleStateService.inCombat(player: Player): boolean
	return pve[player] ~= nil or pvpOpponent[player] ~= nil
end

-- 敵を攻撃した／されたときに呼ぶ。target が nil なら今の相手を変えない
function BattleStateService.notePve(player: Player, target: Model?)
	local wasInCombat = BattleStateService.inCombat(player)
	local current = pve[player]
	pve[player] = {
		expiresAt = os.clock() + Config.Combat.PveCombatTimeout,
		target = target or (if current then current.target else nil),
	}
	if not wasInCombat and hooks.onStarted then
		hooks.onStarted(player)
	end
end

function BattleStateService.getPveTarget(player: Player): Model?
	local state = pve[player]
	return if state then state.target else nil
end

function BattleStateService.getPvpOpponent(player: Player): Player?
	return pvpOpponent[player]
end

-- 対人の効果を通してよいか。決闘リングで互いに相手として登録されている 2 人だけ true
function BattleStateService.canAffectPlayer(attacker: Player, victim: Player): boolean
	if attacker == victim then
		return false
	end
	return pvpOpponent[attacker] == victim and pvpOpponent[victim] == attacker
end

-- 決闘リング用（Step 4）
function BattleStateService.setPvpPair(a: Player, b: Player)
	pvpOpponent[a] = b
	pvpOpponent[b] = a
	if hooks.onStarted then
		hooks.onStarted(a)
		hooks.onStarted(b)
	end
end

local function finish(player: Player)
	if hooks.onEnded then
		hooks.onEnded(player)
	end
end

-- PvP を終える（Step 4）
function BattleStateService.clearPvp(player: Player)
	local opponent = pvpOpponent[player]
	pvpOpponent[player] = nil
	if opponent and pvpOpponent[opponent] == player then
		pvpOpponent[opponent] = nil
		if not BattleStateService.inCombat(opponent) then
			finish(opponent)
		end
	end
	if not BattleStateService.inCombat(player) then
		finish(player)
	end
end

-- 倒れた・退出したときなど、すべての戦闘状態を終える
function BattleStateService.endAll(player: Player)
	local was = BattleStateService.inCombat(player)
	pve[player] = nil
	if pvpOpponent[player] then
		BattleStateService.clearPvp(player)
	elseif was then
		finish(player)
	end
end

function BattleStateService.init()
	task.spawn(function()
		while true do
			task.wait(Config.Combat.BattleTickInterval)
			local now = os.clock()
			for player, state in pve do
				if now >= state.expiresAt then
					pve[player] = nil
					if not BattleStateService.inCombat(player) then
						finish(player)
					end
				end
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		pve[player] = nil
		if pvpOpponent[player] then
			BattleStateService.clearPvp(player)
		end
	end)
end

return BattleStateService
