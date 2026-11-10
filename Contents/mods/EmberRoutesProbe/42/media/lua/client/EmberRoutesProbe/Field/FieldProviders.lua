local Field=require 'EmberRoutesProbe/Field/FieldWork'
local Discovery=require 'EmberRoutesProbe/Field/FieldDiscovery'
local Operations=require 'EmberRoutesProbe/Field/FieldOperations'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local ToolDiscovery=require 'EmberRoutesProbe/Field/ToolDiscovery'
local ToolReq=require 'EmberRoutesProbe/Field/ToolRequirements'
local RuntimeMetrics=require 'EmberRoutesProbe/Kernel/RuntimeMetrics'
local Constants=require 'EmberRoutesProbe/Kernel/Constants'
local function tick() return RuntimeMetrics.active() and RuntimeMetrics.now() or nil end
local function span(name,started) if started then RuntimeMetrics.measureSpan(name,started) end end
local M={}
local providers={}
-- Category default priorities live only on the PublicWork-facing provider
-- shims (CleaningProvider etc.); nothing in the composition layer restates
-- them, so the two copies cannot drift apart.
local function corpseZoneReady(category,entry)
    local zoneId=Discovery.policy(category,entry.id).corpseZoneId
    local zone=zoneId and require('EmberRoutesProbe/Settlement/SettlementZones').get(zoneId)
    return zone and zone.enabled and zone.settlementId==entry.id or false
