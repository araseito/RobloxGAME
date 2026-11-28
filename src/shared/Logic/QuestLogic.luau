--!strict
-- 掲示板のクエストと探索ピースの計算。require を使わない（定義データは引数で受け取る）。
-- quests の形：{ [questId] = { progress = n, done = true? } }
-- 元のテーブルは書き換えず、新しいテーブルを返す。

local QuestLogic = {}

export type Event = { kind: string, monster: string?, item: string? }

local function matches(goal: any, event: Event): boolean
	if goal.kind ~= event.kind then
		return false
	end
	if goal.kind == "kill" then
		return goal.monster == event.monster
	elseif goal.kind == "craft" then
		return goal.item == event.item
	end
	return false
end

local function copy(quests: any): any
	local out = {}
	for id, entry in quests do
		out[id] = table.clone(entry)
	end
	return out
end

-- 出来事（倒した・作った）を記録する。達成済みのクエストは進めない。
-- 戻り値：新しい quests と、進んだかどうか
function QuestLogic.record(quests: any, questDefs: any, event: Event): (any, boolean)
	local result = copy(quests)
	local changed = false
	for id, def in questDefs do
		local entry = result[id] or { progress = 0 }
		if not entry.done and matches(def.goal, event) and entry.progress < def.goal.count then
			entry.progress += 1
			result[id] = entry
			changed = true
		end
	end
	return result, changed
end

-- 目標に届いたが、まだ報酬を渡していないクエスト（order の順）
function QuestLogic.pending(quests: any, questDefs: any): { string }
	local list = {}
	for id, def in questDefs do
		local entry = quests[id]
		if entry and not entry.done and entry.progress >= def.goal.count then
			table.insert(list, id)
		end
	end
	table.sort(list, function(a, b)
		return questDefs[a].order < questDefs[b].order
	end)
	return list
end

function QuestLogic.markDone(quests: any, questId: string): any
	local result = copy(quests)
	local entry = result[questId] or { progress = 0 }
	entry.done = true
	result[questId] = entry
	return result
end

-- 探索の隠し場所 ID から、そこで拾えるピースを返す
function QuestLogic.explorePiece(spotId: any, pieceDefs: any): string?
	if type(spotId) ~= "string" then
		return nil
	end
	for id, def in pieceDefs do
		if def.route == "explore" and def.source == spotId then
			return id
		end
	end
	return nil
end

return QuestLogic
