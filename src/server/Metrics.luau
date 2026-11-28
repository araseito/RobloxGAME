--!strict
-- 計測は Roblox 公式の AnalyticsService に送る（個人を特定する情報は送らない）。
-- 継続率・セッション時間・フレンドとの同時プレイは公式ダッシュボードで見る。
-- 失敗しても遊びには影響させない（pcall で包む）。

local AnalyticsService = game:GetService("AnalyticsService")

local Metrics = {}

-- カスタムイベント名はここに集める（打ち間違いを防ぐ）
Metrics.Events = table.freeze({
	PieceGained = "PieceGained",
	PuzzleCompleted = "PuzzleCompleted",
	RingJoined = "RingJoined",
	RingWon = "RingWon",
	RingLost = "RingLost",
	RingRematch = "RingRematch", -- 負けてから Config.Ring.RematchWindowSeconds 以内の再参加
	UltimateCast = "UltimateCast",
	MonsterKilled = "MonsterKilled",
	CraftExecuted = "CraftExecuted",
	CraftOpenedNoCraft = "CraftOpenedNoCraft",
	QuestCompleted = "QuestCompleted",
})

-- 最初の 60 秒のファネル（PHASE0_PLAN_v2 5.8）
Metrics.Onboarding = table.freeze({
	{ step = 1, name = "Spawned" },
	{ step = 2, name = "PickedFirstPiece" },
	{ step = 3, name = "PlacedFirstPiece" },
	{ step = 4, name = "TraveledToSatoyama" },
})

local knownEvents: { [string]: boolean } = {}
for _, name in Metrics.Events do
	knownEvents[name] = true
end

-- field：内訳（ピースの入手経路など）。公式ダッシュボードでは CustomField01 として分けて見られる
function Metrics.event(player: Player, eventName: string, value: number?, field: string?)
	assert(knownEvents[eventName], "未定義の計測イベント: " .. eventName)
	local ok, err = pcall(function()
		if field then
			AnalyticsService:LogCustomEvent(player, eventName, value or 1, {
				[Enum.AnalyticsCustomFieldKeys.CustomField01.Name] = field,
			})
		else
			AnalyticsService:LogCustomEvent(player, eventName, value or 1)
		end
	end)
	if not ok then
		warn("[Metrics] " .. eventName .. ": " .. tostring(err))
	end
end

-- ファネルは 1 人 1 回、順番どおりにだけ記録する（profile.onboarding.step に到達段階を保存）
function Metrics.onboarding(player: Player, profile: any, step: number)
	if profile == nil or profile.onboarding.step >= step then
		return
	end
	local entry = Metrics.Onboarding[step]
	assert(entry, "未定義のファネル段階: " .. tostring(step))
	if profile.onboarding.step ~= step - 1 then
		return -- 前の段階を飛ばしては記録しない
	end
	profile.onboarding.step = step
	local ok, err = pcall(function()
		AnalyticsService:LogOnboardingFunnelStepEvent(player, step, entry.name)
	end)
	if not ok then
		warn("[Metrics] onboarding " .. entry.name .. ": " .. tostring(err))
	end
end

return Metrics
