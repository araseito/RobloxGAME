--!strict
-- ダメージを受け持つ唯一の窓口と、戦闘の操作（4 段コンボ・ガード・回避ダッシュ・スタン）。
-- ・敵（木人・モンスター）の HP はここで管理する（Humanoid は使わず、属性でクライアントへ見せる）
-- ・プレイヤーへの攻撃は、攻撃者がプレイヤーなら BattleStateService.canAffectPlayer が
--   true のときだけ通す。決闘リングの対戦相手以外にはダメージ・吹き飛ばし・スタンを一切入れない
-- ・付与の「できること」（AbilityDefs の perk）：
--   疾風 dash_fast    ダッシュのクールダウン半分
--   剛力 guard_break  締めで相手のガードを割る
--   鉄壁 no_knockback 吹き飛ばされない

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))
local CombatLogic = require(Shared:WaitForChild("Logic"):WaitForChild("CombatLogic"))

local BattleStateService = require(script.Parent.BattleStateService)
local GrantService = require(script.Parent.GrantService)
local Remotes = require(script.Parent.Remotes)

export type Enemy = {
	model: Model,
	id: string, -- MonsterDefs の ID、または "dummy"
	maxHealth: number,
	health: number,
	alive: boolean,
	onDeath: ((Model, Player?) -> ())?,
}

-- 攻撃・スタンの対象：Player か敵の Model
type Fighter = Instance

local CombatService = {}

CombatService.ENEMY_TAG = "Enemy"

local enemies: { [Model]: Enemy } = {}

-- プレイヤーごとの操作の状態
type PlayerState = {
	comboStep: number?,
	lastAttackAt: number?,
	guarding: boolean,
	dashReadyAt: number,
}
local playerStates: { [Player]: PlayerState } = {}

local stunnedUntil: { [Fighter]: number } = {}
local shields: { [Player]: { amount: number, expiresAt: number } } = {}

local hooks = {
	onDealt = nil :: ((Player, number) -> ())?, -- 攻撃者が与えたダメージ
	onTaken = nil :: ((Player, number) -> ())?, -- プレイヤーが受けたダメージ
	onKill = nil :: ((Player, Enemy) -> ())?, -- プレイヤーが敵を倒した
	onStateChanged = nil :: ((Player) -> ())?, -- ガード・スタン・ダッシュ・シールドなど表示が変わった
}

function CombatService.setHooks(newHooks: any)
	hooks.onDealt = newHooks.onDealt
	hooks.onTaken = newHooks.onTaken
	hooks.onKill = newHooks.onKill
	hooks.onStateChanged = newHooks.onStateChanged
end

local function now(): number
	return workspace:GetServerTimeNow()
end

local function stateOf(player: Player): PlayerState
	local state = playerStates[player]
	if not state then
		state = { comboStep = nil, lastAttackAt = nil, guarding = false, dashReadyAt = 0 }
		playerStates[player] = state
	end
	return state
end

local function notifyState(player: Player)
	if hooks.onStateChanged then
		hooks.onStateChanged(player)
	end
end

local function hasPerk(fighter: Fighter, perk: string): boolean
	for _, grant in GrantService.list(fighter) do
		local def = AbilityDefs[grant.ability]
		if def and def.perk == perk then
			return true
		end
	end
	return false
end
CombatService.hasPerk = hasPerk

-- 位置 -------------------------------------------------------------------

local function rootOf(player: Player): BasePart?
	local character = player.Character
	if not character then
		return nil
	end
	local humanoid = character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	return if root and root:IsA("BasePart") then root else nil
end
CombatService.rootOf = rootOf

local function positionOf(model: Model): Vector3
	return model:GetPivot().Position
end

function CombatService.distance(player: Player, model: Model): number
	local root = rootOf(player)
	if not root then
		return math.huge
	end
	return (positionOf(model) - root.Position).Magnitude
end

-- 攻撃が victim の正面から来たか（ガードが効くか）
local function isFront(victimCFrame: CFrame, attackerPosition: Vector3): boolean
	local look = victimCFrame.LookVector
	local toAttacker = attackerPosition - victimCFrame.Position
	return CombatLogic.isFront(look.X, look.Z, toAttacker.X, toAttacker.Z)
end

-- スタンと移動速度 ------------------------------------------------------------

function CombatService.isStunned(fighter: Fighter): boolean
	local untilAt = stunnedUntil[fighter]
	return untilAt ~= nil and untilAt > now()
