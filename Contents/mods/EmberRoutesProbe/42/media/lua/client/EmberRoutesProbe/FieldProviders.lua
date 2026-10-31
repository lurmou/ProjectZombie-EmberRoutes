local Field=require 'EmberRoutesProbe/FieldWork'
local Discovery=require 'EmberRoutesProbe/FieldDiscovery'
local Operations=require 'EmberRoutesProbe/FieldOperations'
local Spatial=require 'EmberRoutesProbe/FieldSpatial'
local Record=require 'EmberRoutesProbe/FieldRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local ToolDiscovery=require 'EmberRoutesProbe/ToolDiscovery'
local M={}
local providers={}
local priorities={cleaning=2,farming=3,lumberjack=3,forager=3}
local function claim(category,selected,npc,entry,jobId)
    local t,keys,why=Discovery.claim(selected.point,npc,entry,category)
    if not t then return nil,nil,why end
    local supplies=ToolDiscovery.findSupplies(entry,npc,t.kind)
    if not supplies then return nil,nil,'FIELD_TOOLS_UNAVAILABLE' end
    t.tools={}
    local npcId=tostring((npc.getDescriptor and npc:getDescriptor():getID()) or 0)
    local toolSupplyReqs={}
    local createdCustodies={}
    for _,req in ipairs(supplies.requirements) do
        local itemId=req.item:getID()
        t.tools[#t.tools+1]=itemId
        if req.inInventory then
            local existing=Store.custodyByItem(itemId)
            if existing then
                if jobId then Store.assignToolUse(existing.id,jobId) end
            else
                local custody,err=Store.claimCustody(npcId,itemId,req.role,nil,jobId)
                if not custody then
                    for _,cid in ipairs(createdCustodies) do Store.releaseCustody(cid) end
                    return nil,nil,err or 'TOOL_CUSTODY_CONFLICT'
                end
                custody.state='HELD'
                createdCustodies[#createdCustodies+1]=custody.id
            end
        else
            local custody,err=Store.claimCustody(npcId,itemId,req.role,req.endpoint.id,jobId)
            if not custody then
                for _,cid in ipairs(createdCustodies) do Store.releaseCustody(cid) end
                return nil,nil,err or 'TOOL_CUSTODY_CONFLICT'
            end
            createdCustodies[#createdCustodies+1]=custody.id
            toolSupplyReqs[#toolSupplyReqs+1]={
                role=req.role,
                itemId=itemId,
                custodyId=custody.id,
                containerId=req.endpoint.id
            }
        end
    end
    t.createdCustodies=createdCustodies
    if #toolSupplyReqs>0 then
        t.toolSupply={requirements=toolSupplyReqs}
    end
    for _,item in pairs({primary=npc:getPrimaryHandItem(),secondary=npc:getSecondaryHandItem()}) do
        if not Store.custodyByItem(item:getID()) then
            local key='item:'..item:getID() local seen=false
            for _,existing in ipairs(keys) do if key==existing then seen=true break end end
            if not seen then keys[#keys+1]=key end
        end
    end
    if t.kind=='ROTTEN' then keys[#keys+1]='item:'..t.itemId end
    if t.kind=='CORPSE' then
        local zoneId=Discovery.policy(category,entry.id).corpseZoneId
        local zone=zoneId and require('EmberRoutesProbe/SettlementZones').get(zoneId)
        if not zone or not zone.enabled or zone.settlementId~=entry.id then return nil,nil,'FIELD_CORPSE_ZONE_REQUIRED' end
    end
    return t,keys
end
local function policyReady(env,category)
    if category=='lumberjack' then
        local max=Discovery.policy(category,env.entry.id).maxStoredLogs or 20
        if max>0 then local count=Discovery.logs(env.entry.id) if not count or count>=max then return false end end
        local stats=env.npc:getStats()
        if stats and stats:get(CharacterStat.ENDURANCE)<0.4 then return false end
    end
    return true
end
local function hasSupplies(entry,npc,kind)
    if ToolDiscovery and ToolDiscovery.findSupplies then
        local s=ToolDiscovery.findSupplies(entry,npc,kind)
        if s~=nil then return true end
    end
    if Operations.supplies then
        return Operations.supplies(npc,kind)~=nil
    end
    return false
end
function M.get(category)
    if providers[category] then return providers[category] end
    local def={category=category,defaultPriority=priorities[category],step=Operations.step,collect=category=='lumberjack'}
    function def.valid(c)
        local entry=c.entry
        if not entry then return false end
        -- Radius bounds discovery; an already accepted stain does not move with its worker.
        if category=='cleaning' then return require('EmberRoutesProbe/SettlementGeometry').inside(entry,c.job.payload.target.x,c.job.payload.target.y) end
        return Discovery.allowed(category,entry,c.job.payload.target,c.npc)
    end
    function def.discover(env)
        if not policyReady(env,category) then return end
        local offered=0
        for _,t in ipairs(Discovery.targets(env,category)) do
            if Discovery.allowed(category,env.entry,t,env.npc) and hasSupplies(env.entry,env.npc,t.kind) then
                if Field.offer(env,category,t,t.kind=='HARVEST' and 0.95 or 0.8) then
                    offered=offered+1 if offered>=3 then break end
                end
            end
        end
    end
    function def.claim(selected,npc,entry) return claim(category,selected,npc,entry) end
    function def.continue(c)
        local policy=Discovery.policy(category,c.job.scopeId)
        local maxBatch=policy and policy.maxContinuousBatch or (category=='lumberjack' and 4 or 8)
        if (c.job.payload.batchCount or 1)>=maxBatch
            or (policy and policy.continuousBatch==false) then return false end
        local priorities=require('EmberRoutesProbe/PublicWork').priorities(c.job.npcId)
        if priorities and (priorities[category] or 0)==0 then return false end
        local entry=require('EmberRoutesProbe/SettlementLedger').get(c.job.scopeId)
        if not entry or not policyReady({entry=entry,npc=c.npc},category) then return false end
        local previous=c.job.payload.target
        local env={entry=entry,npc=c.npc,npcId=c.job.npcId,actor=c.actor,now=getTimestampMs()}
        for _,t in ipairs(Discovery.targets(env,category)) do
            if (t.x~=previous.x or t.y~=previous.y or t.z~=previous.z) and math.abs(t.x-previous.x)<=5
                and math.abs(t.y-previous.y)<=5 and t.z==previous.z and Discovery.object(t) then
                local target,keys=claim(category,{point=t},c.npc,entry,c.job.id)
                if target then
                    local free=true
                    for _,key in ipairs(keys) do local owner=Store.resourceOwner(key)
                        if owner and owner.taskId~=c.job.id then free=false end
                    end
                    if free then return c.change(function(j)
                        j.payload.target=target j.payload.claims=keys j.payload.assets={}
                        j.payload.workDone=nil j.payload.attempt=nil j.payload.phase='WORK'
                        j.payload.batchCount=(j.payload.batchCount or 1)+1
                    end) end
                end
            end
        end
        return false
    end
    function def.destination(c,e,item)
        if c.job.payload.target.kind~='ROTTEN' then return true end
        local f=Registry.filter(e.object,e.container)
        return f and f.groups and (f.groups['scrap.compost']==true or f.groups['scrap.waste']==true or f.groups.scrap==true) or false
    end
    providers[category]=Field.provider(def)
    return providers[category]
end
return M
