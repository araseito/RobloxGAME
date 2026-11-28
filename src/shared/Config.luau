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

-- 戦闘の操作（Step 2 改訂：4 段コンボ・ガード・回避ダッシュ）
Config.Combat = {
	MaxHealth = 100,
	BaseWalkSpeed = 16,
	ComboDamage = { 6, 6, 8, 14 }, -- 4 段コンボの各段のダメージ。4 段目が「締め」
	ComboInterval = 0.35, -- 1 段ごとの最短間隔（秒）
	ComboResetSeconds = 1.0, -- この秒数あくと 1 段目に戻る
	BasicRange = 8, -- stud
	RangeTolerance = 4, -- 通信の遅れを見込んで射程に足す余裕（stud）
	IntervalTolerance = 0.05, -- 攻撃間隔の許容誤差（秒）
	FinisherStunSeconds = 0.6, -- 締めで吹き飛んだ相手が動けない秒数
	Knockback = {
		Horizontal = 55, -- プレイヤーを飛ばす速さ（stud/秒）
		Vertical = 20,
		Duration = 0.2, -- 秒
		EnemyDistance = 10, -- 敵を押し出す距離（stud）
	},
	Guard = {
		DamageMultiplier = 0.2, -- 正面からのダメージをこの倍率にする
		WalkSpeedMultiplier = 0.4, -- ガード中の移動速度
		BreakStunSeconds = 1.5, -- ガードを割られたときに動けない秒数
	},
	Dash = {
		Cooldown = 3, -- 秒
		GaleCooldownMultiplier = 0.5, -- 疾風付与中はクールダウンがこの倍率
		Speed = 70, -- stud/秒
		Duration = 0.18, -- 秒
	},
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
	-- 攻撃（自分を攻撃したプレイヤーにだけ反撃する）
	AttackInterval = 4, -- 秒
	TelegraphSeconds = 0.8, -- 赤く光る予備動作の秒数。この間に締めで吹き飛ばすと攻撃を止められる
	AttackDamage = 15,
	AttackRange = 10, -- stud
	ReturnDistance = 25, -- 元の位置からこれ以上押し出されたら戻る
	-- Workspace に DummySpawn という Part がなければここに置く（x, y, z）。
	-- Config は Lune のテストでも読むので Vector3 などの Roblox の型は使わない（ERROR_LOG #2）
	DefaultPosition = { 0, 3, -20 },
}

Config.Ring = {
	CountdownSeconds = 5,
	MatchSeconds = 90,
	LoserCooldown = 10,
	RematchWindowSeconds = 600, -- 負けてからこの秒数以内の再参加を「再戦」と数える
	-- 置き場所：Workspace に「DuelRing」という Part があればその上面の中心。なければスポーン地点から SpawnOffset
	SpawnOffset = { 0, 0, 30 }, -- 町の広場の中央の仮の位置（x, y, z）
	Radius = 16, -- リングの半径（stud）。中心からこれより外に出たら負け
	FallDepth = 4, -- 床よりこれ以上下に落ちたら負け（stud）
	PadOffset = 11, -- 台の中心から台までの距離（stud）
	PadRadius = 3, -- 台の半径（stud）
	PadMaxHeight = 7, -- 台の上に「立っている」とみなす高さ（stud）
	TickInterval = 0.2, -- 台と決着を確かめる間隔（秒）
	NoticeSeconds = 4, -- 乗れない理由を同じ人に知らせ直すまでの秒数
}

Config.Drops = {
	NormalPieceChance = 0.05,
	BossContributionRatio = 0.1, -- ボスの最大 HP のこの割合以上を与えた人全員がドロップをもらう
}

