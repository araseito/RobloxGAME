--!strict
-- モンスター 4 体（通常 3 ＋ボス 1）。名前・姿はすべて自作。数値は仮。
-- drops: 撃破時に必ず判定する素材（chance は 0〜1）
-- pieceDrop: 低確率で落とすピース（Config.Drops.NormalPieceChance）
-- bossPieces: ボスの n 回目の撃破で確定で落とすピースは PieceDefs の bossKill で決まる
-- selfGrant: 戦闘中に自分へかける付与（AbilityDefs の ID）。プレイヤーは剥がす練習ができる

return {
	moripon = {
		id = "moripon",
		nameJa = "モリポン",
		nameEn = "Moripon",
		descJa = "葉をまとった小さなけもの。群れで現れる",
		area = "satoyama",
		role = "normal",
		maxHealth = 60,
		damage = 6,
		attackRange = 6,
		attackInterval = 1.5,
		moveSpeed = 12,
		drops = { { item = "leaf", chance = 1.0, min = 1, max = 2 } },
		pieceDrop = "p03",
	},
	aohane = {
		id = "aohane",
		nameJa = "アオハネ",
		nameEn = "Aohane",
		descJa = "里山の空を飛ぶ青い小鳥。急降下してくる",
		area = "satoyama",
		role = "normal",
		maxHealth = 45,
		damage = 8,
		attackRange = 6,
		attackInterval = 2.0,
		moveSpeed = 18,
		selfGrant = "gale",
		drops = { { item = "feather", chance = 1.0, min = 1, max = 2 } },
	},
	sandhorn = {
		id = "sandhorn",
		nameJa = "サンドホーン",
		nameEn = "Sandhorn",
		descJa = "角のある砂色のトカゲ。離れたところから砂の弾を撃つ",
		area = "dungeon",
		role = "normal",
		maxHealth = 80,
		damage = 10,
		attackRange = 40,
		attackInterval = 2.5,
		moveSpeed = 10,
		drops = { { item = "fang", chance = 1.0, min = 1, max = 2 } },
		pieceDrop = "p04",
	},
	oonushi = {
		id = "oonushi",
		nameJa = "オオヌシ",
		nameEn = "Oonushi",
		descJa = "渓谷の洞の奥に棲む大きな主。体力が減ると大技を放つ",
		area = "dungeon",
		role = "boss",
		maxHealth = 1500,
		damage = 25,
		attackRange = 12,
		attackInterval = 2.5,
		moveSpeed = 8,
		selfGrant = "bulwark",
		drops = {
			{ item = "fang", chance = 1.0, min = 2, max = 3 },
			{ item = "feather", chance = 1.0, min = 1, max = 2 },
		},
	},
} :: { [string]: any }
