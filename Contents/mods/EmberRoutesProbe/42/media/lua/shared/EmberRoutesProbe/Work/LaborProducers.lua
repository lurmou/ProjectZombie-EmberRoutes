-- Producer contracts extend execution policy without importing services into Work.
local Producers={handlers={}}
function Producers.register(id,handler)
    assert(type(id)=="string" and not Producers.handlers[id] and type(handler.check)=="function"
        and type(handler.transfer)=="function","PRODUCER_INVALID")
    Producers.handlers[id]=handler
end
function Producers.check(context)
    local id=context.job.producer
    if not id then return true end
    local handler=Producers.handlers[id]
    if not handler then return false,"PRODUCER_UNAVAILABLE" end
    return handler.check(context)
end
function Producers.transfer(context,item,from,to)
    local id=context.job.producer
    if not id then return true end
    local handler=Producers.handlers[id]
    return handler and handler.transfer(context,item,from,to) or false
end
function Producers.eligible(item)
    if EmberRoutesProbeJava and EmberRoutesProbeJava.workItemEligible then
        local result=EmberRoutesProbeJava.workItemEligible(item)
        if result~=nil then return result end
    end
    local data=item:getModData()
    return item:getCategory()~="Container" and not item:isEquipped() and not item:isFavorite()
        and not data.EmberRoutesHaulFixture and not data.EmberRoutesPersistenceSample and not data.EmberRoutesProbeFixture
end
function Producers.isCharacterInventory(npc, container)
    if not npc or not container then return false end
    local own = npc.getInventory and npc:getInventory()
    if container == own then return true end
    if container.isInCharacterInventory and container:isInCharacterInventory(npc) then return true end
    return false
end
function Producers.getCarryContainers(npc)
    if not npc then return {} end
    local own = npc.getInventory and npc:getInventory()
    if not own then return {} end
    local list = {{ container = own, item = nil, weightReduction = 0 }}
    local items = own.getItems and own:getItems()
    if items and items.size then
        local size = items:size()
        local bags = {}
        for i = 0, size - 1 do
            local it = items:get(i)
            if it and it.getCategory and it:getCategory() == "Container"
                and (npc.isEquipped and npc:isEquipped(it) or it.isEquipped and it:isEquipped()) then
                local bagCont = it.getItemContainer and it:getItemContainer()
                    or (it.getInventory and it:getInventory())
                if bagCont and bagCont ~= own then
                    local reduction = it.getWeightReduction and it:getWeightReduction() or 0
                    bags[#bags + 1] = { container = bagCont, item = it, weightReduction = reduction }
                end
            end
        end
        table.sort(bags, function(a, b) return a.weightReduction > b.weightReduction end)
        for _, b in ipairs(bags) do
            list[#list + 1] = b
        end
    end
    return list
end
function Producers.bestCarryContainer(npc, item)
    if not npc or not item then return nil, "INVALID_ARGUMENT" end
    local maximum, weight = npc.getMaxWeight and npc:getMaxWeight(), npc.getInventoryWeight and npc:getInventoryWeight()
    if type(maximum) ~= "number" or type(weight) ~= "number" or maximum ~= maximum or weight ~= weight
        or maximum < 0 or weight < 0 or maximum == math.huge or weight == math.huge then
        return nil, "INVALID_CHARACTER_WEIGHT"
    end
    local itemWeight = item.getActualWeight and item:getActualWeight()
        or (item.getUnequippedWeight and item:getUnequippedWeight()) or 0
    local hardLimit = maximum * 1.5 - 0.01
    local carryContainers = Producers.getCarryContainers(npc)
    for i = 2, #carryContainers do
        local entry = carryContainers[i]
        local bagCont = entry.container
        if bagCont and bagCont.hasRoomFor and bagCont:hasRoomFor(npc, item) then
            local effectiveWeight = itemWeight * (1 - (entry.weightReduction or 0) / 100)
            if weight + effectiveWeight <= hardLimit then
                return bagCont
            end
        end
    end
    local own = npc.getInventory and npc:getInventory()
    if own and own.hasRoomFor and own:hasRoomFor(npc, item) then
        if weight + itemWeight <= hardLimit then
            return own
        end
    end
    return nil, "INSUFFICIENT_CARRY_CAPACITY"
end
function Producers.hasCarryRoomFor(npc, item)
    return Producers.bestCarryContainer(npc, item) ~= nil
end
function Producers.freeCarry(npc)
    if EmberRoutesProbeJava and EmberRoutesProbeJava.workFreeCarry then return EmberRoutesProbeJava.workFreeCarry(npc) end
    local maximum,weight=npc:getMaxWeight(),npc:getInventoryWeight()
    if type(maximum)~="number" or type(weight)~="number" or maximum~=maximum or weight~=weight
        or maximum<0 or weight<0 or maximum==math.huge or weight==math.huge then return 0 end
    local own = npc.getInventory and npc:getInventory()
    local totalFree = own and own.getFreeCapacity and own:getFreeCapacity(npc) or 0
    local carry = Producers.getCarryContainers(npc)
    for i = 2, #carry do
        local bag = carry[i].container
        if bag and bag.getFreeCapacity then
            totalFree = totalFree + bag:getFreeCapacity(npc)
        end
    end
    return math.max(0,math.min(totalFree,maximum-weight))
end
return Producers
