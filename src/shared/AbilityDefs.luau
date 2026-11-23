--!strict
-- 能力 3 種（すべて付与型）。名称はすべて仮称・自作。
-- stat: moveSpeed / attack / damageTaken。amount は倍率の増減（0.30 = +30%）

return {
	gale = {
		id = "gale",
		order = 1,
		nameJa = "疾風付与",
		nameEn = "Gale Grant",
		cost = 3,
		stat = "moveSpeed",
		amount = 0.30,
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
		ultimate = "bulwark_ult",
	},
} :: { [string]: any }
