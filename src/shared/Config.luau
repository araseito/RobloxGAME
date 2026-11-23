--!strict
-- すべての数値はここに集約する。値はすべて仮置き（Phase 0 のプレイテストで調整）。

local Config = {}

Config.Data = {
	StoreName = "PlayerData_v1",
	KeyPrefix = "u_",
	AutosaveInterval = 60, -- 秒
	LockTimeout = 180, -- 秒。これより古い他サーバーのロックは期限切れとして奪う
	LoadRetryInterval = 5, -- 秒
	LoadMaxAttempts = 8,
	ProfileWaitTimeout = 15, -- GetSnapshot がプロフィール読み込みを待つ最大秒数
}

Config.Inventory = {
	-- 種別ごとの合計枚数の上限（設計図「種別ごとに上限 20」）
	CategoryLimit = {
		material = 20,
		weapon = 20,
		armor = 20,
		consumable = 20,
	} :: { [string]: number },
	UnplacedPieceLimit = 20, -- 未装着ピースの合計枚数（重複を含む）
	MaxAmountPerChange = 1000, -- 1 回の増減で扱える最大数（異常値対策）
}

Config.Grant = {
	BaseCapacity = 10, -- 付与上限。装備の capacityBonus が加算される
	ReleaseCooldown = 5, -- 解除した能力を付け直せない秒数
	StripRange = 30, -- 剥がしが届く距離（stud）
}

Config.Ultimate = {
	GaugeMax = 100,
	PerDamageDealt = 0.1, -- 与ダメ 10 ごとに +1
	PerDamageTaken = 0.1, -- 被ダメ 10 ごとに +1
	OnGrant = 8,
	OnRelease = 5,
	OnStrip = 12,
	OnMonsterKill = 15,
	BasePower = 30,
	PowerPerCost = 8, -- 威力 = BasePower + 消費コスト合計 × PowerPerCost
	CastTime = 1.2, -- 秒（技名表示とカットイン）
	PvpDamageCapRatio = 0.35, -- 対人ダメージ上限（最大 HP 比）
	DefaultUltimate = "might_ult", -- 付与が 1 つもないときに出る技（仮置き）
	TargetRangeTolerance = 4, -- 必殺技の射程に足す余裕（stud）
}

Config.Combat = {
	MaxHealth = 100,
	BaseWalkSpeed = 16,
	BasicDamage = 10,
	BasicInterval = 0.6,
	BasicRange = 8, -- stud
	RangeTolerance = 4, -- 通信の遅れを見込んで射程に足す余裕（stud）
	IntervalTolerance = 0.05, -- 攻撃間隔の許容誤差（秒）
	PveCombatTimeout = 15, -- この秒数攻撃しなければ PvE 戦闘終了
	BattleTickInterval = 0.5, -- 戦闘状態の期限切れを確かめる間隔（秒）
	MinDamageTakenMultiplier = 0.1, -- 被ダメージ倍率の下限
}

-- 練習用の木人（Step 2。モンスター実装前の練習相手）
Config.Dummy = {
	MaxHealth = 300,
	RespawnSeconds = 3,
	SelfGrant = "bulwark", -- 剥がす練習用に自分へかける付与
	RegrantSeconds = 10, -- 剥がされてからかけ直すまでの秒数
	-- Workspace に DummySpawn という Part がなければここに置く（x, y, z）。
	-- Config は Lune のテストでも読むので Vector3 などの Roblox の型は使わない（ERROR_LOG #2）
	DefaultPosition = { 0, 3, -20 },
}

Config.Ring = {
	CountdownSeconds = 5,
	MatchSeconds = 90,
	LoserCooldown = 10,
	RematchWindowSeconds = 600, -- 負けてからこの秒数以内の再参加を「再戦」と数える
}

Config.Drops = {
	NormalPieceChance = 0.05,
}

Config.Badge = {
	CompletionBadgeId = 0, -- TODO: ダイスケさんが作成した Badge ID に差し替える（Step 3）
}

Config.Titles = {
	first_picture = { nameJa = "最初の一枚", nameEn = "First Picture" },
}

-- Remote ごとのレート制限（トークンバケット）。Rate = 1 秒あたりの補充数、Burst = 最大保持数
Config.RateLimit = {
	Default = { Rate = 8, Burst = 16 },
	GetSnapshot = { Rate = 1, Burst = 5 },
	Attack = { Rate = 4, Burst = 6 },
} :: { [string]: { Rate: number, Burst: number } }

return Config
