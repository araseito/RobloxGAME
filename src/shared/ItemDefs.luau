--!strict
-- カード（素材・武器・防具・アイテム）。名称は仮。
-- category: material / weapon / armor / consumable（Config.Inventory.CategoryLimit と対応）
-- 素材の入手先は MonsterDefs の drops から求める（ここに重複して書かない）

return {
	-- 素材
	leaf = { id = "leaf", category = "material", nameJa = "葉", nameEn = "Leaf" },
	fang = { id = "fang", category = "material", nameJa = "牙", nameEn = "Fang" },
	feather = { id = "feather", category = "material", nameJa = "羽", nameEn = "Feather" },

	-- 装備（付与上限 +1）
	wooden_blade = {
		id = "wooden_blade",
		category = "weapon",
		nameJa = "木刀",
		nameEn = "Wooden Blade",
		stat = "attack",
		amount = 0.05,
		capacityBonus = 1,
	},
	travel_coat = {
		id = "travel_coat",
		category = "armor",
		nameJa = "旅の外套",
		nameEn = "Traveler's Coat",
		stat = "damageTaken",
		amount = -0.05,
		capacityBonus = 1,
	},

	-- アイテム
	potion = {
		id = "potion",
		category = "consumable",
		nameJa = "回復薬",
		nameEn = "Potion",
		healRatio = 0.30,
		combatOnly = true,
		ringAllowed = false,
	},
} :: { [string]: any }
