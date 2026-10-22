local Log = require "EmberRoutesProbe/Log"
local Samples = {}
local KEY = "EmberRoutesPersistenceSample"

local function index(npc)
    local items, count = {}, 0
    local function walk(container, depth)
        if depth > 16 then error("SAMPLE_INVENTORY_TOO_DEEP") end
        local list = container:getItems()
        for i = 0, list:size() - 1 do
            local item = list:get(i)
            count = count + 1
            if count > 4096 or items[item:getID()] then error("SAMPLE_INVENTORY_IDENTITY") end
            items[item:getID()] = item
            if item.getInventory and item:getInventory() then walk(item:getInventory(), depth + 1) end
        end
    end
    walk(npc:getInventory(), 0)
    return items
end

function Samples.prepare(npc, id)
    local data = npc:getModData()
    if data[KEY] then return "SAMPLE_EXISTS" end
    local sample = { npcId = id, token = id .. "/persistence-sample", pieces = {}, names = {}, ready = false }
    data[KEY] = sample -- Retain even partially created samples for explicit cleanup.
    local function add(container, kind, role, name)
        local item = container:AddItem(kind)
        if not item then error("SAMPLE_ITEM_UNAVAILABLE " .. kind) end
        sample.pieces[role] = item:getID()
        sample.names[role] = name
        item:getModData()[KEY] = sample.token
        item:setName(name)
        item:setCustomName(true)
        return item
    end
    local bag = add(npc:getInventory(), "Base.Bag_Schoolbag", "bag", getText("IGUI_EmberRoutesProbe_SampleBag"))
    local pencil = add(npc:getInventory(), "Base.Pencil", "pencil", getText("IGUI_EmberRoutesProbe_SamplePencil"))
    pencil:setCondition(math.max(1, pencil:getConditionMax() - 1))
    sample.condition = pencil:getCondition()
    local water = add(bag:getInventory(), "Base.WaterBottle", "water", getText("IGUI_EmberRoutesProbe_SampleWater"))
    if not water:getFluidContainer() then error("SAMPLE_FLUID_UNAVAILABLE") end
    sample.amount = water:getFluidContainer():getAmount()
    sample.equipped = npc:getPrimaryHandItem() == nil
    if sample.equipped then npc:setPrimaryHandItem(pencil) end
    sample.health = npc:getBodyDamage():getOverallBodyHealth()
    sample.ready = true
    Log.write("PERSISTENCE_SAMPLE", "PREPARED npc=" .. id .. " bag=" .. bag:getID()
        .. " pencil=" .. pencil:getID() .. " water=" .. water:getID() .. " health=" .. sample.health)
    return "SAMPLE_PREPARED"
end

-- Explicit test preparation only. Never called by saving, checking samples or starting work.
function Samples.recover(npc, id)
    local damage = npc:getBodyDamage()
    if not damage.RestoreToFullHealth then return "HEALTH_API_UNAVAILABLE" end
    local before = damage:getOverallBodyHealth()
    damage:RestoreToFullHealth() -- Current B42 also resets needs and clears injury/infection state.
    local after = damage:getOverallBodyHealth()
    Log.write("TEST_RECOVERY", "npc=" .. id .. " healthBefore=" .. before .. " healthAfter=" .. after)
    return after >= 95 and "TEST_HEALTH_RESTORED" or "TEST_HEALTH_RECOVERY_INCOMPLETE"
end

local function owned(npc, id)
    local sample = npc:getModData()[KEY]
    if not sample or sample.npcId ~= id then return nil, nil, "SAMPLE_ABSENT_OR_STALE" end
    if type(sample.pieces) ~= "table" or type(sample.token) ~= "string" or type(sample.names) ~= "table" then
        return nil, nil, "SAMPLE_MARKER_INVALID"
    end
    local items = index(npc)
    for _, itemId in pairs(sample.pieces) do
        if not items[itemId] or items[itemId]:getModData()[KEY] ~= sample.token then
            return nil, nil, "SAMPLE_ITEM_MISSING_OR_CHANGED"
        end
    end
    return sample, items
