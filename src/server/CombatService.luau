--!strict
-- ダメージを受け持つ唯一の窓口。
-- ・敵（木人・モンスター）の HP はここで管理する（Humanoid は使わず、属性でクライアントへ見せる）
-- ・プレイヤーへのダメージは、攻撃者がプレイヤーなら BattleStateService.canAffectPlayer が
--   true のときだけ通す。決闘リングの対戦相手以外には 0（PHASE0_PLAN_v2 の最重要ルール）

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local CombatLogic = require(Shared:WaitForChild("Logic"):WaitForChild("CombatLogic"))

local BattleStateService = require(script.Parent.BattleStateService)
local GrantService = require(script.Parent.GrantService)

export type Enemy = {
	model: Model,
	id: string, -- MonsterDefs の ID、または "dummy"
	maxHealth: number,
	health: number,
	alive: boolean,
	onDeath: ((Model, Player?) -> ())?,
}

local CombatService = {}

CombatService.ENEMY_TAG = "Enemy"

local enemies: { [Model]: Enemy } = {}
local lastBasicAttack: { [Player]: number } = {}
local shields: { [Player]: { amount: number, expiresAt: number } } = {}

local hooks = {
	onDealt = nil :: ((Player, number) -> ())?, -- 攻撃者が与えたダメージ
	onTaken = nil :: ((Player, number) -> ())?, -- プレイヤーが受けたダメージ
	onKill = nil :: ((Player, Enemy) -> ())?, -- プレイヤーが敵を倒した
	onShieldChanged = nil :: ((Player) -> ())?,
}

function CombatService.setHooks(newHooks: any)
	hooks.onDealt = newHooks.onDealt
	hooks.onTaken = newHooks.onTaken
	hooks.onKill = newHooks.onKill
	hooks.onShieldChanged = newHooks.onShieldChanged
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
		syncEnemyAttributes(enemy)
	end
end

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

-- ダメージ -----------------------------------------------------------------

-- プレイヤーが敵にダメージを与える
function CombatService.damageEnemy(attacker: Player, model: Model, base: number): number
	local enemy = enemies[model]
	if not enemy or not enemy.alive then
		return 0
	end
	local amount = CombatLogic.damage(
		base,
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
	end
	syncEnemyAttributes(enemy)
	return amount
end

-- プレイヤーにダメージを与える（唯一の入り口）。
-- attacker がプレイヤーのときは、決闘リングの対戦相手でなければ 0 を返して何もしない。
-- attacker が nil のときは敵からの攻撃（Step 5 のモンスター）。sourceEnemy でどの敵かを渡す
function CombatService.damagePlayer(attacker: Player?, victim: Player, base: number, sourceEnemy: Model?): number
	if attacker ~= nil and not BattleStateService.canAffectPlayer(attacker, victim) then
		return 0 -- 戦闘状態でない相手には一切効かない
	end
	local character = victim.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if not humanoid or humanoid.Health <= 0 then
		return 0
	end

	local attackMultiplier = if attacker then GrantService.multipliers(attacker).attack else 1
	local pvpCap = if attacker then humanoid.MaxHealth * Config.Ultimate.PvpDamageCapRatio else nil
	local amount = CombatLogic.damage(base, attackMultiplier, GrantService.multipliers(victim).damageTaken, pvpCap)

	local shield = shields[victim]
	if shield and shield.expiresAt > os.clock() then
		local remaining, passed = CombatLogic.absorb(shield.amount, amount)
		shield.amount = remaining
		amount = passed
		if remaining <= 0 then
			shields[victim] = nil
		end
		if hooks.onShieldChanged then
			hooks.onShieldChanged(victim)
		end
	end
	if amount <= 0 then
		return 0
	end

	humanoid.Health = math.max(0, humanoid.Health - amount)
	if sourceEnemy then
		BattleStateService.notePve(victim, sourceEnemy)
	end
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
	shields[player] = { amount = amount, expiresAt = os.clock() + duration }
	if hooks.onShieldChanged then
		hooks.onShieldChanged(player)
	end
	task.delay(duration, function()
		local shield = shields[player]
		if shield and shield.expiresAt <= os.clock() then
			shields[player] = nil
			if hooks.onShieldChanged then
				hooks.onShieldChanged(player)
			end
		end
	end)
end

function CombatService.shieldOf(player: Player): number
	local shield = shields[player]
	if shield and shield.expiresAt > os.clock() then
		return shield.amount
	end
	return 0
end

-- 通常攻撃 ---------------------------------------------------------------

-- 戻り値：結果コード（"hit" / "not_in_battle" / それ以外は失敗理由）
function CombatService.basicAttack(player: Player, target: any): string
	if typeof(target) ~= "Instance" or not target:IsA("Model") then
		return "bad_target"
	end
	local root = rootOf(player)
	if not root then
		return "dead"
	end

	local now = os.clock()
	local last = lastBasicAttack[player]
	if last and now - last < Config.Combat.BasicInterval - Config.Combat.IntervalTolerance then
		return "too_fast"
	end

	local model = target :: Model
	local maxRange = Config.Combat.BasicRange + Config.Combat.RangeTolerance
	if (positionOf(model) - root.Position).Magnitude > maxRange then
		return "out_of_range"
	end

	local enemy = enemies[model]
	if enemy then
		if not enemy.alive then
			return "dead_target"
		end
		lastBasicAttack[player] = now
		CombatService.damageEnemy(player, model, Config.Combat.BasicDamage)
		return "hit"
	end

	local victim = Players:GetPlayerFromCharacter(model)
	if victim then
		lastBasicAttack[player] = now
		local dealt = CombatService.damagePlayer(player, victim, Config.Combat.BasicDamage, nil)
		return if dealt > 0 then "hit" else "not_in_battle"
	end

	return "bad_target"
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

-- 単体技の対象：今戦っている敵か対戦相手を優先し、いなければ射程内で一番近い相手
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

-- キャラクター ------------------------------------------------------------

local function onCharacterAdded(player: Player, character: Model)
	local humanoid = character:WaitForChild("Humanoid", 10)
	if not humanoid or not humanoid:IsA("Humanoid") then
		return
	end
	humanoid.MaxHealth = Config.Combat.MaxHealth
	humanoid.Health = Config.Combat.MaxHealth
	GrantService.refreshEffects(player)
	humanoid.Died:Connect(function()
		-- 倒れたら付与・シールド・戦闘状態をすべてなくす
		GrantService.clear(player)
		shields[player] = nil
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
		lastBasicAttack[player] = nil
		shields[player] = nil
	end)
end

return CombatService
