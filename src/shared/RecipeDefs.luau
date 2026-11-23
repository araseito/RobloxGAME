--!strict
-- クラフトのレシピ 3 種。工程なしのワンタップ合成。多段合成はしない。

return {
	wooden_blade = {
		id = "wooden_blade",
		order = 1,
		inputs = { fang = 2, leaf = 1 },
		output = "wooden_blade",
		outputCount = 1,
	},
	travel_coat = {
		id = "travel_coat",
		order = 2,
		inputs = { feather = 2, leaf = 1 },
		output = "travel_coat",
		outputCount = 1,
	},
	potion = {
		id = "potion",
		order = 3,
		inputs = { leaf = 2 },
		output = "potion",
		outputCount = 1,
	},
} :: { [string]: any }
