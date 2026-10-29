local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Resources={}
function Resources.eligible(item,kind)
    if not item or not item.getID or item:getIsCraftingConsumed() then return false end
    local data=item.getModData and item:getModData()
    if data and (data.EmberRoutesHaulFixture or data.EmberRoutesPersistenceSample or data.EmberRoutesProbeFixture) then return false end
    if kind=='EAT' then
        if not instanceof(item,'Food') or not item.getBaseHunger or item:getBaseHunger()>=0
            or item:getHungChange()>=-0.001 or item:isRotten() or item:isPoison() or item:getPoisonPower()>0
            or item:isbDangerousUncooked() and not item:isCooked() then return false end
        local food=require('EmberRoutesProbe/CookingFood').read(item)
        if not food or not food.safe or food.frozen or food.meal and food.needsHeat then return false end
        local required=item:getRequireInHandOrInventory()
        if required and required:size()>0 then return false end -- No implicit ignition/tool consumption.
        return true
    elseif kind=='DRINK' then
        local fluid=item:getFluidContainer()
        return fluid and Fluid and Fluid.Water and fluid:isPureFluid(Fluid.Water) and fluid:getAmount()>0.001 or false
    elseif kind=='STUDY' then
        return require('EmberRoutesProbe/LibraryIndex').eligible(item)
    end
    return false
end
-- Cursor includes container discoveries and item visits, shared by the caller's
-- global scan budget. Native handles live only here, never in persisted payloads.
function Resources.new(actor,npc,kind,personalOnly,wanted,sourceId,ownerId)
    local inventory=npc:getInventory()
    local request={frames={{container=inventory,offset=0,size=inventory:getItems():size(),depth=0}},
        visited={},containers=1,total=0,position=1,kind=kind,wanted=wanted,sourceId=sourceId}
    local ownOnly=personalOnly
    function request:step(budget)
        for _=1,budget do
            self.total=self.total+1
            if self.total>20000 then return nil,true,'RESOURCE_SCAN_LIMIT' end
            local frame=self.frames[#self.frames]
            if frame then
                local items=frame.container:getItems()
                if items:size()~=frame.size then return nil,true,'INVENTORY_CHANGED' end
                if frame.offset>=frame.size then self.frames[#self.frames]=nil
                else
                    local item=items:get(frame.offset) frame.offset=frame.offset+1
                    if item:getContainer()==frame.container then
                        local owner=Store.owner(item:getID())
                        if (not self.wanted or item:getID()==self.wanted) and (not owner or owner.taskId==ownerId)
                            and (kind=='CUSTODY' and self.wanted or Resources.eligible(item,kind))
                            and (not frame.endpoint or Registry.accepts(frame.endpoint,item)) then
                            return {item=item,id=item:getID(),container=frame.container,endpoint=frame.endpoint,
                                npc=npc,entry=self.entry},true
                        end
                        if not frame.endpoint and instanceof(item,'InventoryContainer') and frame.depth<3
                            and self.containers<16 and not self.visited[item:getID()] then
                            self.visited[item:getID()]=true self.containers=self.containers+1
                            local bag=item:getInventory()
                            self.frames[#self.frames+1]={container=bag,offset=0,size=bag:getItems():size(),depth=frame.depth+1}
                        end
                    end
                end
            elseif ownOnly then return nil,true,'PERSONAL_RESOURCE_UNAVAILABLE'
            elseif not self.ids then
                local M=require 'EmberRoutesProbe/MembershipService'
                local npcId=EmberRoutesProbeJava.carrierId(npc)
                if kind=='CUSTODY' and self.sourceId then
                    self.entry=M.entry(npcId)
                else
                    local eligibility=M.check(npcId,'SELF_CARE',{x=npc:getX(),y=npc:getY(),z=npc:getZ()})
                    if not eligibility.allowed or not eligibility.sharedResources then return nil,true,'PERSONAL_RESOURCE_UNAVAILABLE' end
                    self.entry=M.entry(npcId)
                end
                if not self.entry then return nil,true,'TARGET_LOST' end
                if self.sourceId then self.ids={self.sourceId}
                else
                    local ids,reason=require('EmberRoutesProbe/SettlementMembership').query(self.entry)
                    if not ids then return nil,true,reason end self.ids=ids
                end
            else
                local id=self.ids[self.position]
                if not id then return nil,true,self.unknown and 'RESOURCE_UNLOADED' or 'RESOURCE_UNAVAILABLE' end
                self.position=self.position+1
                local endpoint,reason=Supply.endpoint(self.entry,id,'take')
                if not endpoint then
                    if reason=='CONTAINER_UNLOADED' then self.unknown=true end
                elseif Registry.logistics(endpoint)=='STORAGE' then
                    self.frames[1]={container=endpoint.container,endpoint=endpoint,offset=0,
                        size=endpoint.container:getItems():size(),depth=0}
                end
            end
        end
        return nil,false
    end
    return request
end
function Resources.revalidate(candidate,kind,ownerId)
    local owner=Store.owner(candidate.id)
    if candidate.item:getID()~=candidate.id or candidate.item:getContainer()~=candidate.container
        or owner and owner.taskId~=ownerId or not Resources.eligible(candidate.item,kind) then return false end
    if candidate.endpoint then
        return Registry.revalidate(candidate.endpoint,'take','local-world')~=nil
            and Registry.logistics(candidate.endpoint)=='STORAGE' and Registry.accepts(candidate.endpoint,candidate.item)
            and require('EmberRoutesProbe/SettlementGeometry').inside(candidate.entry,candidate.npc:getX(),candidate.npc:getY())
    end
    return candidate.container==candidate.npc:getInventory()
        or candidate.container.isInCharacterInventory and candidate.container:isInCharacterInventory(candidate.npc) or false
end
return Resources
