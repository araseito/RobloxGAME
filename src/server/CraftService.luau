--!strict
-- クラフト（ワンタップ合成）と、回復薬を使う（PHASE0_PLAN_v2 5.6）。
-- ・合成は消費と付与を InventoryService.applyItems で同時に行う（途中で割り込まれない）
-- ・合成したらクエスト（作る）に記録する
-- ・計測：合成の実行、合成画面を開いたが合成しなかった
-- ・回復薬：戦闘中だけ、リングでは使えない。最大 HP の healRatio を回復

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local RecipeDefs = require(Shared:WaitForChild("RecipeDefs"))
local CraftLogic = require(Shared:WaitForChild("Logic"):WaitForChild("CraftLogic"))

local DataService = require(script.Parent.DataService)
local InventoryService = require(script.Parent.InventoryService)
local BattleStateService = require(script.Parent.BattleStateService)
local QuestService = require(script.Parent.QuestService)
local Metrics = require(script.Parent.Metrics)

local CraftService = {}

-- 合成画面を開いている人と、開いてから合成したか
local openSessions: { [Player]: { crafted: boolean } } = {}

function CraftService.craft(player: Player, recipeId: any): (boolean, string?)
	local recipe = if type(recipeId) == "string" then RecipeDefs[recipeId] else nil
	if recipe == nil then
		return false, "unknown_id"
	end
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	if not CraftLogic.canCraft(profile.items, recipe) then
		return false, "insufficient"
	end
	local ok, reason = InventoryService.applyItems(player, CraftLogic.change(recipe))
	if not ok then
		return false, reason
	end
	local session = openSessions[player]
	if session then
		session.crafted = true
	end
	Metrics.event(player, Metrics.Events.CraftExecuted, 1, recipe.id)
	QuestService.record(player, { kind = "craft", item = recipe.output })
	return true, nil
end

function CraftService.opened(player: Player): (boolean, string?)
	openSessions[player] = { crafted = false }
	return true, nil
end

local function closeSession(player: Player)
	local session = openSessions[player]
	openSessions[player] = nil
	if session and not session.crafted then
		Metrics.event(player, Metrics.Events.CraftOpenedNoCraft)
	end
end

function CraftService.closed(player: Player): (boolean, string?)
	closeSession(player)
	return true, nil
end

-- アイテムを使う（Phase 0 は回復薬だけ）
function CraftService.useItem(player: Player, itemId: any): (boolean, string?)
	local def = if type(itemId) == "string" then ItemDefs[itemId] else nil
	if def == nil or def.category ~= "consumable" then
		return false, "unknown_id"
	end
	local character = player.Character
	local humanoid = character and character:FindFirstChildOfClass("Humanoid")
	if humanoid == nil or humanoid.Health <= 0 then
		return false, "dead"
	end
	if def.combatOnly and not BattleStateService.inCombat(player) then
		return false, "item_combat_only"
	end
	if not def.ringAllowed and BattleStateService.getPvpOpponent(player) ~= nil then
		return false, "item_not_in_ring"
	end
	if humanoid.Health >= humanoid.MaxHealth then
		return false, "item_full_health"
	end
	local ok, reason = InventoryService.applyItems(player, { consume = { [def.id] = 1 } })
	if not ok then
		return false, reason
	end
	humanoid.Health = math.min(humanoid.MaxHealth, humanoid.Health + humanoid.MaxHealth * def.healRatio)
	return true, nil
end

function CraftService.init()
	Players.PlayerRemoving:Connect(closeSession)
end

return CraftService