end

-- 移動速度 = 基本 × 付与の倍率 × ガード中の倍率。スタン中は 0
function CombatService.refreshSpeed(player: Player)
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid then
		return
	end
	if CombatService.isStunned(player) then
		humanoid.WalkSpeed = 0
		return
	end
	local speed = Config.Combat.BaseWalkSpeed * GrantService.multipliers(player).moveSpeed
	if stateOf(player).guarding then
		speed *= Config.Combat.Guard.WalkSpeedMultiplier
	end
	humanoid.WalkSpeed = speed
end

local function stun(fighter: Fighter, seconds: number)
	local untilAt = now() + seconds
	if (stunnedUntil[fighter] or 0) < untilAt then
		stunnedUntil[fighter] = untilAt
	end
	if fighter:IsA("Player") then
		local player = fighter :: Player
		stateOf(player).guarding = false
		CombatService.refreshSpeed(player)
		notifyState(player)
		task.delay(seconds + 0.05, function()
			if player.Parent and not CombatService.isStunned(player) then
				CombatService.refreshSpeed(player)
				notifyState(player)
			end
		end)
	else
		fighter:SetAttribute("Stunned", true)
		task.delay(seconds + 0.05, function()
			if fighter.Parent and not CombatService.isStunned(fighter) then
				fighter:SetAttribute("Stunned", false)
			end
		end)
	end
end

-- 吹き飛ばし ---------------------------------------------------------------

-- 敵は server が動かしているので、ここで押し出す（Anchored の Model を少しずつ動かす）
local function knockEnemy(model: Model, fromPosition: Vector3)
	local direction = positionOf(model) - fromPosition
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		return
	end
	local step = direction.Unit * Config.Combat.Knockback.EnemyDistance
	local start = model:GetPivot()
	local duration = Config.Combat.Knockback.Duration
	local elapsed = 0
	local connection: RBXScriptConnection? = nil
	connection = RunService.Heartbeat:Connect(function(dt)
		elapsed += dt
		local t = math.min(1, elapsed / duration)
		if model.Parent then
			model:PivotTo(start + step * t)
		end
		if t >= 1 and connection then
			connection:Disconnect()
		end
	end)
end

-- プレイヤーのキャラクターは本人の端末が動かしているので、本人に飛ばしてもらう
local function knockPlayer(player: Player, fromPosition: Vector3)
	local root = rootOf(player)
	if not root then
		return
	end
	local direction = root.Position - fromPosition
	direction = Vector3.new(direction.X, 0, direction.Z)
	if direction.Magnitude < 0.01 then
		direction = -root.CFrame.LookVector
	end
	local velocity = direction.Unit * Config.Combat.Knockback.Horizontal
		+ Vector3.new(0, Config.Combat.Knockback.Vertical, 0)
	Remotes.fire(player, "Knockback", { velocity = velocity, duration = Config.Combat.Knockback.Duration })
end

-- 敵 ---------------------------------------------------------------------

local function syncEnemyAttributes(enemy: Enemy)
	enemy.model:SetAttribute("EnemyId", enemy.id)
	enemy.model:SetAttribute("Health", enemy.health)
	enemy.model:SetAttribute("MaxHealth", enemy.maxHealth)
	enemy.model:SetAttribute("Alive", enemy.alive)
end

function CombatService.registerEnemy(model: Model, id: string, maxHealth: number, onDeath: ((Model, Player?) -> ())?)
	local enemy: Enemy = {
		model = model,
		id = id,
		maxHealth = maxHealth,
		health = maxHealth,
		alive = true,
		onDeath = onDeath,
	}
	enemies[model] = enemy
	syncEnemyAttributes(enemy)
	CollectionService:AddTag(model, CombatService.ENEMY_TAG)
	return enemy
end

function CombatService.unregisterEnemy(model: Model)
	enemies[model] = nil
	stunnedUntil[model] = nil
	GrantService.forget(model)
	CollectionService:RemoveTag(model, CombatService.ENEMY_TAG)
end

function CombatService.getEnemy(target: any): Enemy?
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return nil
	end
	return enemies[target :: Model]
end

-- 倒れた敵を元に戻す（木人の復活・モンスターの再出現）
function CombatService.reviveEnemy(model: Model)
	local enemy = enemies[model]
	if enemy then
		enemy.health = enemy.maxHealth
		enemy.alive = true
		stunnedUntil[model] = nil
		model:SetAttribute("Stunned", false)
		syncEnemyAttributes(enemy)
	end
