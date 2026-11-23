--!strict
-- パズルピース 9 個（3×3）。grid は左上から右へ 1〜9。
-- route と source：
--   explore = 探索の隠し場所 ID（AreaDefs の exploreSpots）
--   drop    = 通常モンスター ID（Config.Drops.NormalPieceChance で落とす）
--   quest   = クエスト ID
--   boss    = ボスモンスター ID（bossKill 回目の撃破で確定）
-- 名称は仮。完成絵が決まったら差し替える。

return {
	p01 = { id = "p01", grid = 1, nameJa = "ピース 1", nameEn = "Piece 1", route = "explore", source = "e01" },
	p02 = { id = "p02", grid = 2, nameJa = "ピース 2", nameEn = "Piece 2", route = "explore", source = "e02" },
	p03 = { id = "p03", grid = 3, nameJa = "ピース 3", nameEn = "Piece 3", route = "drop", source = "moripon" },
	p04 = { id = "p04", grid = 4, nameJa = "ピース 4", nameEn = "Piece 4", route = "drop", source = "sandhorn" },
	p05 = { id = "p05", grid = 5, nameJa = "ピース 5", nameEn = "Piece 5", route = "quest", source = "q01" },
	p06 = { id = "p06", grid = 6, nameJa = "ピース 6", nameEn = "Piece 6", route = "quest", source = "q02" },
	p07 = { id = "p07", grid = 7, nameJa = "ピース 7", nameEn = "Piece 7", route = "quest", source = "q03" },
	p08 = { id = "p08", grid = 8, nameJa = "ピース 8", nameEn = "Piece 8", route = "boss", source = "oonushi", bossKill = 1 },
	p09 = { id = "p09", grid = 9, nameJa = "ピース 9", nameEn = "Piece 9", route = "boss", source = "oonushi", bossKill = 2 },
} :: { [string]: any }
