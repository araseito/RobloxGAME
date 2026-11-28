--!strict
-- 探索ピースの隠し場所を、自分がもう拾ったものだけ自分の画面から消す。
-- 隠し場所は全員で共有の 1 つだが、拾ったかどうかは人ごと（サーバーでも確かめている）。

local CollectionService = game:GetService("CollectionService")

local StateStore = require(script.Parent.StateStore)

local ExploreSpots = {}

local EXPLORE_TAG = "ExploreSpot" -- サーバーの QuestService.EXPLORE_TAG と同じ

local function apply(spot: Instance)
	local found = StateStore.state.exploreFound or {}
	local spotId = spot:GetAttribute("SpotId")
	local hidden = type(spotId) == "string" and found[spotId] == true
	if spot:IsA("BasePart") then
		-- クライアントで変えた値はサーバーや他の人には伝わらない
		spot.Transparency = if hidden then 1 else 0
	end
	for _, d in spot:GetDescendants() do
		if d:IsA("ProximityPrompt") then
			d.Enabled = not hidden
		elseif d:IsA("PointLight") or d:IsA("Sparkles") then
			d.Enabled = not hidden
		end
	end
end

local function applyAll()
	for _, spot in CollectionService:GetTagged(EXPLORE_TAG) do
		apply(spot)
	end
end

function ExploreSpots.mount()
	CollectionService:GetInstanceAddedSignal(EXPLORE_TAG):Connect(apply)
	StateStore.Changed:Connect(function(sections: { string })
		for _, section in sections do
			if section == "exploreFound" then
				applyAll()
			end
		end
	end)
	applyAll()
end

return ExploreSpots
