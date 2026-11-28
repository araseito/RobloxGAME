-- Lune で実行する単体テスト： lune run tests/run
-- 対象：src/shared/Logic（純粋ロジック）と定義データの整合性

local ProfileSchema = require("../src/shared/Logic/ProfileSchema")
local SessionLock = require("../src/shared/Logic/SessionLock")
local InventoryLogic = require("../src/shared/Logic/InventoryLogic")
local PuzzleLogic = require("../src/shared/Logic/PuzzleLogic")
local QuestLogic = require("../src/shared/Logic/QuestLogic")
local DuelLogic = require("../src/shared/Logic/DuelLogic")
local DropLogic = require("../src/shared/Logic/DropLogic")

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

-- PuzzleLogic（Step 3） -----------------------------------------------------

test("はめると未装着から 1 枚減り、はまったものに入る", function()
	local pieces = { placed = {}, unplaced = { p01 = 2 } }
	local ok, result = PuzzleLogic.place(pieces, "p01", PieceDefs)
	eq(ok, true)
	eq(result.placed.p01, true)
	eq(result.unplaced.p01, 1, "重複した分は未装着に残る")
	eq(pieces.placed.p01, nil, "元のテーブルは書き換えない")
	eq(pieces.unplaced.p01, 2)
end)

test("最後の 1 枚をはめると未装着から消える", function()
	local _, result = PuzzleLogic.place({ placed = {}, unplaced = { p05 = 1 } }, "p05", PieceDefs)
	eq(result.unplaced.p05, nil)
end)

test("はめられないとき：持っていない・もうはまっている・未定義・型違い", function()
	local ok, reason = PuzzleLogic.place({ placed = {}, unplaced = {} }, "p01", PieceDefs)
	eq(ok, false)
	eq(reason, "piece_not_owned")
	ok, reason = PuzzleLogic.place({ placed = { p01 = true }, unplaced = { p01 = 1 } }, "p01", PieceDefs)
	eq(ok, false)
	eq(reason, "already_placed", "重複ははめられない")
	ok, reason = PuzzleLogic.place({ placed = {}, unplaced = { p99 = 1 } }, "p99", PieceDefs)
	eq(reason, "unknown_id")
	ok, reason = PuzzleLogic.place({ placed = {}, unplaced = {} }, 5, PieceDefs)
	eq(reason, "unknown_id")
end)

test("完成の判定と数", function()
	local placed = {}
	for id in PieceDefs do
		eq(PuzzleLogic.isComplete(placed, PieceDefs), false)
		placed[id] = true
	end
	eq(PuzzleLogic.isComplete(placed, PieceDefs), true)
	eq(PuzzleLogic.placedCount(placed, PieceDefs), 9)
	placed.p99 = true
	eq(PuzzleLogic.placedCount(placed, PieceDefs), 9, "未定義の ID は数えない")
end)

test("次にはめられるピースは grid の小さい順で、はまっているものは飛ばす", function()
	eq(PuzzleLogic.nextPlaceable({ placed = {}, unplaced = {} }, PieceDefs), nil)
	eq(PuzzleLogic.nextPlaceable({ placed = {}, unplaced = { p07 = 1, p03 = 1 } }, PieceDefs), "p03")
	eq(PuzzleLogic.nextPlaceable({ placed = { p03 = true }, unplaced = { p07 = 1, p03 = 1 } }, PieceDefs), "p07")
	eq(PuzzleLogic.nextPlaceable({ placed = { p03 = true }, unplaced = { p03 = 2 } }, PieceDefs), nil, "重複だけなら nil")
end)

-- QuestLogic（Step 3） ------------------------------------------------------

test("倒した数を数え、目標で止まる", function()
	local quests = {}
	local changed
	for _ = 1, 5 do
		quests, changed = QuestLogic.record(quests, QuestDefs, { kind = "kill", monster = "moripon" })
	end
	eq(quests.q01.progress, QuestDefs.q01.goal.count, "目標を超えて数えない")
	eq(changed, false, "目標に届いたあとは進まない")
	eq(quests.q03, nil, "関係ないクエストは進まない")
end)

