--!strict
-- 能力 3 種（すべて付与型）。名称はすべて仮称・自作。
-- stat: moveSpeed / attack / damageTaken。amount は倍率の増減（0.30 = +30%）
-- perk: 数字だけでなく「できること」を変える効果（Step 2 改訂。剥がす意味をはっきりさせる）
--   dash_fast    回避ダッシュのクールダウンが短くなる
--   guard_break  4 段コンボの締めで相手のガードを割れる
--   no_knockback 吹き飛ばされない（締めでも、必殺技でも）

return {
	gale = {
		id = "gale",
		order = 1,
		nameJa = "疾風付与",
		nameEn = "Gale Grant",
		cost = 3,
		stat = "moveSpeed",
		amount = 0.30,
		perk = "dash_fast",
		perkJa = "移動 +30%・ダッシュのクールダウン半分",
		ultimate = "gale_ult",
	},
	might = {
		id = "might",
		order = 2,
		nameJa = "剛力付与",
		nameEn = "Might Grant",
		cost = 4,
		stat = "attack",
		amount = 0.25,
		perk = "guard_break",
		perkJa = "攻撃 +25%・締めでガードを割る",
		ultimate = "might_ult",
	},
	bulwark = {
		id = "bulwark",
		order = 3,
		nameJa = "鉄壁付与",
		nameEn = "Bulwark Grant",
		cost = 4,
		stat = "damageTaken",
		amount = -0.25,
		perk = "no_knockback",
		perkJa = "被ダメージ −25%・吹き飛ばされない",
		ultimate = "bulwark_ult",
	},
} :: { [string]: any }