end

-- ダメージ -----------------------------------------------------------------

export type HitOptions = {
	finisher: boolean?, -- 締め（吹き飛ばす・ガードを割れる）
	fromPosition: Vector3?, -- 攻撃が来た位置（吹き飛ばしの向き）
}

-- プレイヤーが敵に当てる。戻り値：与えたダメージ
function CombatService.hitEnemy(attacker: Player, model: Model, base: number, options: HitOptions?): number
	local enemy = enemies[model]
	if not enemy or not enemy.alive then
		return 0
	end
	local opts = options or {}
	local outcome = CombatLogic.resolveHit({
		finisher = opts.finisher == true,
		guarding = false, -- Phase 0 の敵はガードしない
		front = false,
		guardBreak = hasPerk(attacker, "guard_break"),
		noKnockback = hasPerk(model, "no_knockback"),
	}, Config.Combat.Guard.DamageMultiplier)

	local amount = CombatLogic.damage(
		base * outcome.damageMultiplier,
		GrantService.multipliers(attacker).attack,
		GrantService.multipliers(model).damageTaken,
		nil
	)
	if amount <= 0 then
		return 0
	end

	enemy.health = math.max(0, enemy.health - amount)
	BattleStateService.notePve(attacker, model)
	if hooks.onDealt then
		hooks.onDealt(attacker, amount)
	end

	if enemy.health <= 0 then
		enemy.alive = false
		GrantService.clear(model)
		if hooks.onKill then
			hooks.onKill(attacker, enemy)
		end
		if enemy.onDeath then
			task.spawn(enemy.onDeath, model, attacker)
		end
	elseif outcome.knockback then
		-- 吹き飛ばすと、予備動作中の攻撃も止まる（敵側でスタンを確かめる）
		local root = rootOf(attacker)
		knockEnemy(model, opts.fromPosition or (if root then root.Position else positionOf(model)))
		stun(model, Config.Combat.FinisherStunSeconds)
	end
	syncEnemyAttributes(enemy)
	return amount
end

-- プレイヤーに当てる（唯一の入り口）。
-- attacker がプレイヤーのときは、決闘リングの対戦相手でなければ 0 を返して何もしない。
-- attacker が nil のときは敵からの攻撃。sourceEnemy でどの敵かを渡す
function CombatService.hitPlayer(attacker: Player?, victim: Player, base: number, sourceEnemy: Model?, options: HitOptions?): number
	if attacker ~= nil and not BattleStateService.canAffectPlayer(attacker, victim) then
		return 0 -- 戦闘状態でない相手には、ダメージ・吹き飛ばし・スタンのどれも入れない
	end
	local victimRoot = rootOf(victim)
	local character = victim.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not victimRoot or not humanoid then
		return 0
	end

	local opts = options or {}
	local attackerRoot = if attacker then rootOf(attacker) else nil
	local fromPosition = opts.fromPosition
		or (if attackerRoot then attackerRoot.Position elseif sourceEnemy then positionOf(sourceEnemy) else victimRoot.Position)

	local outcome = CombatLogic.resolveHit({
		finisher = opts.finisher == true,
		guarding = stateOf(victim).guarding,
		front = isFront(victimRoot.CFrame, fromPosition),
		guardBreak = if attacker then hasPerk(attacker, "guard_break") else false,
		noKnockback = hasPerk(victim, "no_knockback"),
	}, Config.Combat.Guard.DamageMultiplier)

	local attackMultiplier = if attacker then GrantService.multipliers(attacker).attack else 1
	local pvpCap = if attacker then humanoid.MaxHealth * Config.Ultimate.PvpDamageCapRatio else nil
	local amount = CombatLogic.damage(
		base * outcome.damageMultiplier,
		attackMultiplier,
		GrantService.multipliers(victim).damageTaken,
		pvpCap
	)

	local shield = shields[victim]
	if shield and shield.expiresAt > now() then
		local remaining, passed = CombatLogic.absorb(shield.amount, amount)
		shield.amount = remaining
		amount = passed
		if remaining <= 0 then
			shields[victim] = nil
		end
		notifyState(victim)
	end

	if outcome.guardBroken then
		stun(victim, Config.Combat.Guard.BreakStunSeconds)
	elseif outcome.knockback then
		knockPlayer(victim, fromPosition)
		stun(victim, Config.Combat.FinisherStunSeconds)
	end

	if sourceEnemy then
		BattleStateService.notePve(victim, sourceEnemy)
	end
	if amount <= 0 then
		return 0
	end

	humanoid.Health = math.max(0, humanoid.Health - amount)
	if hooks.onTaken then
		hooks.onTaken(victim, amount)
	end
	if attacker and hooks.onDealt then
		hooks.onDealt(attacker, amount)
	end
	return amount
