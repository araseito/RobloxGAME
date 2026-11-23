-- Lune で実行する単体テスト： lune run tests/run
-- 対象：src/shared/Logic（純粋ロジック）と定義データの整合性

local ProfileSchema = require("../src/shared/Logic/ProfileSchema")
local SessionLock = require("../src/shared/Logic/SessionLock")
local InventoryLogic = require("../src/shared/Logic/InventoryLogic")

local Config = require("../src/shared/Config")
local AbilityDefs = require("../src/shared/AbilityDefs")
local UltimateDefs = require("../src/shared/UltimateDefs")
local PieceDefs = require("../src/shared/PieceDefs")
local MonsterDefs = require("../src/shared/MonsterDefs")
local ItemDefs = require("../src/shared/ItemDefs")
local RecipeDefs = require("../src/shared/RecipeDefs")
local AreaDefs = require("../src/shared/AreaDefs")
local QuestDefs = require("../src/shared/QuestDefs")

local passed, failed = 0, 0

local function test(name: string, fn: () -> ())
	local ok, err = pcall(fn)
	if ok then
		passed += 1
	else
		failed += 1
		print("FAIL  " .. name .. "\n      " .. tostring(err))
	end
end

local function eq(actual: any, expected: any, label: string?)
	if actual ~= expected then
		error(("%s: expected %s, got %s"):format(label or "eq", tostring(expected), tostring(actual)), 2)
	end
end

local LIMIT = Config.Inventory.CategoryLimit
local MAX = Config.Inventory.MaxAmountPerChange

-- ProfileSchema ------------------------------------------------------------

test("reconcile(nil) は初期データを返す", function()
	local p = ProfileSchema.reconcile(nil, 100)
	eq(p.schema, ProfileSchema.VERSION)
	eq(p.createdAt, 100)
	eq(p.areas.town, true)
	eq(type(p.pieces.placed), "table")
	eq(p.onboarding.step, 0)
end)

test("reconcile は既存の値を残し、足りないキーを補う", function()
	local stored = { items = { leaf = 3 }, pieces = { placed = { p01 = true } }, bossKills = 1 }
	local p = ProfileSchema.reconcile(stored, 100)
	eq(p.items.leaf, 3)
	eq(p.pieces.placed.p01, true)
	eq(type(p.pieces.unplaced), "table", "unplaced が補われる")
	eq(p.bossKills, 1)
	eq(p.areas.satoyama, true)
	eq(stored.pieces.unplaced, nil, "元のテーブルは書き換えない")
end)

test("reconcile は型の食い違いを直す", function()
	local p = ProfileSchema.reconcile({ items = "broken", bossKills = "x" }, 100)
	eq(type(p.items), "table")
	eq(p.bossKills, 0)
end)

test("clientView に lock と createdAt は含まれない", function()
	local p = ProfileSchema.default(1)
	p.lock = { jobId = "a", at = 1 }
	local v = ProfileSchema.clientView(p)
	eq(v.lock, nil)
	eq(v.createdAt, nil)
	eq(type(v.pieces), "table")
end)

test("clientView はコピー（書き換えても元に影響しない）", function()
	local p = ProfileSchema.default(1)
	local v = ProfileSchema.clientView(p)
	v.items.leaf = 99
	eq(p.items.leaf, nil)
end)

test("clientSection は非公開セクションを拒否する", function()
	local ok = pcall(ProfileSchema.clientSection, ProfileSchema.default(1), "lock")
	eq(ok, false)
end)

-- SessionLock --------------------------------------------------------------

test("ロックの状態判定", function()
	eq(SessionLock.state(nil, "A", 1000, 180), "free")
	eq(SessionLock.state({ jobId = "A", at = 0 }, "A", 1000, 180), "ours")
	eq(SessionLock.state({ jobId = "B", at = 900 }, "A", 1000, 180), "locked")
	eq(SessionLock.state({ jobId = "B", at = 820 }, "A", 1000, 180), "expired")
	eq(SessionLock.state({ jobId = 5 }, "A", 1000, 180), "free")
	eq(SessionLock.canAcquire("locked"), false)
	eq(SessionLock.canAcquire("expired"), true)
end)

-- InventoryLogic -----------------------------------------------------------

test("付与できる", function()
	local ok, r = InventoryLogic.applyItems({}, { grant = { leaf = 2 } }, ItemDefs, LIMIT, MAX)
	eq(ok, true)
	eq(r.leaf, 2)
end)

