--!strict
-- DataStore の読み書きとセッションロック。
-- ・読み込み時に UpdateAsync でロックを取る。他サーバーが使用中なら待って再試行
-- ・保存時はロックが自分のものか確かめてから書く。奪われていたら書かずにキックする
-- ・定期保存、退出時の保存（ロック解放）、サーバー終了時の保存
-- ・Studio で API アクセスが無効なときだけ、メモリ上の仮ストアに切り替える（本番では切り替えない）

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local ProfileSchema = require(Shared:WaitForChild("Logic"):WaitForChild("ProfileSchema"))
local SessionLock = require(Shared:WaitForChild("Logic"):WaitForChild("SessionLock"))

local DataService = {}

local loadedEvent = Instance.new("BindableEvent")
DataService.Loaded = loadedEvent.Event -- (player: Player)

local profiles: { [Player]: any } = {}
local saving: { [Player]: boolean } = {}
-- 退出時、最後の保存の写しを取る直前に呼ぶ（決闘中に抜けた人の賭けピースを、保存に間に合わせて動かすため）
local beforeReleaseHooks: { (Player) -> () } = {}

function DataService.onBeforeRelease(fn: (Player) -> ())
	table.insert(beforeReleaseHooks, fn)
end

-- Studio では JobId が空なので、起動ごとに別の ID を作る
local jobId = if game.JobId ~= "" then game.JobId else ("studio-" .. HttpService:GenerateGUID(false))

local store: DataStore? = nil
local memoryMode = false
local memoryStore: { [string]: any } = {}
local initialized = false

local function keyFor(player: Player): string
	return Config.Data.KeyPrefix .. tostring(player.UserId)
end

local function isStudioAccessError(err: any): boolean
	local message = tostring(err)
	return string.find(message, "StudioAccessToApisNotAllowed", 1, true) ~= nil
		or string.find(message, "publish", 1, true) ~= nil
		or string.find(message, "403", 1, true) ~= nil
end

local function switchToMemoryMode(reason: any)
	if memoryMode then
		return
	end
	memoryMode = true
	warn(
		"[DataService] Studio から DataStore にアクセスできないため、メモリ上の仮ストアを使います。"
			.. "このテストサーバーを閉じるとデータは消えます。理由: "
			.. tostring(reason)
	)
end

-- UpdateAsync の薄いラッパー。transform が nil を返すと書き込みを取りやめる。
-- 戻り値は「通信が成功したか」とエラー内容だけ。結果は transform 側で upvalue に書き出す。
local function update(key: string, transform: (any) -> any): (boolean, any)
	if memoryMode then
		local result = transform(ProfileSchema.deepCopy(memoryStore[key]))
		if result ~= nil then
			memoryStore[key] = ProfileSchema.deepCopy(result)
		end
		return true, nil
	end

	local currentStore = store
	if currentStore == nil then
		return false, "store_unavailable"
	end

	local ok, err = pcall(function()
		currentStore:UpdateAsync(key, transform)
	end)
	if not ok and RunService:IsStudio() and isStudioAccessError(err) then
		switchToMemoryMode(err)
		return update(key, transform)
	end
	return ok, err
end

local function loadProfile(player: Player): any
	local key = keyFor(player)
	for attempt = 1, Config.Data.LoadMaxAttempts do
		local outcome = "error"
		local loaded: any = nil

		local ok, err = update(key, function(stored: any): any
			local now = os.time()
			local state = SessionLock.state(stored and stored.lock, jobId, now, Config.Data.LockTimeout)
			if not SessionLock.canAcquire(state) then
				outcome = "locked"
				return nil
			end
			local profile = ProfileSchema.reconcile(stored, now)
			profile.lock = { jobId = jobId, at = now }
			profile.lastSeen = now
			outcome = "ok"
			loaded = profile
			return profile
		end)

		if ok and outcome == "ok" then
			return loaded
		end
		if not ok then
			warn(("[DataService] 読み込み失敗（%d 回目）: %s"):format(attempt, tostring(err)))
		else
			warn(("[DataService] 別サーバーが使用中のため待機（%d 回目）"):format(attempt))
		end
		if player.Parent == nil then
			return nil
		end
		task.wait(Config.Data.LoadRetryInterval)
	end
	return nil
