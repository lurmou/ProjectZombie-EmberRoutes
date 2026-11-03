-- Real matching/ranking/allocation and native-transfer adapter, fake world/effects.
local n=0 local function check(v,m) n=n+1 assert(v,m) end
local function container(cap)
    local c={items={},capacity=cap}
    function c:getItems() return {size=function() return #c.items end,get=function(_,i) return c.items[i+1] end,
        contains=function(_,item) for _,v in ipairs(c.items) do if v==item then return true end end return false end} end
    function c:getFreeCapacity() return c.capacity-#c.items end
    function c:hasRoomFor() return self:getFreeCapacity()>=1 end
    return c
end
local function item(id,kind,c)
    local i={id=id,kind=kind,container=c}
    function i:getID() return self.id end function i:getFullType() return self.kind end
    function i:getContainer() return self.container end function i:getUnequippedWeight() return 1 end
    function i:getCategory() return 'Material' end function i:getIsCraftingConsumed() return false end
    c.items[#c.items+1]=i return i
end
local root=container(100) local npc={getInventory=function() return root end,getX=function() return 0 end,
    getY=function() return 0 end,getZ=function() return 0 end}
local endpoints={} local ids={'S1','S2','D1','D2'}
for x,id in ipairs(ids) do
    local c=container(id=='D1' and 2 or id=='D2' and 3 or 100)
    endpoints[id]={id=id,container=c,object={getSquare=function() return {getX=function() return x end,getY=function() return 0 end,getZ=function() return 0 end} end},
        filter={format=1,enabled=true,private=false,types={['Base.Plank']=id=='D1' or id=='D2',['Base.Log']=id=='S1' or id=='S2'},groups={}}}
end
local Registry={resolve=function(id) return endpoints[id] end,revalidate=function() return true end,
    logistics=function() return 'STORAGE' end,filter=function(o,c) for _,e in pairs(endpoints) do if e.container==c then return e.filter end end end,
    accepts=function(e,i) return e.filter.types[i:getFullType()]==true end,inventoryChanged=function() end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return ids end}
local owners={}
package.loaded['EmberRoutesProbe/LaborStore']={owner=function(id) return owners[id] end,availableCapacity=function(_,free) return free end}
package.loaded['EmberRoutesProbe/LaborProducers']={eligible=function() return true end}
local first=item(1,'Base.Log',endpoints.S1.container) local second=item(2,'Base.Log',endpoints.S2.container)
item(3,'Base.Log',root) -- unrelated carried material is never source stock
local Plan=require 'EmberRoutesProbe/ProductionSupply'
local record={id='job',requested=4,target=6,produced=6,delivered=0,materials={},tools={},outputs={}}
local spec={inputs={{slot=0,count=2,keep=false,io={canUseItem=function(_,i) return i.kind=='Base.Log' end}}}}
local plan=assert(Plan.new({id='s'},npc,spec,record,true)) local ready,why
for _=1,100 do ready,why=plan:step(32) if ready or why then break end end
check(ready and #plan.materials==2,'one batch matches two distinct source boxes')
check(plan.materials[1].id~=3 and plan.materials[2].id~=3,'NPC-carried material excluded from fresh source stock')
check(plan.locations[first.id].endpoint.id~=plan.locations[second.id].endpoint.id,'matching preserves each actual source')
local Allocation=require 'EmberRoutesProbe/ProductionAllocation'
local Routing=require 'EmberRoutesProbe/ProductionRouting'
local c={record=record,npc=npc,entry={id='s'},plan=plan,valid=function() return true end,changed=function() end}
for id=11,16 do local i=item(id,'Base.Plank',root) local a={id=id,fullType=i.kind,delivered=false}
    record.outputs[#record.outputs+1]=a plan.locations[id]={item=i} Allocation.row(record,a) end
local routing=Routing.new(c)
for _=1,100 do if routing:step(8) then break end end
local allocated,settled,remaining=Allocation.count(record,'Base.Plank')
check(allocated==5 and settled==0 and remaining==6 and record.target==6 and record.requested==4,'capacity shortage retains rounded target and all unsettled quantity')
local targetCounts={}
for _,row in ipairs(record.outputAllocation.assets) do if row.targets[1] then local id=row.targets[1].destinationId targetCounts[id]=(targetCounts[id] or 0)+1 end end
check(targetCounts.D1==2 and targetCounts.D2==3,'ranked targets split without virtual overfill')
package.loaded['EmberRoutesProbe/ProductionJobs']={valid=function() return true end}
package.loaded['EmberRoutesProbe/ProductionCarry']={fits=function() return true end}
for _,name in ipairs({'ProductionRecipe','CraftStations','CraftRecipeInputs'}) do package.loaded['EmberRoutesProbe/'..name]={} end
package.loaded['TimedActions/ISInventoryTransferAction']=true package.loaded['Entity/TimedActions/ISHandcraftAction']=true
EmberRoutesProbeJava={carrierActive=function() return true end}
local physical=0
ISInventoryTransferAction={new=function(_,worker,i,from,to)
    return {isValid=function() return true end,startActionAnim=function() end,stop=function() end,
        perform=function() physical=physical+1 for k,v in ipairs(from.items) do if v==i then table.remove(from.items,k) break end end to.items[#to.items+1]=i i.container=to end}
end}
local Actions=require 'EmberRoutesProbe/ProductionActions'
local function transfer(a)
    local row=Allocation.row(record,a) local t=endpoints[row.targets[1].destinationId] local i=plan.locations[a.id].item
    local action=assert(Actions.transfer(c,i,root,t.container,t,function()
        if Allocation.settle(row,t.id) then a.delivered=true record.delivered=record.delivered+1 end
    end))
    action:perform() action:perform()
end
for i=1,5 do transfer(record.outputs[i]) end
check(physical==5 and record.delivered==5 and #root.items==2,'each original transferred once; duplicate callback cannot duplicate settlement')
check(not Allocation.settle(record.outputAllocation.assets[1],'D1'),'duplicate receipt rejected')
local function copy(v) if type(v)~='table' then return v end local t={} for k,x in pairs(v) do t[k]=copy(x) end return t end
record=copy(record) c.record=record -- save/load scalar manifest, no shared table references
check(Allocation.valid(record.outputAllocation),'saved manifest validates after reload')
allocated,settled,remaining=Allocation.count(record,'Base.Plank')
check(allocated==5 and settled==5 and remaining==1,'reload retains partial allocation/settlement separately')
endpoints.D2.container.capacity=4
routing=Routing.new(c) for _=1,100 do if routing:step(8) then break end end
transfer(record.outputs[6])
allocated,settled,remaining=Allocation.count(record,'Base.Plank')
check(allocated==6 and settled==6 and remaining==0 and physical==6,'remaining original completes without repeating prior transfers')
check(#endpoints.D1.container.items==2 and #endpoints.D2.container.items==4,'physical destination total equals settled, not settled plus stock')
local bad=copy(record.outputAllocation) bad.assets[1].transferred=2
check(not Allocation.valid(bad),'invalid per-ItemID settlement rejected')
record.npcId='n' record.requester='owner' record.recipeId='saw' record.recipeName='Saw'
record.signature='saw:1' record.settlementId='s' record.unitYield=3 record.format=4
record.generation=1 record.released=false record.state='RUNNING' record.phase='RETURNING'
record.product='Base.Plank'
local Contract=require 'EmberRoutesProbe/CraftRecord'
check(Contract.validProduction('n',record),'complete production record accepts persisted allocation/settlement chain')
record.outputs[1].delivered=false
check(not Contract.validProduction('n',record),'record rejects disagreement between ItemID transfer receipt and delivered flag')
record.outputs[1].delivered=true
print('PASS '..n..' Gate C cross-target checks; native transfer effects mocked, game UNVERIFIED')