end

-- シールド（不動・鉄壁聖域）
function CombatService.addShield(player: Player, amount: number, duration: number)
	shields[player] = { amount = amount, expiresAt = now() + duration }
	notifyState(player)
	task.delay(duration, function()
		local shield = shields[player]
		if shield and shield.expiresAt <= now() then
			shields[player] = nil
			notifyState(player)
		end
	end)
end

function CombatService.shieldOf(player: Player): number
	local shield = shields[player]
	if shield and shield.expiresAt > now() then
		return shield.amount
	end
	return 0
end

-- 操作：4 段コンボ ------------------------------------------------------------

-- 戻り値：結果コード（"hit" / "not_in_battle" / それ以外は失敗理由）
function CombatService.basicAttack(player: Player, target: any): string
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return "bad_target"
	end
	local root = rootOf(player)
	if not root then
		return "dead"
	end
	if CombatService.isStunned(player) then
		return "stunned"
	end
	local state = stateOf(player)
	if state.guarding then
		return "guarding"
	end

	local t = now()
	if state.lastAttackAt and t - state.lastAttackAt < Config.Combat.ComboInterval - Config.Combat.IntervalTolerance then
		return "too_fast"
	end

	local model = target :: Model
	local maxRange = Config.Combat.BasicRange + Config.Combat.RangeTolerance
	if (positionOf(model) - root.Position).Magnitude > maxRange then
		return "out_of_range"
	end

	local enemy = enemies[model]
	local victim = if enemy then nil else Players:GetPlayerFromCharacter(model)
	if not enemy and not victim then
		return "bad_target"
	end
	if enemy and not enemy.alive then
		return "dead_target"
	end

	local hits = #Config.Combat.ComboDamage
	local step = CombatLogic.nextComboStep(state.comboStep, state.lastAttackAt, t, Config.Combat.ComboResetSeconds, hits)
	state.comboStep = step
	state.lastAttackAt = t
	local options: HitOptions = { finisher = step == hits, fromPosition = root.Position }
	local base = Config.Combat.ComboDamage[step]
	notifyState(player)

	if enemy then
		CombatService.hitEnemy(player, model, base, options)
		return "hit"
	end
	local dealt = CombatService.hitPlayer(player, victim :: Player, base, nil, options)
	return if dealt > 0 then "hit" else "not_in_battle"
end

-- 操作：ガード（押している間だけ）----------------------------------------------

function CombatService.setGuard(player: Player, on: any): (boolean, string?)
	if type(on) ~= "boolean" then
		return false, "bad_value"
	end
	if rootOf(player) == nil then
		return false, "dead"
	end
	local state = stateOf(player)
	if on and CombatService.isStunned(player) then
		return false, "stunned"
	end
	if state.guarding == on then
		return true, nil
	end
	state.guarding = on
	CombatService.refreshSpeed(player)
	notifyState(player)
	return true, nil
end

-- 操作：回避ダッシュ。サーバーは可否とクールダウンだけを決め、動きは本人の端末が出す ----------

function CombatService.dash(player: Player): (boolean, string?)
	if rootOf(player) == nil then
		return false, "dead"
	end
	if CombatService.isStunned(player) then
		return false, "stunned"
	end
	local state = stateOf(player)
	local t = now()
	if state.dashReadyAt > t then
		return false, "dash_cooldown"
	end
	local cooldown = CombatLogic.dashCooldown(
		Config.Combat.Dash.Cooldown,
		hasPerk(player, "dash_fast"),
		Config.Combat.Dash.GaleCooldownMultiplier
	)
	state.dashReadyAt = t + cooldown
	if state.guarding then
		state.guarding = false
		CombatService.refreshSpeed(player)
	end
	notifyState(player)
	return true, nil
end

-- 敵の攻撃 ---------------------------------------------------------------------

