--!strict
-- 必殺技 3 種（能力と 1 対 1）。名称はすべて仮称・自作。
-- 共通の威力計算・詠唱時間は Config.Ultimate にある。
-- kind:
--   dash   = 前方へ突進する範囲攻撃（range × width の帯）
--   single = 1 体への大ダメージ
--   shield = 自分にシールド（威力分のダメージを吸収）

return {
	gale_ult = {
		id = "gale_ult",
		ability = "gale",
		nameJa = "蒼嵐・天駆け",
		nameEn = "Azure Gale Rush",
		kind = "dash",
		range = 30,
		width = 8,
		stripsAbility = "gale", -- 当たった相手の疾風付与を剥がす
	},
	might_ult = {
		id = "might_ult",
		ability = "might",
		nameJa = "震天・大地割り",
		nameEn = "Skyquake Splitter",
		kind = "single",
		range = 12,
	},
	bulwark_ult = {
		id = "bulwark_ult",
		ability = "bulwark",
		nameJa = "不動・鉄壁聖域",
		nameEn = "Ironwall Sanctum",
		kind = "shield",
		shieldDuration = 8,
	},
} :: { [string]: any }