end

function Samples.check(npc, id)
    local sample, items, reason = owned(npc, id)
    if not sample or not items then return reason end
    if not sample.ready then return "SAMPLE_PARTIAL" end
    local bag, pencil, water = items[sample.pieces.bag], items[sample.pieces.pencil], items[sample.pieces.water]
    if not bag or not pencil or not water then return "SAMPLE_PARTIAL" end
    local failures = {}
    local function compare(field, expected, actual)
        if expected ~= actual then
            failures[#failures + 1] = field .. " expected=" .. tostring(expected) .. " actual=" .. tostring(actual)
        end
    end
    compare("bag_root", true, bag:getContainer() == npc:getInventory())
    compare("pencil_root", true, pencil:getContainer() == npc:getInventory())
    compare("water_nested", true, water:getContainer() == bag:getInventory())
    compare("pencil_condition", sample.condition, pencil:getCondition())
    -- B42 getName() returns fluid UI names and condition prefixes. getDisplayName()
    -- is the underlying name serialized by InventoryItem.save/load.
    compare("bag_name", sample.names.bag, bag:getDisplayName())
    compare("pencil_name", sample.names.pencil, pencil:getDisplayName())
    compare("water_name", sample.names.water, water:getDisplayName())
    local fluid = water:getFluidContainer()
    if not fluid or math.abs(fluid:getAmount() - sample.amount) >= 0.001 then
        failures[#failures + 1] = "water_amount expected=" .. tostring(sample.amount)
            .. " actual=" .. tostring(fluid and fluid:getAmount() or "absent")
    end
    if sample.equipped then
        local primary = npc:getPrimaryHandItem()
        compare("primary_id", pencil:getID(), primary and primary:getID() or "absent")
    end
    local result = #failures == 0 and "SAMPLE_PASSED" or "SAMPLE_FAILED"
    Log.write("PERSISTENCE_SAMPLE", result .. " npc=" .. id .. " bag=" .. bag:getID()
        .. " pencil=" .. pencil:getID() .. " water=" .. water:getID()
        .. " healthBefore=" .. sample.health .. " healthNow=" .. npc:getBodyDamage():getOverallBodyHealth()
        .. " failures=" .. #failures)
    for _, failure in ipairs(failures) do Log.write("PERSISTENCE_SAMPLE", "MISMATCH " .. failure) end
    return result
end

function Samples.cleanup(npc, id)
    local sample, items, reason = owned(npc, id)
    if not sample or not items then return reason end
    local bag = sample.pieces.bag and items[sample.pieces.bag]
    for _, slots in ipairs({ npc:getWornItems(), npc:getAttachedItems() }) do
        for i = 0, slots:size() - 1 do
            local item = slots:getItemByIndex(i)
            if item and item:getModData()[KEY] == sample.token then return "SAMPLE_CLEANUP_BLOCKED_EQUIPPED" end
        end
    end
    if bag then
        local contents = bag:getInventory():getItems()
        for i = 0, contents:size() - 1 do
            local item = contents:get(i)
            if item:getID() ~= sample.pieces.water then return "SAMPLE_CLEANUP_BLOCKED_FOREIGN_ITEM" end
        end
    end
    for _, itemId in pairs(sample.pieces) do
        local container = items[itemId]:getContainer()
        if container ~= npc:getInventory() and (not bag or container ~= bag:getInventory()) then
            return "SAMPLE_CLEANUP_BLOCKED_LOCATION"
        end
    end
    -- All checks precede removal. Only exact tracked instances may be disposed.
    for _, role in ipairs({ "water", "pencil", "bag" }) do
        local item = sample.pieces[role] and items[sample.pieces[role]]
        if item then
            if npc:getPrimaryHandItem() == item then npc:setPrimaryHandItem(nil) end
            if npc:getSecondaryHandItem() == item then npc:setSecondaryHandItem(nil) end
            item:getContainer():Remove(item)
        end
    end
    npc:getModData()[KEY] = nil
    return "SAMPLE_CLEANED"
end
return Samples
