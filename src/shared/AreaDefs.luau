--!strict
-- エリア 3 つ（選択式移動）。地名は仮称・自作、日英二重表記。
-- spawnPart: Studio 側で Workspace.Spawns の下に置く到着地点の Part 名
-- unlock: 解放条件（nil なら最初から解放）
-- safe: 町は決闘リングの中を除いてセーフゾーン

return {
	town = {
		id = "town",
		order = 1,
		nameJa = "ひだまり通り",
		nameEn = "Hidamari Main Street",
		spawnPart = "Spawn_town",
		safe = true,
		exploreSpots = { "e01" },
	},
	satoyama = {
		id = "satoyama",
		order = 2,
		nameJa = "こもれび里山",
		nameEn = "Komorebi Hills",
		spawnPart = "Spawn_satoyama",
		safe = false,
		exploreSpots = { "e02" },
	},
	dungeon = {
		id = "dungeon",
		order = 3,
		nameJa = "赤岩渓谷の洞",
		nameEn = "Red Rock Hollow",
		spawnPart = "Spawn_dungeon",
		safe = false,
		unlock = { quest = "q01" },
		exploreSpots = {},
	},
} :: { [string]: any }