-- モンスター（Step 5）。数値はすべて仮置き
Config.Monsters = {
	TickInterval = 0.1, -- 動きと攻撃を決める間隔（秒）
	AggroRange = 40, -- この距離に入ったプレイヤーを狙う（同じエリアにいる人だけ）
	LeashRange = 70, -- 出現点からこれ以上離れたら、狙いをやめて戻る
	WindupSeconds = 0.45, -- 攻撃の予備動作（光る）
	ProjectileSeconds = 0.35, -- 砂の弾が飛ぶ時間
	ProjectileHitRadius = 4, -- 狙った地点からこの距離にいれば弾が当たる（ダッシュで避けられる）
	RespawnSeconds = 8,
	BossRespawnSeconds = 30,
	RegrantSeconds = 10, -- 自分への付与を剥がされてから、かけ直すまでの秒数
	Boss = {
		BigAttackBelow = 0.5, -- HP の割合がこれを下回ると大技を混ぜる
		BigAttackEvery = 3, -- 何回に 1 回が大技か
		BigDamageMultiplier = 2,
		BigRangeMultiplier = 1.6,
		BigWindupSeconds = 1.2,
	},
	-- 出現点：Workspace.MonsterSpawns の下にモンスター ID と同じ名前の Part があればその位置。
	-- なければエリアの到着地点から offset の位置（x, y, z）。spread の範囲に count 体を散らす
	Spawns = {
		{ monster = "moripon", area = "satoyama", offset = { 35, 0, -45 }, count = 4, spread = 10 },
		{ monster = "aohane", area = "satoyama", offset = { -40, 0, -55 }, count = 2, spread = 12 },
		{ monster = "sandhorn", area = "dungeon", offset = { 0, 0, -50 }, count = 3, spread = 14 },
		{ monster = "oonushi", area = "dungeon", offset = { 0, 0, -105 }, count = 1, spread = 0 },
	},
	-- 見た目の仮置き（size は x, y, z、color は RGB、hover は地面から浮く高さ）
	Looks = {
		moripon = { size = { 3, 3, 3 }, color = { 110, 170, 80 }, hover = 0 },
		aohane = { size = { 3, 1.5, 3 }, color = { 80, 140, 230 }, hover = 7 },
		sandhorn = { size = { 3.5, 2.5, 6 }, color = { 205, 170, 110 }, hover = 0 },
		oonushi = { size = { 10, 9, 10 }, color = { 110, 75, 55 }, hover = 0 },
	} :: { [string]: { size: { number }, color: { number }, hover: number } },
}

Config.Badge = {
	CompletionBadgeId = 0, -- TODO: ダイスケさんが作成した Badge ID に差し替える（0 のあいだは渡さない）
}

-- 探索ピース（Step 3）。置き場所：Workspace に「ExploreSpot_<隠し場所 ID>」という Part があればその上。
-- なければ町の e01 だけ、スポーン地点から SpawnOffset の位置（最初の 60 秒で必ず目の前に出すため）
Config.Explore = {
	PromptDistance = 10, -- 拾うボタンが出る距離（stud）
	PickupTolerance = 6, -- サーバーでの距離確認に足す余裕（stud）
	SpawnOffset = { 0, 1.5, -8 }, -- スポーン地点から見た e01 の位置（x, y, z。-z が正面）
	-- 町以外の隠し場所は、印がなければそのエリアの到着地点から見たこの位置（固定の隠し場所。仮置き）
	AreaOffsets = {
		e02 = { -95, 1.5, 85 },
	} :: { [string]: { number } },
}

-- エリアと移動（Step 5）。到着地点：Workspace.Spawns の下に AreaDefs の spawnPart という Part があればその上。
-- なければ町はスポーン地点、それ以外はスポーン地点から PlaceholderOffsets の位置に仮の足場を作る（地形は Studio 側で作る）
Config.Travel = {
	PlaceholderOffsets = {
		satoyama = { 0, 0, 700 },
		dungeon = { 700, 0, 0 },
	} :: { [string]: { number } },
	PlaceholderSize = 260, -- 仮の足場の一辺（stud）
	Cooldown = 2, -- 続けて移動できるまでの秒数
}

-- 町の掲示板（Step 3）。置き場所：Workspace に「QuestBoard」という Part があればそこ。
-- なければスポーン地点から SpawnOffset の位置
Config.QuestBoard = {
	PromptDistance = 12,
	SpawnOffset = { 12, 0, -6 },
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