test("足りなければ消費できず、元は変わらない", function()
	local items = { leaf = 1 }
	local ok, reason = InventoryLogic.applyItems(items, { consume = { leaf = 2 } }, ItemDefs, LIMIT, MAX)
	eq(ok, false)
	eq(reason, "insufficient")
	eq(items.leaf, 1)
end)

test("消費と付与は同時に成り立つ（合成の形）", function()
	local items = { fang = 2, leaf = 1 }
	local ok, r = InventoryLogic.applyItems(
		items,
		{ consume = { fang = 2, leaf = 1 }, grant = { wooden_blade = 1 } },
		ItemDefs, LIMIT, MAX
	)
	eq(ok, true)
	eq(r.fang, nil, "0 になったキーは消える")
	eq(r.leaf, nil)
	eq(r.wooden_blade, 1)
	eq(items.fang, 2, "元は変わらない")
end)

test("一部だけ足りないときは全部取りやめ", function()
	local ok = InventoryLogic.applyItems(
		{ fang = 2 },
		{ consume = { fang = 2, leaf = 1 }, grant = { wooden_blade = 1 } },
		ItemDefs, LIMIT, MAX
	)
	eq(ok, false)
end)

test("不正な値を拒否する", function()
	local cases = {
		{ grant = { leaf = 0 } },
		{ grant = { leaf = -1 } },
		{ grant = { leaf = 1.5 } },
		{ grant = { leaf = 0 / 0 } },
		{ grant = { leaf = math.huge } },
		{ grant = { leaf = "3" } },
		{ grant = { leaf = MAX + 1 } },
		{ grant = { not_an_item = 1 } },
		{ grant = "x" },
	}
	for i, change in cases do
		local ok = InventoryLogic.applyItems({}, change :: any, ItemDefs, LIMIT, MAX)
		eq(ok, false, "case " .. i)
	end
end)

test("種別の上限を超えて増やせない", function()
	local ok, reason = InventoryLogic.applyItems({ leaf = 19 }, { grant = { fang = 2 } }, ItemDefs, LIMIT, MAX)
	eq(ok, false)
	eq(reason, "category_full")
	-- 別の種別なら増やせる
	local ok2 = InventoryLogic.applyItems({ leaf = 20 }, { grant = { potion = 1 } }, ItemDefs, LIMIT, MAX)
	eq(ok2, true)
end)

test("上限を超えている状態でも消費はできる", function()
	local ok = InventoryLogic.applyItems({ leaf = 25 }, { consume = { leaf = 2 } }, ItemDefs, LIMIT, MAX)
	eq(ok, true)
end)

test("未装着ピースの追加と削除", function()
	local pieces = { placed = {}, unplaced = {} }
	local ok, r = InventoryLogic.addUnplacedPiece(pieces, "p01", PieceDefs, 20)
	eq(ok, true)
	eq(r.unplaced.p01, 1)
	eq(pieces.unplaced.p01, nil, "元は変わらない")
	ok, r = InventoryLogic.addUnplacedPiece(r, "p01", PieceDefs, 20)
	eq(r.unplaced.p01, 2, "重複を持てる")
	ok, r = InventoryLogic.removeUnplacedPiece(r, "p01")
	eq(r.unplaced.p01, 1)
	ok, r = InventoryLogic.removeUnplacedPiece(r, "p01")
	eq(r.unplaced.p01, nil)
	local ok2, reason = InventoryLogic.removeUnplacedPiece(r, "p01")
	eq(ok2, false)
	eq(reason, "insufficient")
	eq((InventoryLogic.addUnplacedPiece(pieces, "p99", PieceDefs, 20)), false, "未定義のピース")
end)

test("未装着ピースの上限", function()
	local ok, reason = InventoryLogic.addUnplacedPiece({ placed = {}, unplaced = { p01 = 20 } }, "p02", PieceDefs, 20)
	eq(ok, false)
	eq(reason, "pieces_full")
end)

-- 定義データの整合性 --------------------------------------------------------

local function count(t: any): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

test("件数が v2 のスコープどおり", function()
	eq(count(PieceDefs), 9, "ピース")
	eq(count(AbilityDefs), 3, "能力")
	eq(count(UltimateDefs), 3, "必殺技")
	eq(count(MonsterDefs), 4, "モンスター")
	eq(count(RecipeDefs), 3, "レシピ")
	eq(count(AreaDefs), 3, "エリア")
	eq(count(QuestDefs), 3, "クエスト")
end)

