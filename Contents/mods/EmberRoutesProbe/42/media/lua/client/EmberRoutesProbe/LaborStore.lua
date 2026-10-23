local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Claims=require "EmberRoutesProbe/LaborClaims"
local CraftRecord=require "EmberRoutesProbe/CraftRecord"
local Store={}
local root,ledger,claims,tokens
local nativeTokens={}
local recent={}
local function resources(record)
    local result={} for _,id in ipairs(record.items) do result[#result+1]="item:"..id end return result
end
function Store.data()
    local current=Registry.data()
    if current~=root then
        local data=require('EmberRoutesProbe/BusinessJobs').hauls()
        local rebuilt,newTokens=Claims.new(),{}
        for id,record in pairs(data.tasks) do
            if type(record)~="table" or type(id)~="string" or record.id~=id or type(record.npcId)~="string"
                or (record.state~='DONE' and data.byNpc[record.npcId]~=id) or record.format~=1 or record.kind~="EXPLICIT_TRANSFER"
                or record.executor~="ENTITY" or record.scopeId~="local-world" or type(record.items)~="table"
                or #record.items>30 or (record.state~="RUNNING" and record.state~="PAUSED" and record.state~="DONE")
                or (record.generation and (type(record.generation)~="number" or record.generation<0
                    or record.generation~=math.floor(record.generation) or record.generation==math.huge)) then error("TASK_RECORD_INVALID") end
            for _,itemId in ipairs(record.items) do
                if type(itemId)~="number" or itemId~=itemId or itemId==math.huge or itemId==-math.huge then error("TASK_ITEM_INVALID") end
            end
            if record.state~="DONE" then
                local token=rebuilt:acquire(id,(record.generation or 0)+1,resources(record))
                if not token then error("TASK_CLAIM_CONFLICT") end newTokens[id]=token
                local r=record.reservation
                if r then
                    if type(r)~="table" then error("TASK_RESERVATION_INVALID") end
                    if r.format==2 and type(r.items)=="table" then
                        for itemId,amount in pairs(r.items) do
                            if not rebuilt:restore(token,r.key,itemId,amount) then error("TASK_RESERVATION_INVALID") end
                        end
                    elseif r.format~=nil or not rebuilt:restore(token,r.key,r.itemId,r.amount) then error("TASK_RESERVATION_INVALID") end
                end
            end
        end
        for npcId,id in pairs(data.byNpc) do
            if not data.tasks[id] or data.tasks[id].npcId~=npcId then error("TASK_INDEX_INVALID") end
        end
        local rebuiltNative={}
        for npcId,record in pairs(CraftRecord.records(current)) do
            if not record.released then
                local other=data.tasks[data.byNpc[npcId]]
                if other and other.state~="DONE" then error("NPC_TASK_CONFLICT") end
                local token=rebuilt:acquire(record.id,record.generation,CraftRecord.resources(record))
                if not token or newTokens[record.id] or rebuiltNative[record.id] then error("CRAFT_CLAIM_CONFLICT") end
                rebuiltNative[record.id]=token
            end
        end
        -- Publish the cache only after the entire ledger passed validation.
        for _,record in pairs(data.tasks) do
            record.generation=(record.generation or 0)+1
            if record.state=="RUNNING" then record.state="PAUSED" record.reason="LOAD_RECOVERY" end
        end
        require('EmberRoutesProbe/BusinessJobs').flush()
        root,ledger,claims,tokens=current,data,rebuilt,newTokens
        nativeTokens=rebuiltNative
        recent={}
    end
    return ledger
end
function Store.record(npcId)
    local data=Store.data() return data.tasks[data.byNpc[npcId]]
end
-- One UI summary per current NPC, scoped to this world session; no item handles.
function Store.recent(npcId)
    Store.data()
    local saved=recent[npcId]
    if not saved then return nil end
    local copy={} for key,value in pairs(saved) do copy[key]=value end return copy
end
function Store.owner(itemId) Store.data() return claims.owners["item:"..itemId] end
function Store.claimNative(record)
    Store.data()
    if not CraftRecord.valid(record.npcId,record) or record.released then return nil,"CRAFT_RECORD_INVALID" end
    local other=Store.record(record.npcId)
    if other and other.state~="DONE" then return nil,"NPC_TASK_CONFLICT" end
    local saved=CraftRecord.records(root)[record.npcId]
    if saved and saved~=record and not saved.released then return nil,"OTHER_TASK_RETAINED" end
    if ledger.tasks[record.id] then return nil,"TASK_ID_DUPLICATED" end
    for _,otherRecord in pairs(CraftRecord.records(root)) do
        if otherRecord~=record and otherRecord.id==record.id then return nil,"TASK_ID_DUPLICATED" end
    end
    local token,reason=claims:acquire(record.id,record.generation,CraftRecord.resources(record))
    if token then nativeTokens[record.id]=token end
    return token,reason
end
function Store.validNative(record,token,key)
    Store.data()
    return nativeTokens[record.id]==token and token and token.generation==record.generation
        and CraftRecord.records(root)[record.npcId]==record and not record.released
        and (not key or claims:valid(token,key))
end
function Store.extendNative(record,token)
    Store.data()
    -- An already committed native result still belongs to its paused owner.
    -- This only records originals; it never authorizes a stale physical action.
    if nativeTokens[record.id]~=token or CraftRecord.records(root)[record.npcId]~=record
        or record.released then return false,"STALE_CLAIM" end
    return claims:extend(token,CraftRecord.resources(record))
end
function Store.finishNative(record)
    Store.data() claims:release(nativeTokens[record.id]) nativeTokens[record.id]=nil
end
function Store.replaceNative(record,token,proposed)
    Store.data()
    if not Store.validNative(record,token) or proposed.id~=record.id or proposed.generation~=record.generation
        or proposed.npcId~=record.npcId or not CraftRecord.valid(record.npcId,proposed) then return false,"STALE_CLAIM" end
    local ok,reason=claims:replace(token,CraftRecord.resources(proposed))
    if not ok then return false,reason end
    record.materials,record.tools,record.outputs=proposed.materials,proposed.tools,proposed.outputs
    record.held=proposed.held
    return true
end
function Store.claim(record)
    Store.data()
    local native=CraftRecord.records(root)[record.npcId]
    if native and not native.released then return nil,"OTHER_TASK_RETAINED" end
    local generation=(record.generation or 0)+1
    local token,reason=claims:acquire(record.id,generation,resources(record))
    if token then record.generation=generation tokens[record.id]=token end
    return token,reason
end
function Store.publish(record)
    local data=Store.data() local previous=Store.record(record.npcId)
    local native=CraftRecord.records(root)[record.npcId]
    if native and not native.released then return false,"OTHER_TASK_RETAINED" end
    if previous and previous~=record then
        if previous.state~="DONE" then return false,"TASK_EXISTS_RESUME_OR_CLEAR" end
        claims:release(tokens[previous.id]) tokens[previous.id]=nil
    end
    return require('EmberRoutesProbe/BusinessJobs').publishHaul(record)
end
function Store.valid(record,generation,token)
    return Store.record(record.npcId)==record and record.state=="RUNNING" and record.generation==generation
        and tokens[record.id]==token
end
function Store.pause(record)
    local token=Store.claim(record) return token
end
function Store.capacity(token,itemId,key,amount,free)
    Store.data() local ok,reason=claims:reserve(token,key,itemId,amount,free)
    if ok then
        local record=ledger.tasks[token.taskId] local previous=record.reservation
        local reservation=previous and previous.format==2 and previous or {format=2,key=key,items={}}
        if previous and previous.itemId then reservation.items[previous.itemId]=previous.amount end
        reservation.items[itemId]=amount record.reservation=reservation
    end
    return ok,reason
end
function Store.releaseCapacity(token,itemId)
    Store.data() if not token then return end
    claims:releaseCapacity(token,itemId)
    local record=ledger.tasks[token.taskId]
    if record and tokens[token.taskId]==token then
        local reservation=record.reservation
        if not itemId then record.reservation=nil
        elseif reservation and reservation.format==2 then
            reservation.items[itemId]=nil
            local empty=true for _ in pairs(reservation.items) do empty=false break end
            if empty then record.reservation=nil end
        elseif reservation and reservation.itemId==itemId then record.reservation=nil end
    end
end
function Store.availableCapacity(key,free) Store.data() return claims:available(key,free) end
function Store.availableFor(token,key,itemId,free) Store.data() return claims:availableFor(token,key,itemId,free) end
function Store.capacityBatch(token,key,weights,free)
    Store.data() local ok,reason=claims:reserveMany(token,key,weights,free)
    if ok then
        local copy={} for id,amount in pairs(weights) do copy[id]=amount end
        ledger.tasks[token.taskId].reservation={format=2,key=key,items=copy}
    end
    return ok,reason
end
function Store.finish(record)
    Store.data()
    if record.state=="DONE" and record.producer=="LOGISTICS" and record.delivered==#record.items then
        recent[record.npcId]={id=record.id,settlementId=record.settlementId,sourceMode=record.sourceMode,
            delivered=record.delivered,total=#record.items}
    end
    claims:release(tokens[record.id]) tokens[record.id]=nil record.reservation=nil record.generation=(record.generation or 0)+1
end
function Store.clear(npcId)
    local record=Store.record(npcId) if not record then return end
    Store.finish(record) record.state='DONE' record.reason='CLEARED'
    require('EmberRoutesProbe/BusinessJobs').removeHaul(record)
    require('EmberRoutesProbe/BusinessJobs').flush()
    recent[npcId]=nil
end
function Store.route(npcId)
    local data=Store.data() local route=data.routes[npcId]
    if not route then
        route={}
        if npcId~="" then
            route=data.unassignedRoute or data.routes[""] or route
            data.unassignedRoute=nil data.routes[""]=nil
        end
        data.routes[npcId]=route
    end
    return route
end
return Store
