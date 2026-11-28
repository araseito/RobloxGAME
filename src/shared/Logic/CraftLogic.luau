--!strict
-- クラフトの計算（PHASE0_PLAN_v2 5.6）。require を使わない（定義データは引数で受け取る）。
-- 合成そのもの（消費と付与を同時に）は InventoryLogic.applyItems が行う。ここは「足りるか」「何が足りないか」だけ。

local CraftLogic = {}

-- 足りない素材 { [itemId] = 足りない数 }。足りていれば空のテーブル
function CraftLogic.missing(items: { [string]: number }, recipe: any): { [string]: number }
	local out = {}
	for itemId, need in recipe.inputs do
		local have = items[itemId] or 0
		if have < need then
			out[itemId] = need - have
		end
	end
	return out
end

function CraftLogic.canCraft(items: { [string]: number }, recipe: any): boolean
	return next(CraftLogic.missing(items, recipe)) == nil
end

-- 合成で渡す増減（InventoryService.applyItems に渡す形）
function CraftLogic.change(recipe: any): any
	return {
		consume = table.clone(recipe.inputs),
		grant = { [recipe.output] = recipe.outputCount },
	}
end

-- 素材の入手先（その素材を落とすモンスターの ID の一覧。ID 順）
function CraftLogic.sources(itemId: string, monsterDefs: any): { string }
	local out = {}
	for monsterId, def in monsterDefs do
		for _, entry in def.drops or {} do
			if entry.item == itemId then
				table.insert(out, monsterId)
				break
			end
		end
	end
	table.sort(out)
	return out
end

return CraftLogic
