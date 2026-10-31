-- Tool discovery service: evaluates tool availability for field candidates,
-- scanning worker inventory first, then searching settlement warehouse containers
-- with bounded budgets.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local ToolReq=require 'EmberRoutesProbe/ToolRequirements'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'

local D={}

function D.findSupplies(entry,npc,kind)
    if not entry or not npc or not npc.getInventory then return nil end
    local inv=npc:getInventory()
    if not inv then return nil end
    local roles=ToolReq.requiredRoles(kind)
    if #roles==0 then return {ready=true,requirements={}} end

    local npcId=(npc.getDescriptor and npc:getDescriptor():getID()) or 0
    local requirements={}
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
            requirements[#requirements+1]={
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
    if not containerIds or #containerIds==0 then return nil end

    local readBudget=500
    local readCount=0

    for _,cid in ipairs(containerIds) do
        if #neededRoles==0 then break end
        local endpoint=Registry.resolve(cid,'take','local-world')
        if endpoint and endpoint.object and endpoint.container and Registry.logistics(endpoint)~='EXCLUDED' then
            local sq=endpoint.object:getSquare()
            if sq and Geometry.inside(entry,sq:getX(),sq:getY()) then
                local items=endpoint.container:getItems()
                local size=items:size()
                for i=0,size-1 do
                    readCount=readCount+1
                    if readCount>readBudget then return nil end
                    local it=items:get(i)
                    if it and not usedItemIds[it:getID()] and Store.canClaimTool(npcId,it:getID()) then
                        for rIdx,role in ipairs(neededRoles) do
                            if ToolReq.matchPhysical(it,role) then
                                usedItemIds[it:getID()]=true
                                requirements[#requirements+1]={
                                    role=role,
                                    item=it,
                                    endpoint=endpoint,
                                    inInventory=false
                                }
                                table.remove(neededRoles,rIdx)
                                break
                            end
                        end
                        if #neededRoles==0 then break end
                    end
                end
            end
        end
    end

    -- If all roles satisfied, return plan; otherwise nil
    if #neededRoles>0 then return nil end
    return {ready=allInInventory,requirements=requirements}
end

return D
