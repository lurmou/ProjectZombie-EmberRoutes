-- Reuses the warehouse membership, access/filter and logistics target ranking.
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Membership=require "EmberRoutesProbe/SettlementMembership"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Sort=require "EmberRoutesProbe/SortPolicy"
local Claims=require "EmberRoutesProbe/LaborStore"
local Adapter=require "EmberRoutesProbe/CraftRecipeAdapter"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Supply={}
function Supply.entry(actor,npc,object,id,recovery)
    local M=require 'EmberRoutesProbe/MembershipService'
    local entry,reason=M.entry(EmberRoutesProbeJava.carrierId(npc),id)
    if not entry then return nil,reason end
    if not recovery and not Geometry.inside(entry,npc:getX(),npc:getY()) then return nil,"NPC_OUTSIDE_SETTLEMENT" end
    local square=object and object:getSquare()
    if object and (not square or not Geometry.inside(entry,square:getX(),square:getY())) then return nil,"SURFACE_OUTSIDE_SETTLEMENT" end
    return entry
end
function Supply.endpoint(entry,id,intent)
    local endpoint,reason=Registry.resolve(id,intent,"local-world")
    if not endpoint then return nil,reason end
    local square=endpoint.object:getSquare()
    if not square or not Geometry.inside(entry,square:getX(),square:getY()) or Registry.logistics(endpoint)=="EXCLUDED" then
        return nil,"CONTAINER_EXCLUDED_OR_OUTSIDE"
    end
    return endpoint
end
function Supply.new(entry,npc,spec,recovery)
    local ids,reason=Membership.query(entry) if not ids then return nil,reason end
    local plan={entry=entry,npc=npc,spec=spec,ids=ids,position=1,phase="TARGETS",index=Sort.index(),locations={},read=0,recovery=recovery}
    if npc:getInventory():getItems():size()>Adapter.limit then return nil,"INVENTORY_LIMIT" end
    if not recovery then
        local contents=npc:getInventory():getItems()
        for i=0,contents:size()-1 do
            local item=contents:get(i)
            if not Claims.owner(item:getID()) and spec.tool:canUseItem(item,npc) and Producers.eligible(item)
                and not item:getIsCraftingConsumed() then plan.tool=item plan.toolFromNpc=true break end
        end
    end
    function plan:step(budget)
        for _=1,budget do
            if self.phase=="TARGETS" then
                local id=self.ids[self.position]
                if not id then self.phase="ITEMS" self.position=1
                else
                    self.position=self.position+1
                    local target=Supply.endpoint(self.entry,id,"put")
                    if target and Registry.logistics(target)=="STORAGE" then
                        target.filter=Filter.copy(Registry.filter(target.object,target.container)) self.index:add(target)
                    end
                end
            else
                if not self.source then
                    local id=self.ids[self.position]
                    if not id then
                        if self.recovery or (self.material and self.tool) then return true end
                        return nil,self.material and "SHARP_KNIFE_REQUIRED" or "SMALL_HANDLE_REQUIRED"
                    end
                    self.position=self.position+1
                    local source=Supply.endpoint(self.entry,id,"take")
                    if source then
                        local size=source.container:getItems():size()
                        if size>2000 then return nil,"SOURCE_SCAN_LIMIT" end
                        self.source=source self.offset=0 self.size=size
                    end
                else
                    local source=self.source
                    if not Registry.revalidate(source,"take","local-world") or source.container:getItems():size()~=self.size then return nil,"INVENTORY_CHANGED" end
                    if self.offset>=self.size then self.source=nil
                    else
                        local item=source.container:getItems():get(self.offset) self.offset=self.offset+1 self.read=self.read+1
                        if self.read>20000 then return nil,"INVENTORY_SCAN_LIMIT" end
                        if item:getContainer()==source.container then
                            if self.recovery then
                                if item:getID()==self.recovery.materialId or item:getID()==self.recovery.toolId then
                                    if self.locations[item:getID()] then return nil,"ITEM_ID_CONFLICT" end
                                    self.locations[item:getID()]={item=item,endpoint=source}
                                end
                                for _,outputId in ipairs(self.recovery.outputIds) do
                                    if item:getID()==outputId then
                                        if self.locations[outputId] then return nil,"ITEM_ID_CONFLICT" end
                                        self.locations[outputId]={item=item,endpoint=source}
                                    end
                                end
                            elseif Registry.logistics(source)=="STORAGE" and Registry.accepts(source,item) and not Claims.owner(item:getID())
                                and Producers.eligible(item) and not item:getIsCraftingConsumed() then
                                if not self.material and item:getFullType()=="Base.SmallHandle" and self.spec.material:canUseItem(item,self.npc) then
                                    self.material,self.materialSource=item,source
                                elseif not self.tool and self.spec.tool:canUseItem(item,self.npc) then self.tool,self.toolSource=item,source end
                            end
                        end
                    end
                end
            end
        end
        return false
    end
    return plan
end
function Supply.route(plan,item,accept)
    local route={cursor=plan.index:cursor(item),best=nil}
    function route:step(budget)
        for _=1,budget do
            local target,done=self.cursor:step()
            if done then return self.best and Supply.endpoint(plan.entry,self.best.id,"put") or nil,true end
            if target then
                local current=Supply.endpoint(plan.entry,target.id,"put")
                if current and Registry.logistics(current)=="STORAGE" and Registry.accepts(current,item)
                    and (not accept or accept(current))
                    and current.container:hasRoomFor(plan.npc,item)
                    and Claims.availableCapacity(current.id,current.container:getFreeCapacity(plan.npc))>=item:getUnequippedWeight() then
                    local square=current.object:getSquare()
                    local score=Sort.specificity(Registry.filter(current.object,current.container),self.cursor.description,item)
                    local distance=(square:getX()-plan.npc:getX())^2+(square:getY()-plan.npc:getY())^2+(square:getZ()-plan.npc:getZ())^2
                    local candidate={id=current.id,specificity=score,distance=distance}
                    if score and Sort.better(candidate,self.best) then self.best=candidate end
                end
            end
        end
        return nil,false
    end
    return route
end
-- Bounded reuse of warehouse target ranking for leftovers/native empty vessels.
-- No inventory scan and no new stock or claim authority.
function Supply.returnRoute(actor,npc,scope,item,accept)
    local entry,reason=require('EmberRoutesProbe/MembershipService').entry(EmberRoutesProbeJava.carrierId(npc),scope)
    if not entry then return nil,reason end
    if not Geometry.inside(entry,npc:getX(),npc:getY()) then return nil,'NPC_OUTSIDE_SETTLEMENT' end
    local ids,why=Membership.query(entry) if not ids then return nil,why end
    local plan={entry=entry,npc=npc,index=Sort.index()}
    local position,route=1,nil
    local request={}
    function request:step(budget)
        for _=1,budget do
            if not route then
                local id=ids[position] position=position+1
                if not id then route=Supply.route(plan,item,accept)
                else
                    local target=Supply.endpoint(entry,id,'put')
                    if target and Registry.logistics(target)=='STORAGE' then
                        target.filter=Filter.copy(Registry.filter(target.object,target.container)) plan.index:add(target)
                    end
                end
            else return route:step(1) end
        end
        return nil,false
    end
    return request
end
return Supply
