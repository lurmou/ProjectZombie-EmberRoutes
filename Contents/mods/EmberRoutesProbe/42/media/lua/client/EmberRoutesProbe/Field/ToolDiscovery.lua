local Custody=require 'EmberRoutesProbe/Field/ToolCustody'
-- Tool discovery service: evaluates tool availability for field candidates,
-- scanning worker inventory first, then searching settlement warehouse containers
-- with bounded budgets.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local ToolReq=require 'EmberRoutesProbe/Field/ToolRequirements'
local Membership=require 'EmberRoutesProbe/Settlement/SettlementMembership'
local Geometry=require 'EmberRoutesProbe/Settlement/SettlementGeometry'

-- Any container mutation invalidates negative supply results immediately; the
-- short call budget is only a fallback for reservation/ownership changes that
-- do not raise a container event.
local inventoryRevision=0
if Registry.inventoryListeners then
    Registry.inventoryListeners[#Registry.inventoryListeners+1]=function()
        inventoryRevision=inventoryRevision+1
    end
end

local D={}
local world,searches

D.uses=function(item) return ToolReq.uses(item) end

-- Prefer a container that can serve the whole job. When nothing is sufficient,
-- keep the best available one and let the caller surface the shortfall instead
-- of silently burning an action with zero water.
local function betterWater(item,needUses,usedItemIds,npcId)
    if not item or usedItemIds[item:getID()] then return nil end
    if not ToolReq.matchPhysical(item,'WATER_FLUID') then return nil end
    if D.uses(item)<needUses then return nil end
    if not Custody.canClaim(npcId,item:getID()) then return nil end
    return item
end

function D.findSupplies(entry,npc,kind,needUses,roleFilter)
    local root=Registry.data()
    if root~=world then world,searches=root,{} end
    if not entry or not npc or not npc.getInventory then return nil end
    local inv=npc:getInventory()
    if not inv then return nil end
    local roles=ToolReq.requiredRoles(kind)
    if #roles==0 then return {ready=true,requirements={}} end

    local npcId=EmberRoutesProbeJava and EmberRoutesProbeJava.carrierId and EmberRoutesProbeJava.carrierId(npc)
    if type(npcId)~='string' or npcId=='' then return nil end
    local requirements={}
    -- Consumers use requiredRoles order, independent of where each item is found.
    local roleIndex={}
    for i,role in ipairs(roles) do roleIndex[role]=i end
    local neededRoles={}
    local usedItemIds={}

    -- 1. Check worker inventory first
    for _,role in ipairs(roles) do
        local foundItem=nil
        if inv then
            foundItem=inv:getFirstEvalRecurse(function(i)
                if usedItemIds[i:getID()] then return false end
                if not ToolReq.matchPhysical(i,role) then return false end
                if roleFilter and not roleFilter(i,role) then return false end
                return Custody.canClaim(npcId,i:getID())
            end)
        end
        if foundItem then
            usedItemIds[foundItem:getID()]=true
            requirements[roleIndex[role]]={
                role=role,
                item=foundItem,
                inInventory=true
            }
        else
            neededRoles[#neededRoles+1]=role
        end
    end

    if #neededRoles==0 then
        return {ready=true,requirements=requirements}
    end

    -- 2. Search settlement warehouse containers for remaining roles
    local containerIds=Membership.query(entry)
    if not containerIds then return nil,'FIELD_OBSERVING',{complete=false,missingRoles=neededRoles} end
    if #containerIds==0 then return nil,'FIELD_TOOLS_UNAVAILABLE',{complete=true,missingRoles=neededRoles} end

    local key=entry.id..':'..npcId..':'..kind
    local claimsRev=Store.claimsVersion and Store.claimsVersion() or 0
    local stamp=tostring(entry.revision)..':'..tostring(inventoryRevision)..':'..tostring(claimsRev)..':'..table.concat(containerIds,'|')
    local scan=searches[key]
    if not scan or scan.stamp~=stamp then
        scan={stamp=stamp,container=1,item=0,found={},unknown=false,reserved=false}
        searches[key]=scan
    elseif scan.blocked then
        return nil,scan.blockedReason,scan.blockedDetail
    end
    -- Retain partial observations across budget slices, but revalidate originals
    -- and their endpoints before returning them as an actionable plan.
    for i=#neededRoles,1,-1 do
        local role=neededRoles[i] local req=scan.found[role]
        if req then
            local ep=Registry.resolve(req.endpoint.id,'take','local-world')
            local sq=ep and ep.object and ep.object:getSquare()
            if sq and ep.container and Registry.logistics(ep)~='EXCLUDED'
                and Geometry.inside(entry,sq:getX(),sq:getY())
                and ep.container:getItems():contains(req.item)
                and not usedItemIds[req.item:getID()] and Custody.canClaim(npcId,req.item:getID())
                and ToolReq.matchPhysical(req.item,role) then
                req.endpoint=ep requirements[roleIndex[role]]=req
                usedItemIds[req.item:getID()]=true table.remove(neededRoles,i)
            else
                scan.found[role]=nil scan.container=1 scan.item=0
            end
        end
    end

    local readBudget=500
    local readCount=0
    local unknown=scan.unknown
    local reserved=scan.reserved

    for cIdx=scan.container,#containerIds do
        local cid=containerIds[cIdx]
        if #neededRoles==0 then break end
        local endpoint=Registry.resolve(cid,'take','local-world')
        if not endpoint then unknown=true end
        if endpoint and endpoint.object and endpoint.container and Registry.logistics(endpoint)~='EXCLUDED' then
            local sq=endpoint.object:getSquare()
            if sq and Geometry.inside(entry,sq:getX(),sq:getY()) then
                local items=endpoint.container:getItems()
                local size=items:size()
                for i=scan.item,size-1 do
                    readCount=readCount+1
                    if readCount>readBudget then
                        scan.container=cIdx scan.item=i scan.unknown=unknown scan.reserved=reserved
                        return nil,'FIELD_OBSERVING',{complete=false,missingRoles=neededRoles}
                    end
                    local it=items:get(i)
                    if it and not Custody.canClaim(npcId,it:getID()) then
                        for _,role in ipairs(neededRoles) do if ToolReq.matchPhysical(it,role) then reserved=true end end
                    end
                    if it and not usedItemIds[it:getID()] and Custody.canClaim(npcId,it:getID()) then
                        for rIdx,role in ipairs(neededRoles) do
                            if ToolReq.matchPhysical(it,role) and (not roleFilter or roleFilter(it,role)) then
                                usedItemIds[it:getID()]=true
                                requirements[roleIndex[role]]={
                                    role=role,
                                    item=it,
                                    endpoint=endpoint,
                                    inInventory=false
                                }
                                scan.found[role]=requirements[roleIndex[role]]
                                table.remove(neededRoles,rIdx)
                                break
                            end
                        end
                        if #neededRoles==0 then break end
                    end
                end
            end
        end
        scan.item=0
    end

    -- If all roles satisfied, return plan; otherwise nil
    if #neededRoles>0 then
        local missing={}
        for i,role in ipairs(neededRoles) do missing[i]=role end
        scan.blocked=true
        scan.container=1 scan.item=0
        scan.blockedReason=unknown and 'FIELD_OBSERVING' or reserved and 'FIELD_TOOL_RESERVED' or 'FIELD_TOOLS_UNAVAILABLE'
        scan.blockedDetail={complete=not unknown,missingRoles=missing}
        return nil,scan.blockedReason,scan.blockedDetail
    end
    -- 3. Liquid sufficiency. One water container per job: if it cannot serve the
    -- whole target, prefer a fuller one from the worker, then from the same
    -- warehouse list (bounded). Nothing sufficient keeps the best available
    -- container and records the shortfall for the caller.
    if type(needUses)=='number' and needUses>0 then
        for idx,req in ipairs(requirements) do
            if req.role=='WATER_FLUID' and D.uses(req.item)<needUses then
                local better=inv:getFirstEvalRecurse(function(i)
                    return betterWater(i,needUses,usedItemIds,npcId)~=nil
                end)
                if better then
                    usedItemIds[better:getID()]=true
                    requirements[idx]={role='WATER_FLUID',item=better,inInventory=true}
                else
                    local betterEp,reads
                    reads=0
                    for cIdx=1,#containerIds do
                        local ep=Registry.resolve(containerIds[cIdx],'take','local-world')
                        if ep and ep.container and Registry.logistics(ep)~='EXCLUDED' then
                            local sq=ep.object and ep.object:getSquare()
                            if sq and Geometry.inside(entry,sq:getX(),sq:getY()) then
                                local items=ep.container:getItems()
                                for i=0,items:size()-1 do
                                    reads=reads+1
                                    if reads>600 then break end
                                    local candidate=betterWater(items:get(i),needUses,usedItemIds,npcId)
                                    if candidate then better=candidate betterEp=ep break end
                                end
                            end
                        end
                        if better or reads>600 then break end
                    end
                    if better then
                        usedItemIds[better:getID()]=true
                        requirements[idx]={role='WATER_FLUID',item=better,endpoint=betterEp,inInventory=false}
                    else
                        req.insufficient=needUses
                    end
                end
            end
        end
    end

    local ready=true
    for _,req in ipairs(requirements) do if not req.inInventory then ready=false end end
    return {ready=ready,requirements=requirements}
end

return D
