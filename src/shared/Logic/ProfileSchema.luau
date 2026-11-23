--!strict
-- 保存データの形。require を使わない（Lune で単体テストするため）。
-- DataStore に入れる値は JSON にできる形だけにする（文字列キーの辞書、数値、文字列、真偽値）。

local ProfileSchema = {}

ProfileSchema.VERSION = 1

-- クライアントに見せてよいセクション（lock や createdAt は見せない）
ProfileSchema.CLIENT_SECTIONS = table.freeze({
	"pieces",
	"items",
	"equipped",
	"dex",
	"quests",
	"exploreFound",
	"areas",
	"bossKills",
	"titles",
	"activeTitle",
})

function ProfileSchema.deepCopy(value: any): any
	if type(value) ~= "table" then
		return value
	end
	local out = {}
	for k, v in value do
		out[ProfileSchema.deepCopy(k)] = ProfileSchema.deepCopy(v)
	end
	return out
end

function ProfileSchema.default(now: number): any
	return {
		schema = ProfileSchema.VERSION,
		createdAt = now,
		lastSeen = now,
		pieces = {
			placed = {}, -- [pieceId] = true（はめたもの。奪われない）
			unplaced = {}, -- [pieceId] = 枚数（未装着。重複を含む）
		},
		items = {}, -- [itemId] = 枚数
		equipped = {}, -- weapon = itemId, armor = itemId
		dex = {}, -- [monsterId] = { seen = true, kills = n }
		quests = {}, -- [questId] = { progress = n, done = true }
		exploreFound = {}, -- [spotId] = true
		areas = { town = true, satoyama = true }, -- 解放済みエリア
		bossKills = 0,
		titles = {}, -- [titleId] = true
		onboarding = { step = 0 }, -- 最初の 60 秒のファネルの到達段階
	}
end

-- template にあって target にないキーを補う。型が食い違う場合は template で置き換える。
local function fillMissing(target: any, template: any)
	for key, templateValue in template do
		local current = target[key]
		if current == nil then
			target[key] = ProfileSchema.deepCopy(templateValue)
		elseif type(templateValue) == "table" then
			if type(current) ~= "table" then
				target[key] = ProfileSchema.deepCopy(templateValue)
			elseif next(templateValue) ~= nil then
				-- 中身が決まっているテーブル（pieces など）は中も補う。
				-- 空のテーブル（items など）は自由な辞書なので中は触らない。
				fillMissing(current, templateValue)
			end
		elseif type(current) ~= type(templateValue) then
			target[key] = templateValue
		end
	end
end

-- 読み込んだ値（nil や古い形を含む）を、今の形に整えたコピーを返す
function ProfileSchema.reconcile(stored: any, now: number): any
	if type(stored) ~= "table" then
		return ProfileSchema.default(now)
	end
	local profile = ProfileSchema.deepCopy(stored)
	fillMissing(profile, ProfileSchema.default(now))
	-- 将来の移行処理はここに書く（schema の値で分岐）
	profile.schema = ProfileSchema.VERSION
	return profile
end

function ProfileSchema.clientSection(profile: any, section: string): any
	assert(table.find(ProfileSchema.CLIENT_SECTIONS, section), "見せられないセクション: " .. section)
	return ProfileSchema.deepCopy(profile[section])
end

function ProfileSchema.clientView(profile: any): any
	local view = {}
	for _, section in ProfileSchema.CLIENT_SECTIONS do
		view[section] = ProfileSchema.deepCopy(profile[section])
	end
	return view
end

return ProfileSchema
