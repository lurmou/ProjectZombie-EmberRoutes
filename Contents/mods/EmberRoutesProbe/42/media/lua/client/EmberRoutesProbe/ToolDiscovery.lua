-- Tool discovery service: evaluates tool availability for field candidates,
-- scanning worker inventory first, then searching settlement warehouse containers
-- with bounded budgets.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local ToolReq=require 'EmberRoutesProbe/ToolRequirements'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'

local D={}
local world,searches

function D.findSupplies(entry,npc,kind)
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
    local allInInventory=true
    local neededRoles={}
    local usedItemIds={}

    -- 1. Check worker inventory first
    for _,role in ipairs(roles) do
        local foundItem=nil
        if inv then
            foundItem=inv:getFirstEvalRecurse(function(i)
                if usedItemIds[i:getID()] then return false end
                return Store.canClaimTool(npcId,i:getID()) and ToolReq.matchPhysical(i,role)
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
            allInInventory=false
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
    local stamp=tostring(entry.revision)..':'..table.concat(containerIds,'|')
    local scan=searches[key]
    if not scan or scan.stamp~=stamp then
        scan={stamp=stamp,container=1,item=0,found={},unknown=false,reserved=false}
        searches[key]=scan
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
                and not usedItemIds[req.item:getID()] and Store.canClaimTool(npcId,req.item:getID())
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
                    if it and not Store.canClaimTool(npcId,it:getID()) then
                        for _,role in ipairs(neededRoles) do if ToolReq.matchPhysical(it,role) then reserved=true end end
                    end
                    if it and not usedItemIds[it:getID()] and Store.canClaimTool(npcId,it:getID()) then
                        for rIdx,role in ipairs(neededRoles) do
                            if ToolReq.matchPhysical(it,role) then
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
        searches[key]=nil
        return nil,unknown and 'FIELD_OBSERVING' or reserved and 'FIELD_TOOL_RESERVED' or 'FIELD_TOOLS_UNAVAILABLE',
            {complete=not unknown,missingRoles=neededRoles}
    end
    return {ready=allInInventory,requirements=requirements}
end

return D
