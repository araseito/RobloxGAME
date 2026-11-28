--!strict
-- パズルボックス：はめる・完成・Badge・称号（PHASE0_PLAN_v2 5.3）。
-- ピースの増減そのものは InventoryService が受け持つ。ここは「はめてよいか」の確認と、完成の処理だけ。

local BadgeService = game:GetService("BadgeService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local PieceDefs = require(Shared:WaitForChild("PieceDefs"))
local PuzzleLogic = require(Shared:WaitForChild("Logic"):WaitForChild("PuzzleLogic"))

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local StateSync = require(script.Parent.StateSync)
local Metrics = require(script.Parent.Metrics)
local DuelRingService = require(script.Parent.DuelRingService)

local PuzzleBoxService = {}

local COMPLETION_TITLE = "first_picture"

-- はめられるのは町だけ（5.3）。
-- 仮置き：エリアと移動は Step 5 で作る。それまではマップ全体が町なので、どこでもはめられる
local function isInTown(_player: Player): boolean
	return true
end

local function awardBadge(player: Player)
	local badgeId = Config.Badge.CompletionBadgeId
	if badgeId == 0 then
		warn("[PuzzleBox] Config.Badge.CompletionBadgeId が 0 のため、Badge は渡していません")
		return
	end
	task.spawn(function()
		local ok, err = pcall(function()
			BadgeService:AwardBadge(player.UserId, badgeId)
		end)
		if not ok then
			warn("[PuzzleBox] Badge を渡せませんでした: " .. tostring(err))
		end
	end)
end

-- 9 つそろっていて、まだ称号を持っていなければ完成の処理をする
local function checkCompletion(player: Player, profile: any)
	if profile.titles[COMPLETION_TITLE] or not PuzzleLogic.isComplete(profile.pieces.placed, PieceDefs) then
		return
	end
	profile.titles[COMPLETION_TITLE] = true
	profile.activeTitle = COMPLETION_TITLE
	StateSync.push(player, "titles", "activeTitle")
	Metrics.event(player, Metrics.Events.PuzzleCompleted)
	awardBadge(player)
end

function PuzzleBoxService.place(player: Player, pieceId: any): (boolean, string?)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	if not isInTown(player) then
		return false, "not_in_town"
	end
	if DuelRingService.isLocked(player) then
		return false, "ring_locked" -- 賭けピースを動かさないため、決闘の台にいる間ははめられない
	end
	local ok, reason = InventoryService.placePiece(player, pieceId)
	if not ok then
		return false, reason
	end
	Metrics.onboarding(player, profile, 3)
	checkCompletion(player, profile)
	return true, nil
end

return PuzzleBoxService
