--!strict
-- 町の掲示板のクエスト 3 本。達成すると自動で報酬。
-- goal.kind: kill（monster を count 体倒す）/ craft（item を count 個合成する）

return {
	q01 = {
		id = "q01",
		order = 1,
		nameJa = "モリポン退治",
		nameEn = "Moripon Patrol",
		goal = { kind = "kill", monster = "moripon", count = 3 },
		reward = { piece = "p05", unlockArea = "dungeon" },
	},
	q02 = {
		id = "q02",
		order = 2,
		nameJa = "旅支度",
		nameEn = "Ready to Travel",
		goal = { kind = "craft", item = "travel_coat", count = 1 },
		reward = { piece = "p06" },
	},
	q03 = {
		id = "q03",
		order = 3,
		nameJa = "砂の角を追え",
		nameEn = "Horns in the Sand",
		goal = { kind = "kill", monster = "sandhorn", count = 3 },
		reward = { piece = "p07" },
	},
} :: { [string]: any }
