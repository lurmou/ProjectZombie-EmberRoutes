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
    local data=item:getModData()
    return item:getCategory()~="Container" and not item:isEquipped() and not item:isFavorite()
        and not data.EmberRoutesHaulFixture and not data.EmberRoutesPersistenceSample and not data.EmberRoutesProbeFixture
end
function Producers.freeCarry(npc)
    local maximum,weight=npc:getMaxWeight(),npc:getInventoryWeight()
    if type(maximum)~="number" or type(weight)~="number" or maximum~=maximum or weight~=weight
        or maximum<0 or weight<0 or maximum==math.huge or weight==math.huge then return 0 end
    return math.max(0,math.min(npc:getInventory():getFreeCapacity(npc),maximum-weight))
end
return Producers
