-- Reuses the warehouse membership, access/filter and logistics target ranking.
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"
local Membership=require "EmberRoutesProbe/Settlement/SettlementMembership"
local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
local Sort=require "EmberRoutesProbe/Warehouse/SortPolicy"
local Claims=require "EmberRoutesProbe/Work/LaborStore"
local Supply={}
function Supply.entry(actor,npc,object,id,recovery)
    local M=require 'EmberRoutesProbe/Settlement/MembershipService'
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
function Supply.returnRoute(actor,npc,scope,item,accept,options)
    local entry,reason=require('EmberRoutesProbe/Settlement/MembershipService').entry(EmberRoutesProbeJava.carrierId(npc),scope)
    if not entry then return nil,reason end
    if not Geometry.inside(entry,npc:getX(),npc:getY()) and not (options and options.allowOutside==true) then return nil,'NPC_OUTSIDE_SETTLEMENT' end
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