end

-- release = true のときはロックを外して書く（退出時・終了時）
local function saveProfile(player: Player, release: boolean): boolean
	local profile = profiles[player]
	if profile == nil then
		return false
	end
	if saving[player] then
		-- 前の保存が終わるのを待つ（同じキーへの書き込みを重ねない）
		while saving[player] do
			task.wait(0.1)
		end
	end
	saving[player] = true

	local snapshot = ProfileSchema.deepCopy(profile)
	local outcome = "error"
	local ok, err = update(keyFor(player), function(stored: any): any
		local now = os.time()
		local state = SessionLock.state(stored and stored.lock, jobId, now, Config.Data.LockTimeout)
		if state ~= "ours" then
			outcome = "lost"
			return nil
		end
		snapshot.lock = if release then nil else { jobId = jobId, at = now }
		snapshot.lastSeen = now
		outcome = "ok"
		return snapshot
	end)

	saving[player] = nil

	if not ok then
		warn("[DataService] 保存失敗: " .. tostring(err))
		return false
	end
	if outcome == "lost" then
		-- 他のサーバーがロックを持っている。このサーバーのデータは古いので書かない
		warn("[DataService] ロックを失ったため保存を中止: " .. player.Name)
		profiles[player] = nil
		if player.Parent ~= nil then
			player:Kick("別の場所で同じアカウントが読み込まれました。入り直してください。")
		end
		return false
	end
	return outcome == "ok"
end

local function onPlayerAdded(player: Player)
	local profile = loadProfile(player)
	if profile == nil then
		if player.Parent ~= nil then
			player:Kick("データを読み込めませんでした。しばらくしてから入り直してください。")
		end
		return
	end

	profiles[player] = profile

	if player.Parent == nil then
		-- 読み込み中に退出した。ロックを外しておく
		saveProfile(player, true)
		profiles[player] = nil
		return
	end

	loadedEvent:Fire(player)
end

local function onPlayerRemoving(player: Player)
	if profiles[player] ~= nil then
		for _, fn in beforeReleaseHooks do
			local ok, err = pcall(fn, player)
			if not ok then
				warn("[DataService] 退出時の処理でエラー: " .. tostring(err))
			end
		end
		saveProfile(player, true)
		profiles[player] = nil
	end
end

function DataService.init()
	assert(not initialized, "DataService.init() は 1 回だけ")
	initialized = true

	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.Data.StoreName)
	end)
	if ok then
		store = result
	elseif RunService:IsStudio() then
		switchToMemoryMode(result)
	else
		warn("[DataService] DataStore を取得できません: " .. tostring(result))
	end

	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(onPlayerRemoving)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end

	-- 定期保存（ロックの期限も更新される）
	task.spawn(function()
		while true do
			task.wait(Config.Data.AutosaveInterval)
			for player in profiles do
				task.spawn(saveProfile, player, false)
			end
		end
	end)

	game:BindToClose(function()
		if memoryMode then
			return
		end
		local pending = 0
		for player in profiles do
			pending += 1
			task.spawn(function()
				saveProfile(player, true)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

-- 読み込み済みならプロフィールを返す（読み込み前・退出後は nil）
function DataService.getProfile(player: Player): any
	return profiles[player]
end

function DataService.waitForProfile(player: Player, timeout: number): any
	local deadline = os.clock() + timeout
	while profiles[player] == nil and player.Parent ~= nil and os.clock() < deadline do
		task.wait(0.1)
	end
	return profiles[player]
end

-- 開発用：すぐ保存する
function DataService.saveNow(player: Player): boolean
	return saveProfile(player, false)
end

function DataService.isMemoryMode(): boolean
	return memoryMode
end

return DataService