test("ID とキーが一致し、日英の名前がある", function()
	for _, defs in { AbilityDefs, UltimateDefs, PieceDefs, MonsterDefs, ItemDefs, AreaDefs, QuestDefs } do
		for key, def in defs do
			eq(def.id, key, "id " .. key)
			assert(type(def.nameJa) == "string" and def.nameJa ~= "", "nameJa " .. key)
			assert(type(def.nameEn) == "string" and def.nameEn ~= "", "nameEn " .. key)
		end
	end
end)

test("ピースの grid は 1〜9 を 1 つずつ使う", function()
	local seen = {}
	for id, def in PieceDefs do
		assert(def.grid >= 1 and def.grid <= 9, "grid 範囲 " .. id)
		assert(not seen[def.grid], "grid 重複 " .. id)
		seen[def.grid] = true
	end
end)

test("ピースの入手経路が実在するものを指す", function()
	local spots = {}
	for _, area in AreaDefs do
		for _, spot in area.exploreSpots do
			spots[spot] = true
		end
	end
	local routes = {}
	for id, def in PieceDefs do
		routes[def.route] = (routes[def.route] or 0) + 1
		if def.route == "explore" then
			assert(spots[def.source], "探索地点がない " .. id)
		elseif def.route == "drop" then
			local m = MonsterDefs[def.source]
			assert(m and m.role == "normal" and m.pieceDrop == id, "通常ドロップが対応しない " .. id)
		elseif def.route == "quest" then
			local q = QuestDefs[def.source]
			assert(q and q.reward.piece == id, "クエスト報酬が対応しない " .. id)
		elseif def.route == "boss" then
			local m = MonsterDefs[def.source]
			assert(m and m.role == "boss", "ボスでない " .. id)
			assert(type(def.bossKill) == "number", "bossKill がない " .. id)
		else
			error("未知の経路 " .. id)
		end
	end
	eq(routes.explore, 2)
	eq(routes.drop, 2)
	eq(routes.quest, 3)
	eq(routes.boss, 2)
end)

test("能力と必殺技が 1 対 1", function()
	for id, ability in AbilityDefs do
		local ult = UltimateDefs[ability.ultimate]
		assert(ult and ult.ability == id, "必殺技が対応しない " .. id)
	end
end)

test("モンスターの参照先が実在する", function()
	for id, m in MonsterDefs do
		assert(AreaDefs[m.area], "エリアがない " .. id)
		for _, drop in m.drops do
			assert(ItemDefs[drop.item], "ドロップがない " .. id)
		end
		if m.selfGrant then
			assert(AbilityDefs[m.selfGrant], "付与がない " .. id)
		end
	end
	local bosses = 0
	for _, m in MonsterDefs do
		if m.role == "boss" then
			bosses += 1
		end
	end
	eq(bosses, 1, "ボスは 1 体")
end)

test("素材はすべてどこかのモンスターが落とす", function()
	for id, item in ItemDefs do
		if item.category == "material" then
			local found = false
			for _, m in MonsterDefs do
				for _, drop in m.drops do
					if drop.item == id then
						found = true
					end
				end
			end
			assert(found, "入手先のない素材 " .. id)
		end
	end
end)

test("レシピは素材から装備・アイテムを作る（多段合成なし）", function()
	for id, r in RecipeDefs do
		local out = ItemDefs[r.output]
		assert(out and out.category ~= "material", "成果物がおかしい " .. id)
		for input in r.inputs do
			assert(ItemDefs[input] and ItemDefs[input].category == "material", "材料が素材でない " .. id)
		end
	end
end)

test("クエストの参照先が実在する", function()
	for id, q in QuestDefs do
		if q.goal.kind == "kill" then
			assert(MonsterDefs[q.goal.monster], "モンスターがない " .. id)
		elseif q.goal.kind == "craft" then
			assert(RecipeDefs[q.goal.item], "レシピがない " .. id)
		else
			error("未知の目標 " .. id)
		end
		assert(PieceDefs[q.reward.piece], "報酬ピースがない " .. id)
		if q.reward.unlockArea then
			assert(AreaDefs[q.reward.unlockArea], "解放エリアがない " .. id)
		end
	end
	for id, area in AreaDefs do
		if area.unlock then
			assert(QuestDefs[area.unlock.quest], "解放条件のクエストがない " .. id)
		end
	end
end)

test("装備はすべて付与上限 +1 を持つ", function()
	for id, item in ItemDefs do
		if item.category == "weapon" or item.category == "armor" then
			eq(item.capacityBonus, 1, id)
		end
	end
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("テスト失敗")
end