test("関係ない出来事では進まない（木人・別の種類）", function()
	local quests, changed = QuestLogic.record({}, QuestDefs, { kind = "kill", monster = "dummy" })
	eq(changed, false)
	eq(next(quests), nil)
	quests, changed = QuestLogic.record({}, QuestDefs, { kind = "craft", item = "travel_coat" })
	eq(changed, true)
	eq(quests.q02.progress, 1)
end)

test("目標に届いたものが pending に出て、markDone で消える", function()
	local quests = { q01 = { progress = 3 }, q03 = { progress = 3 }, q02 = { progress = 0 } }
	local pending = QuestLogic.pending(quests, QuestDefs)
	eq(#pending, 2)
	eq(pending[1], "q01", "order の順")
	eq(pending[2], "q03")
	local done = QuestLogic.markDone(quests, "q01")
	eq(done.q01.done, true)
	eq(quests.q01.done, nil, "元のテーブルは書き換えない")
	eq(#QuestLogic.pending(done, QuestDefs), 1)
	local after, changed = QuestLogic.record(done, QuestDefs, { kind = "kill", monster = "moripon" })
	eq(changed, false, "達成済みは進まない")
	eq(after.q01.progress, 3)
end)

test("探索の隠し場所からピースを引ける", function()
	eq(QuestLogic.explorePiece("e01", PieceDefs), "p01")
	eq(QuestLogic.explorePiece("e02", PieceDefs), "p02")
	eq(QuestLogic.explorePiece("e99", PieceDefs), nil)
	eq(QuestLogic.explorePiece(1, PieceDefs), nil)
end)

test("町に最初の探索ピースがある（最初の 60 秒）", function()
	eq(#AreaDefs.town.exploreSpots >= 1, true)
	eq(QuestLogic.explorePiece(AreaDefs.town.exploreSpots[1], PieceDefs) ~= nil, true)
	eq(#Config.Explore.SpawnOffset, 3)
	eq(#Config.QuestBoard.SpawnOffset, 3)
end)

test("完成の称号が Config にある", function()
	eq(Config.Titles.first_picture ~= nil, true)
	eq(type(Config.Badge.CompletionBadgeId), "number")
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

-- GrantLogic（Step 2） -----------------------------------------------------

local GrantLogic = require("../src/shared/Logic/GrantLogic")
local CombatLogic = require("../src/shared/Logic/CombatLogic")

local function grantsOf(...: string): { any }
	local list = {}
	for i, id in { ... } do
		table.insert(list, { ability = id, seq = i })
	end
	return list
end

test("付与上限は基本 10、装備 1 つにつき +1", function()
	eq(GrantLogic.capacity(10, {}, ItemDefs), 10)
	eq(GrantLogic.capacity(10, { weapon = "wooden_blade" }, ItemDefs), 11)
	eq(GrantLogic.capacity(10, { weapon = "wooden_blade", armor = "travel_coat" }, ItemDefs), 12)
end)

test("付与できる・同じ能力は 1 つまで・上限を超えられない", function()
	local ok, g = GrantLogic.apply({}, {}, "might", 0, 10, AbilityDefs, 1)
	eq(ok, true)
	eq(GrantLogic.used(g, AbilityDefs), 4)
	local ok2, reason2 = GrantLogic.apply(g, {}, "might", 0, 10, AbilityDefs, 2)
	eq(ok2, false)
	eq(reason2, "already_active")
	local _, g3 = GrantLogic.apply(g, {}, "bulwark", 0, 10, AbilityDefs, 2) -- 8
	local ok4, reason4 = GrantLogic.apply(g3, {}, "gale", 0, 10, AbilityDefs, 3) -- 8 + 3 = 11 > 10
	eq(ok4, false)
	eq(reason4, "over_capacity")
	local ok5 = GrantLogic.apply(g3, {}, "gale", 0, 11, AbilityDefs, 3) -- 装備 1 つで 11
	eq(ok5, true)
	eq((GrantLogic.apply({}, {}, "nope", 0, 10, AbilityDefs, 1)), false)
	eq((GrantLogic.apply({}, {}, 5, 0, 10, AbilityDefs, 1)), false)
end)

test("解除すると 5 秒付け直せない", function()
	local g = grantsOf("might", "gale")
	local ok, kept, cds, released = GrantLogic.release(g, {}, "might", 100, 5)
	eq(ok, true)
	eq(#kept, 1)
	eq(released[1], "might")
	eq(cds.might, 105)
	local okA, reasonA = GrantLogic.apply(kept, cds, "might", 104.9, 10, AbilityDefs, 3)
	eq(okA, false)
	eq(reasonA, "cooldown")
	eq((GrantLogic.apply(kept, cds, "might", 105, 10, AbilityDefs, 3)), true)
	eq(#g, 2, "元は変わらない")
end)

test("全解除と、付いていない能力の解除", function()
	local ok, kept, _, released = GrantLogic.release(grantsOf("might", "gale"), {}, "all", 0, 5)
	eq(ok, true)
	eq(#kept, 0)
	eq(#released, 2)
	local ok2, reason2 = GrantLogic.release({}, {}, "all", 0, 5)
	eq(ok2, false)
	eq(reason2, "not_active")
end)

test("剥がしの代価は一番安い付与（同じなら古いもの）", function()
	eq(GrantLogic.pickLowest(grantsOf("might", "gale", "bulwark"), AbilityDefs), "gale")
	eq(GrantLogic.pickLowest(grantsOf("bulwark", "might"), AbilityDefs), "bulwark")
	eq(GrantLogic.pickLowest({}, AbilityDefs), nil)
end)

test("必殺技は一番高い付与の技（同じなら新しいもの）", function()
	eq(GrantLogic.pickHighest(grantsOf("gale", "might"), AbilityDefs), "might")
	eq(GrantLogic.pickHighest(grantsOf("might", "bulwark"), AbilityDefs), "bulwark")
	eq(GrantLogic.pickHighest(grantsOf("gale"), AbilityDefs), "gale")
	eq(GrantLogic.pickHighest({}, AbilityDefs), nil)
end)

test("remove は 1 つだけ取り除く", function()
	local found, kept = GrantLogic.remove(grantsOf("might", "gale"), "gale")
	eq(found, true)
	eq(#kept, 1)
	local found2 = GrantLogic.remove(kept, "gale")
	eq(found2, false)
end)

test("倍率：付与と装備を足し算で重ねる", function()
	local m = GrantLogic.multipliers(grantsOf("gale", "might", "bulwark"), AbilityDefs,
		{ weapon = "wooden_blade", armor = "travel_coat" }, ItemDefs, 0.1)
	assert(math.abs(m.moveSpeed - 1.30) < 1e-9, "moveSpeed")
	assert(math.abs(m.attack - 1.30) < 1e-9, "attack")
	assert(math.abs(m.damageTaken - 0.70) < 1e-9, "damageTaken")
	local none = GrantLogic.multipliers({}, AbilityDefs, {}, ItemDefs, 0.1)
	eq(none.attack, 1)
end)

-- CombatLogic（Step 2） ----------------------------------------------------

test("ダメージ計算と対人の上限", function()
	eq(CombatLogic.damage(10, 1.25, 1, nil), 12.5)
	eq(CombatLogic.damage(10, 1, 0.75, nil), 7.5)
	eq(CombatLogic.damage(100, 1, 1, 35), 35)
	eq(CombatLogic.damage(-5, 1, 1, nil), 0)
	eq(CombatLogic.damage(0 / 0, 1, 1, nil), 0)
end)

test("シールドの吸収", function()
	local s, d = CombatLogic.absorb(30, 10)
	eq(s, 20)
	eq(d, 0)
	s, d = CombatLogic.absorb(5, 10)
	eq(s, 0)
	eq(d, 5)
	s, d = CombatLogic.absorb(0, 10)
	eq(d, 10)
end)

test("ゲージは 0〜100 に収まり、不正な値は無視", function()
	eq(CombatLogic.addGauge(95, 8, 100), 100)
	eq(CombatLogic.addGauge(10, -5, 100), 10)
	eq(CombatLogic.addGauge(10, 0 / 0, 100), 10)
	eq(CombatLogic.addGauge(10, math.huge, 100), 10)
end)

test("必殺技の威力 = 30 + 消費コスト × 8", function()
	eq(CombatLogic.ultimatePower(0, Config.Ultimate.BasePower, Config.Ultimate.PowerPerCost), 30)
	eq(CombatLogic.ultimatePower(11, Config.Ultimate.BasePower, Config.Ultimate.PowerPerCost), 118)
end)

test("突進の範囲", function()
	eq(CombatLogic.inDashArea(10, 3, 30, 8), true)
	eq(CombatLogic.inDashArea(10, 5, 30, 8), false)
	eq(CombatLogic.inDashArea(-1, 0, 30, 8), false)
	eq(CombatLogic.inDashArea(31, 0, 30, 8), false)
end)

test("4 段コンボの段の進み方", function()
	eq(CombatLogic.nextComboStep(nil, nil, 0, 1, 4), 1)
	eq(CombatLogic.nextComboStep(1, 0, 0.5, 1, 4), 2)
	eq(CombatLogic.nextComboStep(3, 0, 0.5, 1, 4), 4)
	eq(CombatLogic.nextComboStep(4, 0, 0.5, 1, 4), 1, "4 段目の次は 1 段目")
	eq(CombatLogic.nextComboStep(2, 0, 1.5, 1, 4), 1, "間があいたら 1 段目")
	eq(#Config.Combat.ComboDamage, 4)
end)

local function hit(overrides: { [string]: boolean }): any
	local input: any = { finisher = false, guarding = false, front = false, guardBreak = false, noKnockback = false }
	for k, v in overrides do
		input[k] = v
	end
	return CombatLogic.resolveHit(input, 0.2)
end

test("当たり方：何もなし／締めで吹き飛ぶ／鉄壁は吹き飛ばない", function()
	local plain = hit({})
	eq(plain.damageMultiplier, 1)
	eq(plain.knockback, false)
	eq(hit({ finisher = true }).knockback, true)
	eq(hit({ finisher = true, noKnockback = true }).knockback, false)
end)

test("当たり方：正面ガードで減る／背後はガードが効かない／剛力の締めで割れる", function()
	local guarded = hit({ guarding = true, front = true })
	eq(guarded.damageMultiplier, 0.2)
	eq(hit({ guarding = true, front = true, finisher = true }).knockback, false, "剛力なしの締めはガードで止まる")
	eq(hit({ guarding = true, front = false, finisher = true }).knockback, true, "背後からはガードが効かない")
	local broken = hit({ guarding = true, front = true, finisher = true, guardBreak = true })
	eq(broken.guardBroken, true)
	eq(broken.damageMultiplier, 1)
	eq(hit({ guarding = true, front = true, guardBreak = true }).guardBroken, false, "締め以外では割れない")
end)

test("正面の判定とダッシュのクールダウン", function()
	eq(CombatLogic.isFront(0, -1, 0, -1), true)
	eq(CombatLogic.isFront(0, -1, 0, 1), false)
	eq(CombatLogic.dashCooldown(3, false, 0.5), 3)
	eq(CombatLogic.dashCooldown(3, true, 0.5), 1.5)
end)

test("能力 3 種がそれぞれ別の perk を持つ", function()
	local seen = {}
	for id, def in AbilityDefs do
		assert(type(def.perk) == "string", "perk がない " .. id)
		assert(not seen[def.perk], "perk が重複 " .. id)
		seen[def.perk] = true
	end
	assert(seen.dash_fast and seen.guard_break and seen.no_knockback, "perk の種類")
end)

test("必殺技の既定の技が定義にある", function()
	assert(UltimateDefs[Config.Ultimate.DefaultUltimate], "DefaultUltimate")
	assert(AbilityDefs[Config.Dummy.SelfGrant], "Dummy.SelfGrant")
end)

-- 構文チェック ---------------------------------------------------------------
-- src 以下の全 .luau ファイルをコンパイルして、構文エラーがないか確かめる（ERROR_LOG #1）
-- リポジトリのルートから `lune run tests/run` で実行する前提

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local function collectLuauFiles(dir: string, out: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			collectLuauFiles(path, out)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(out, path)
		end
	end
end

local sourceFiles = {}
collectLuauFiles("src", sourceFiles)
table.sort(sourceFiles)

test("src 以下のファイルが見つかる", function()
	assert(#sourceFiles >= 20, "ファイル数が少ない（ルートから実行しているか確認）: " .. #sourceFiles)
end)

for _, path in sourceFiles do
	test("構文エラーなし: " .. path, function()
		luau.compile(fs.readFile(path))
	end)
end

-- 参照チェック ---------------------------------------------------------------
-- Studio がない環境でも見つけられる打ち間違いを調べる
-- ・require(script.Parent.X) / require(Server.X) の X が同じフォルダに実在するか
-- ・コードに書いた Remote 名が Net.luau の一覧にあるか

local function exists(path: string): boolean
	return fs.isFile(path)
end

local function dirOf(path: string): string
	return string.match(path, "^(.*)/[^/]+$") or "."
end

local function moduleExists(dir: string, name: string): boolean
	return exists(dir .. "/" .. name .. ".luau")
		or exists(dir .. "/" .. name .. ".server.luau")
		or exists(dir .. "/" .. name .. ".client.luau")
		or fs.isDir(dir .. "/" .. name)
end

-- Net.luau は game を使うので Lune で require できない。文字列として読んで名前を取り出す
local netSource = fs.readFile("src/shared/Net.luau")
local remoteNames: { [string]: string } = {}
for _, listName in { "Functions", "ClientEvents", "ServerEvents" } do
	local block = string.match(netSource, "Net%." .. listName .. " = table%.freeze%(%{(.-)%}%)")
	assert(block, "Net." .. listName .. " が読めない")
	for name in string.gmatch(block, '"([%w_]+)"') do
		remoteNames[name] = listName
	end
end

test("Net の Remote が 14 個", function()
	local n = 0
	for _ in remoteNames do
		n += 1
	end
	eq(n, 14)
end)

local REMOTE_PATTERNS: { { pattern: string, kinds: { string } } } = {
	{ pattern = 'Net%.getFunction%("([%w_]+)"', kinds = { "Functions" } },
	{ pattern = 'Net%.getEvent%("([%w_]+)"', kinds = { "ClientEvents", "ServerEvents" } },
	{ pattern = 'invoke%("([%w_]+)"', kinds = { "Functions" } },
	{ pattern = 'Remotes%.onInvoke%("([%w_]+)"', kinds = { "Functions" } },
	{ pattern = 'Remotes%.onEvent%("([%w_]+)"', kinds = { "ClientEvents" } },
	{ pattern = 'Remotes%.fire%([%w_%.]+, "([%w_]+)"', kinds = { "ServerEvents" } },
	{ pattern = 'Remotes%.fireAll%("([%w_]+)"', kinds = { "ServerEvents" } },
}

for _, path in sourceFiles do
	local source = fs.readFile(path)
	local dir = dirOf(path)
	test("「(」で始まる行がない（ERROR_LOG #1）: " .. path, function()
		local lineNumber = 0
		for line in string.gmatch(source .. "\n", "(.-)\n") do
			lineNumber += 1
			assert(not string.match(line, "^%s*%("), "行 " .. lineNumber .. " が「(」で始まっている")
		end
	end)
	test("参照先が実在する: " .. path, function()
		for name in string.gmatch(source, "require%(script%.Parent%.([%w_]+)%)") do
			assert(moduleExists(dir, name), "require 先がない: " .. name)
		end
		for name in string.gmatch(source, "require%(Server%.([%w_]+)%)") do
			assert(moduleExists("src/server", name), "require 先がない: " .. name)
		end
		for _, rule in REMOTE_PATTERNS do
			for name in string.gmatch(source, rule.pattern) do
				local kind = remoteNames[name]
				assert(kind and table.find(rule.kinds, kind), "Net にない（または種類が違う）Remote: " .. name)
			end
		end
	end)
end

-- DuelLogic（Step 4） -------------------------------------------------------

test("賭けピース：未装着がなければ nil", function()
	eq(DuelLogic.pickBet({ placed = { p01 = true }, unplaced = {} }, PieceDefs), nil)
end)

test("賭けピース：はまっているピースの写しを最優先", function()
	local pieces = { placed = { p02 = true }, unplaced = { p02 = 1, p05 = 2, p09 = 1 } }
	eq(DuelLogic.pickBet(pieces, PieceDefs), "p02")
end)

test("賭けピース：次に 2 枚以上あるもの、最後に 1 枚だけのもの", function()
	eq(DuelLogic.pickBet({ placed = {}, unplaced = { p05 = 2, p09 = 1 } }, PieceDefs), "p05")
	eq(DuelLogic.pickBet({ placed = {}, unplaced = { p03 = 1, p07 = 1 } }, PieceDefs), "p07", "同じ順位なら grid の大きい方")
	eq(DuelLogic.pickBet({ placed = {}, unplaced = { p99 = 3 } }, PieceDefs), nil, "未定義の ID は選ばない")
end)

test("賭けピース：元のテーブルは書き換えない", function()
	local pieces = { placed = {}, unplaced = { p05 = 2 } }
	DuelLogic.pickBet(pieces, PieceDefs)
	eq(pieces.unplaced.p05, 2)
end)

test("時間切れ：HP の割合が少ない方が負け、同じなら引き分け", function()
	eq(DuelLogic.judgeTimeout(0.3, 0.8), "b", "a が少ない → b の勝ち")
	eq(DuelLogic.judgeTimeout(0.9, 0.2), "a")
	eq(DuelLogic.judgeTimeout(0.5, 0.5), "draw")
end)

test("リングの内外と台の上", function()
	eq(DuelLogic.isInside(0, 0, 3, 16, 4), true)
	eq(DuelLogic.isInside(15, 8, 3, 16, 4), false, "縁の外")
	eq(DuelLogic.isInside(3, 3, -5, 16, 4), false, "落ちた")
	eq(DuelLogic.isOnPad(1, 1, 3, 3, 7), true)
	eq(DuelLogic.isOnPad(4, 0, 3, 3, 7), false, "台の外")
	eq(DuelLogic.isOnPad(0, 0, 10, 3, 7), false, "跳んでいる")
end)

test("再戦は負けてから決まった秒数以内", function()
	eq(DuelLogic.isRematch(nil, 100, 600), false)
	eq(DuelLogic.isRematch(100, 650, 600), true)
	eq(DuelLogic.isRematch(100, 701, 600), false)
end)

test("リングの数値がそろっている", function()
	eq(Config.Ring.PadOffset + Config.Ring.PadRadius < Config.Ring.Radius, true, "台はリングの中にある")
	eq(#Config.Ring.SpawnOffset, 3)
	eq(Config.Ring.CountdownSeconds > 0 and Config.Ring.MatchSeconds > 0, true)
end)

-- DropLogic（Step 5） -------------------------------------------------------

-- 決まった列を返す乱数（テスト用）
local function sequence(values: { number }): () -> number
	local i = 0
	return function()
		i += 1
		return values[((i - 1) % #values) + 1]
	end
end

test("通常モンスター：素材は min〜max、ピースは確率で", function()
	local drop = DropLogic.roll(MonsterDefs.moripon, PieceDefs, 0.05, 0, sequence({ 0.0, 0.99, 0.01 }))
	eq(drop.items.leaf, 2, "0.99 → max の 2")
	eq(drop.piece, "p03", "0.01 < 0.05 で落ちる")
	drop = DropLogic.roll(MonsterDefs.moripon, PieceDefs, 0.05, 0, sequence({ 0.0, 0.0, 0.5 }))
	eq(drop.items.leaf, 1, "0.0 → min の 1")
	eq(drop.piece, nil, "0.5 では落ちない")
end)

test("ピースを落とさないモンスターは落とさない", function()
	local drop = DropLogic.roll(MonsterDefs.aohane, PieceDefs, 1.0, 0, sequence({ 0.0 }))
	eq(drop.piece, nil)
	eq(drop.items.feather ~= nil, true)
end)

test("ボス：1 回目と 2 回目の撃破で別のピース、3 回目からは落とさない", function()
	local any = sequence({ 0.5 })
	eq(DropLogic.roll(MonsterDefs.oonushi, PieceDefs, 0.05, 0, any).piece, "p08")
	eq(DropLogic.roll(MonsterDefs.oonushi, PieceDefs, 0.05, 1, any).piece, "p09")
	eq(DropLogic.roll(MonsterDefs.oonushi, PieceDefs, 0.05, 2, any).piece, nil)
	local drop = DropLogic.roll(MonsterDefs.oonushi, PieceDefs, 0.05, 0, any)
	eq(drop.items.fang ~= nil and drop.items.feather ~= nil, true, "羽と牙も落とす")
end)

test("ボスのドロップをもらえるのは最大 HP の一定割合以上を与えた人", function()
	eq(DropLogic.qualifies(150, 1500, 0.1), true)
	eq(DropLogic.qualifies(149, 1500, 0.1), false)
end)

test("20 万回のシミュレーション：ピースは約 5%、1 個出るまで平均約 20 体", function()
	-- Lune には Roblox の Random がないので、種を固定した math.random を使う
	math.randomseed(12345)
	local function rng(): number
		return math.random()
	end
	local trials = 200000
	local pieces = 0
	local leaves = 0
	local streak = 0
	local streaks = {}
	for _ = 1, trials do
		local drop = DropLogic.roll(MonsterDefs.moripon, PieceDefs, Config.Drops.NormalPieceChance, 0, rng)
		streak += 1
		leaves += drop.items.leaf or 0
		if drop.piece then
			pieces += 1
			table.insert(streaks, streak)
			streak = 0
		end
	end
	local rate = pieces / trials
	assert(math.abs(rate - Config.Drops.NormalPieceChance) < 0.003, ("ピースの出現率 %.4f"):format(rate))
	local total = 0
	for _, n in streaks do
		total += n
	end
	local mean = total / #streaks
	assert(math.abs(mean - 1 / Config.Drops.NormalPieceChance) < 1.0, ("平均の撃破数 %.2f"):format(mean))
	local leafMean = leaves / trials
	assert(math.abs(leafMean - 1.5) < 0.02, ("葉の平均 %.3f"):format(leafMean))
	table.sort(streaks)
	print(("      [参考] ピース %.2f%%、1 個までの平均 %.1f 体、90%% の人は %d 体以内"):format(rate * 100, mean, streaks[math.ceil(#streaks * 0.9)]))
end)

test("モンスターの出現と見た目が定義とそろっている", function()
	for _, entry in Config.Monsters.Spawns do
		eq(MonsterDefs[entry.monster] ~= nil, true, "出現: " .. entry.monster)
		eq(AreaDefs[entry.area] ~= nil, true, "エリア: " .. entry.area)
		eq(MonsterDefs[entry.monster].area, entry.area, "棲む場所が一致: " .. entry.monster)
		eq(#entry.offset, 3)
	end
	for id in MonsterDefs do
		local look = Config.Monsters.Looks[id]
		eq(look ~= nil, true, "見た目: " .. id)
		eq(#look.size, 3)
		eq(#look.color, 3)
	end
	for areaId, offset in Config.Travel.PlaceholderOffsets do
		eq(AreaDefs[areaId] ~= nil, true, "仮の足場: " .. areaId)
		eq(#offset, 3)
	end
	for spotId, offset in Config.Explore.AreaOffsets do
		eq(QuestLogic.explorePiece(spotId, PieceDefs) ~= nil, true, "隠し場所: " .. spotId)
		eq(#offset, 3)
	end
end)

-- Claude と Codex の指示の同期 ------------------------------------------------

local function bodyWithoutHeading(path: string): string
	local text = string.gsub(fs.readFile(path), "\r", "")
	local _, firstLineEnd = string.find(text, "\n", 1, true)
	return string.sub(text, (firstLineEnd or 0) + 1)
end

test("CLAUDE.md と AGENTS.md は見出し以外が同じ", function()
	eq(fs.isFile("CLAUDE.md"), true, "CLAUDE.md がある")
	eq(fs.isFile("AGENTS.md"), true, "AGENTS.md がある")
	eq(bodyWithoutHeading("CLAUDE.md") == bodyWithoutHeading("AGENTS.md"), true, "片方だけ直していないか")
end)

print(("\n%d passed, %d failed"):format(passed, failed))
if failed > 0 then
	error("テスト失敗")
end
