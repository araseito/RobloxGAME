--!strict
-- 装備（武器 1・防具 1）。装備すると付与上限が +1（ItemDefs の capacityBonus）。
-- 外すと上限が下がるので、今の付与が新しい上限を超える場合は外せない（先に付与を減らしてもらう）。

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared:WaitForChild("Config"))
local AbilityDefs = require(Shared:WaitForChild("AbilityDefs"))
local ItemDefs = require(Shared:WaitForChild("ItemDefs"))
local GrantLogic = require(Shared:WaitForChild("Logic"):WaitForChild("GrantLogic"))

local DataService = require(script.Parent.DataService)
local GrantService = require(script.Parent.GrantService)
local StateSync = require(script.Parent.StateSync)

local EquipmentService = {}

local SLOTS = { weapon = true, armor = true }

local hooks = {
	onChanged = nil :: ((Player) -> ())?,
}

function EquipmentService.setHooks(newHooks: any)
	hooks.onChanged = newHooks.onChanged
end

local function changed(player: Player)
	GrantService.refreshEffects(player)
	StateSync.push(player, "equipped")
	if hooks.onChanged then
		hooks.onChanged(player)
	end
end

function EquipmentService.equip(player: Player, itemId: any): (boolean, string?)
	if type(itemId) ~= "string" then
		return false, "bad_item"
	end
	local def = ItemDefs[itemId]
	if def == nil or not SLOTS[def.category] then
		return false, "not_equipment"
	end
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	if (profile.items[itemId] or 0) < 1 then
		return false, "not_owned"
	end
	if profile.equipped[def.category] == itemId then
		return false, "already_equipped"
	end
	-- 別の装備から付け替えると上限が下がる場合に備えて確かめる（Phase 0 は各枠 1 種類なので通常は起きない）
	local newEquipped = table.clone(profile.equipped)
	newEquipped[def.category] = itemId
	local newCapacity = GrantLogic.capacity(Config.Grant.BaseCapacity, newEquipped, ItemDefs)
	if GrantLogic.used(GrantService.list(player), AbilityDefs) > newCapacity then
		return false, "capacity_exceeded"
	end
	profile.equipped = newEquipped
	changed(player)
	return true, nil
end

function EquipmentService.unequip(player: Player, slot: any): (boolean, string?)
	if type(slot) ~= "string" or not SLOTS[slot] then
		return false, "bad_slot"
	end
	local profile = DataService.getProfile(player)
	if profile == nil then
		return false, "not_loaded"
	end
	if profile.equipped[slot] == nil then
		return false, "not_equipped"
	end
	local newEquipped = table.clone(profile.equipped)
	newEquipped[slot] = nil
	local newCapacity = GrantLogic.capacity(Config.Grant.BaseCapacity, newEquipped, ItemDefs)
	if GrantLogic.used(GrantService.list(player), AbilityDefs) > newCapacity then
		return false, "capacity_exceeded"
	end
	profile.equipped = newEquipped
	changed(player)
	return true, nil
end

-- 読み込み時：持っていない装備が装備中になっていたら外す
function EquipmentService.validate(player: Player)
	local profile = DataService.getProfile(player)
	if profile == nil then
		return
	end
	local fixed = false
	for slot, itemId in table.clone(profile.equipped) do
		local def = ItemDefs[itemId]
		if not SLOTS[slot] or def == nil or def.category ~= slot or (profile.items[itemId] or 0) < 1 then
			profile.equipped[slot] = nil
			fixed = true
		end
	end
	if fixed then
		changed(player)
	end
end

return EquipmentService