-- 敵の大振り。範囲内にいて、その敵と戦っているプレイヤーに当てる（締め扱い：吹き飛ばす）
function CombatService.enemySwing(model: Model, damage: number, range: number): number
	local enemy = enemies[model]
	if not enemy or not enemy.alive or CombatService.isStunned(model) then
		return 0
	end
	local origin = positionOf(model)
	local hits = 0
	for _, player in Players:GetPlayers() do
		local root = rootOf(player)
		if root and BattleStateService.getPveTarget(player) == model and (root.Position - origin).Magnitude <= range then
			if CombatService.hitPlayer(nil, player, damage, model, { finisher = true, fromPosition = origin }) > 0 then
				hits += 1
			end
		end
	end
	return hits
end

-- 必殺技の対象探し -----------------------------------------------------------

export type Target = { kind: string, model: Model, player: Player? }

-- 突進の帯（前方 range、幅 width）に入る敵と、対人で効く相手
function CombatService.targetsInDash(player: Player, range: number, width: number): { Target }
	local root = rootOf(player)
	if not root then
		return {}
	end
	local cf = root.CFrame
	local result: { Target } = {}

	local function consider(model: Model): boolean
		local offset = cf:PointToObjectSpace(positionOf(model))
		-- PointToObjectSpace では前方が -Z
		return CombatLogic.inDashArea(-offset.Z, offset.X, range, width)
	end

	for model, enemy in enemies do
		if enemy.alive and consider(model) then
			table.insert(result, { kind = "enemy", model = model, player = nil })
		end
	end
	for _, other in Players:GetPlayers() do
		local character = other.Character
		if other ~= player and character and BattleStateService.canAffectPlayer(player, other) and consider(character) then
			table.insert(result, { kind = "player", model = character, player = other })
		end
	end
	return result
end

-- 単体技の対象：対戦相手か今戦っている敵を優先し、いなければ射程内で一番近い敵
function CombatService.singleTarget(player: Player, range: number): Target?
	local root = rootOf(player)
	if not root then
		return nil
	end
	local maxRange = range + Config.Ultimate.TargetRangeTolerance

	local opponent = BattleStateService.getPvpOpponent(player)
	if opponent and opponent.Character and BattleStateService.canAffectPlayer(player, opponent) then
		if (positionOf(opponent.Character) - root.Position).Magnitude <= maxRange then
			return { kind = "player", model = opponent.Character, player = opponent }
		end
	end

	local current = BattleStateService.getPveTarget(player)
	if current and enemies[current] and enemies[current].alive then
		if (positionOf(current) - root.Position).Magnitude <= maxRange then
			return { kind = "enemy", model = current, player = nil }
		end
	end

	local best: Target? = nil
	local bestDistance = maxRange
	for model, enemy in enemies do
		if enemy.alive then
			local d = (positionOf(model) - root.Position).Magnitude
			if d <= bestDistance then
				best = { kind = "enemy", model = model, player = nil }
				bestDistance = d
			end
		end
	end
	return best
end

-- クライアントに見せる状態 -------------------------------------------------------

function CombatService.view(player: Player): any
	local state = stateOf(player)
	return {
		guarding = state.guarding,
		stunnedUntil = stunnedUntil[player] or 0, -- workspace:GetServerTimeNow() の時刻
		dashReadyAt = state.dashReadyAt,
		comboStep = state.comboStep or 0,
		comboHits = #Config.Combat.ComboDamage,
		shield = CombatService.shieldOf(player),
	}
end

-- キャラクター ------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.MaxHealth = Config.Combat.MaxHealth
	humanoid.Health = Config.Combat.MaxHealth
	playerStates[player] = nil
	stunnedUntil[player] = nil
	CombatService.refreshSpeed(player)
	notifyState(player)
	humanoid.Died:Connect(function()
		-- 倒れたら付与・シールド・ガード・戦闘状態をすべてなくす
		GrantService.clear(player)
		shields[player] = nil
		playerStates[player] = nil
		BattleStateService.endAll(player)
	end)
end

function CombatService.init()
	local function onPlayerAdded(player: Player)
		player.CharacterAdded:Connect(function(character)
			onCharacterAdded(player, character)
		end)
		if player.Character then
			task.spawn(onCharacterAdded, player, player.Character)
		end
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerRemoving:Connect(function(player)
		playerStates[player] = nil
		stunnedUntil[player] = nil
		shields[player] = nil
	end)
end

return CombatService