end
local function claim(category,selected,npc,entry,jobId)
    local npcId= (EmberRoutesProbeJava and EmberRoutesProbeJava.carrierId and EmberRoutesProbeJava.carrierId(npc))
    local t,keys,why=Discovery.claim(selected.point,npc,entry,category)
    if not t then return nil,nil,why end
    if t.kind=='CORPSE' then
        if not corpseZoneReady(category,entry) then return nil,nil,'FIELD_CORPSE_ZONE_REQUIRED' end
        local hands={npc:getPrimaryHandItem(),npc:getSecondaryHandItem()}
        for _,item in ipairs(hands) do
            if item then
                local id=item:getID()
                local owner=Store.owner(id)
                local allowed=not owner or (npcId and Store.canClaimTool(npcId,id))
                if not allowed then return nil,nil,'FIELD_HANDS_OCCUPIED' end
            end
        end
    end
    -- CURE must pick the spray that matches this plant's disease, not any spray.
    local filter=t.kind=='CURE' and t.disease and function(i)
        return ToolReq.cureType(i)==t.disease
    end or nil
    local supplies=ToolDiscovery.findSupplies(entry,npc,t.kind,t.needUses,filter)
    if not supplies then return nil,nil,'FIELD_TOOLS_UNAVAILABLE' end
    t.tools={}
    npcId=npcId or (EmberRoutesProbeJava and EmberRoutesProbeJava.carrierId and EmberRoutesProbeJava.carrierId(npc))
    if type(npcId)~='string' or npcId=='' then return nil end
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
    -- Record a real water shortfall after selection, so the worker reports it
    -- instead of starting an action that can only do zero uses.
    if t.kind=='WATER' and type(t.needUses)=='number' and t.needUses>0 then
        for _,req in ipairs(supplies.requirements) do
            if req.role=='WATER_FLUID' then
                local have=ToolDiscovery.uses(req.item)
                if have<t.needUses then
                    t.liquid={needUses=t.needUses,haveUses=have,itemId=req.item:getID(),short=true}
                end
            end
        end
    end
    for _,item in pairs({primary=npc:getPrimaryHandItem(),secondary=npc:getSecondaryHandItem()}) do
        if not Store.custodyByItem(item:getID()) then
            local key='item:'..item:getID() local seen=false
            for _,existing in ipairs(keys) do if key==existing then seen=true break end end
            if not seen then keys[#keys+1]=key end
        end
    end
    if t.kind=='ROTTEN' then keys[#keys+1]='item:'..t.itemId end
    return t,keys
end
local function sameSource(a,b)
    return a.kind==b.kind and a.identity==b.identity and a.itemId==b.itemId and a.iconId==b.iconId
	and a.x==b.x and a.y==b.y and a.z==b.z
end
local function rollbackNewTools(c,target)
    local released=true
    for _,id in ipairs(target.createdCustodies or {}) do
	if not Store.releaseCustody(id) then released=false end
    end
    if not released then c.unknown('FIELD_TOOL_ROLLBACK_UNCONFIRMED') end
    return released
end
local function policyReady(env,category)
    if category=='lumberjack' then
        local max=Discovery.policy(category,env.entry.id).maxStoredLogs or 20
        if max>0 then local count=Discovery.logs(env.entry.id) if not count or count>=max then return false end end
        local stats=env.npc:getStats()
        if stats and stats:get(CharacterStat.ENDURANCE)<Constants.Needs.FIELD_MIN_ENDURANCE then return false end
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
    local def={category=category,step=Operations.step,collect=category=='lumberjack'}
    function def.valid(c)
        local entry=c.entry
        if not entry then return false end
        -- Radius bounds discovery; an already accepted stain does not move with its worker.
        if category=='cleaning' then
            local p=c.job.payload local t=p.target
            if require('EmberRoutesProbe/Settlement/SettlementGeometry').inside(entry,t.x,t.y) then return true end
            -- Actual corpse delivery changes target coordinates to the dump site.
            -- Finishing that proven delivery must not fail the source-area guard.
            if t.kind=='CORPSE' and p.workDone==true and not p.holding then
                local Zones=require 'EmberRoutesProbe/Settlement/SettlementZones'
                local zone=Zones.get(Discovery.policy(category,c.job.scopeId).corpseZoneId)
                return zone and zone.enabled and zone.settlementId==c.job.scopeId
                    and Zones.contains(zone,t.x,t.y,t.z) or false
            end
            return false
        end
        return Discovery.allowed(category,entry,c.job.payload.target,c.npc)
    end
    function def.discover(env)
        if not policyReady(env,category) then return end
        -- Tool availability depends on settlement, worker and target kind, not
        -- on the individual target. Resolving it once per discovery pass avoids
        -- repeating the bounded 500-read warehouse scan for all 64 candidates.
        local supplyCache={}
        local function suppliesFor(kind)
            local ok=supplyCache[kind]
            if ok==nil then
                local t0=tick()
                ok=hasSupplies(env.entry,env.npc,kind) and true or false
                span('PublicWork.discover.supplies',t0)
                supplyCache[kind]=ok
            end
            return ok
        end
        local offered=0
        for _,t in ipairs(Discovery.targets(env,category)) do
            -- Corpse offers without a usable dump zone can only fail at claim
            -- time; do not generate them in the first place.
            if (t.kind~='CORPSE' or corpseZoneReady(category,env.entry))
                and Discovery.allowed(category,env.entry,t,env.npc) and suppliesFor(t.kind) then
                local t0=tick()
                local accepted=Field.offer(env,category,t,t.kind=='HARVEST' and 0.95 or 0.8)
                span('PublicWork.discover.offer',t0)
                if accepted then offered=offered+1 if offered>=3 then break end end
            end
        end
    end
    function def.claim(selected,npc,entry) return claim(category,selected,npc,entry) end
    function def.continue(c)
	local p=c.job.payload local a=p.attempt
	if c.job.effects~='KNOWN' or p.workDone~=true or p.holding or p.capacity or p.toolSupply or #p.assets>=96
	    or a and a.state~='APPLIED' and a.state~='ABORTED' then return false end
        local policy=Discovery.policy(category,c.job.scopeId)
        local maxBatch=policy and policy.maxContinuousBatch or (category=='lumberjack' and 4 or 8)
        if (c.job.payload.batchCount or 1)>=maxBatch
            or (policy and policy.continuousBatch==false) then return false end
        local priorities=require('EmberRoutesProbe/Work/OrderQuery').priorities(c.job.npcId)
        if priorities and (priorities[category] or 0)==0 then return false end
        local entry=require('EmberRoutesProbe/Settlement/SettlementLedger').get(c.job.scopeId)
        if not entry or not policyReady({entry=entry,npc=c.npc},category) then return false end
        local previous=c.job.payload.target
        local env={entry=entry,npc=c.npc,npcId=c.job.npcId,actor=c.actor,now=getTimestampMs()}
        for _,t in ipairs(Discovery.targets(env,category)) do
	    if math.abs(t.x-previous.x)<=5 and math.abs(t.y-previous.y)<=5 and t.z==previous.z then
                local target,keys=claim(category,{point=t},c.npc,entry,c.job.id)
                if target then
		    local free=not sameSource(previous,target)
                    for _,key in ipairs(keys) do local owner=Store.resourceOwner(key)
                        if owner and owner.taskId~=c.job.id then free=false end
                    end
		    if free then
			local changed=c.change(function(j)
			    local kept,seen={},{}
			    for _,key in ipairs(j.payload.claims) do
				if string.sub(key,1,13)~='field-target:' then kept[#kept+1]=key seen[key]=true end
			    end
			    for _,key in ipairs(keys) do
				if not seen[key] then kept[#kept+1]=key seen[key]=true end
			    end
			    j.payload.target=target j.payload.claims=kept
			    j.payload.workDone=nil j.payload.attempt=nil j.payload.spotted=nil
			    j.payload.toolSupply=target.toolSupply
			    j.payload.phase=(target.toolSupply or target.liquid) and 'PREPARE' or 'WORK'
			    j.payload.batchCount=(j.payload.batchCount or 1)+1
			end)
			if changed then return true end
			rollbackNewTools(c,target)
			return false
		    end
		    if not rollbackNewTools(c,target) then return false end
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
