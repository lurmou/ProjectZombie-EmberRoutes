-- Native work leaves. Each effect is observed; no synthetic harvest/forage loot.
require 'TimedActions/ISCleanBlood'
require 'TimedActions/ISChopTreeAction'
require 'TimedActions/ISGrabCorpseAction'
require 'TimedActions/ISDropCorpseAction'
require 'TimedActions/ISUnequipAction'
require 'TimedActions/ISEquipWeaponAction'
require 'Farming/TimedActions/ISWaterPlantAction'
require 'Farming/TimedActions/ISHarvestPlantAction'
require 'Farming/TimedActions/ISShovelAction'
require 'Farming/ISUI/ISFarmingMenu'
require 'Foraging/ISForageAction'
require 'Foraging/ISSearchManager'
require 'Foraging/ISForageIcon'
local Spatial=require 'EmberRoutesProbe/FieldSpatial'
local Discovery=require 'EmberRoutesProbe/FieldDiscovery'
local Cargo=require 'EmberRoutesProbe/FieldCargo'
local Native=require 'EmberRoutesProbe/FieldActions'
local Record=require 'EmberRoutesProbe/FieldRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local O={}
local function available(item,jobId)
    if not item or item:isBroken() then return false end
    local owner=Store.owner(item:getID()) return not owner or owner.taskId==jobId
end
function O.supplies(npc,kind,jobId)
    local inv=npc:getInventory()
    if kind=='TREE' then
        local axe=inv:getFirstEvalRecurse(function(i) return available(i,jobId) and i:hasTag(ItemTag.CHOP_TREE) end)
        return axe and {axe} or nil
    elseif kind=='STAIN' then
        local tool=inv:getFirstEvalRecurse(function(i) return available(i) and i:hasTag(ItemTag.CLEAN_STAINS) end)
        local cleaner=inv:getFirstEvalRecurse(function(i)
            local f=i:getFluidContainer()
            return f and not Store.owner(i:getID()) and (f:contains(Fluid.Bleach) or f:contains(Fluid.CleaningLiquid))
                and f:getAmount()>=ZomboidGlobals.CleanBloodBleachAmount
        end)
        return tool and cleaner and {tool,cleaner} or nil
    elseif kind=='WATER' then
        local water=inv:getFirstEvalRecurse(function(i)
            local f=i:getFluidContainer()
            return not Store.owner(i:getID()) and f and f:isFilledWithCleanWater()
                and ISFarmingMenu.getWaterUsesInteger(i)>0
        end)
        return water and {water} or nil
    elseif kind=='CLEAR' then
        local tool=inv:getFirstEvalRecurse(function(i) return available(i) and i:hasTag(ItemTag.DIG_PLOW) end)
        return tool and {tool} or nil
    end
    return {}
end
local function ownedTools(c)
    local result={}
    for _,id in ipairs(c.job.payload.target.tools or {}) do
        local inv=c.npc:getInventory() local item=inv:getFirstEvalRecurse(function(i) return i:getID()==id end)
        if not item or not Store.validField(c.job,c.token,'item:'..id) then return nil end
        result[#result+1]=item
    end
    return result
end
local function toolNode(c,item,secondary)
    local from=item:getContainer() local own=c.npc:getInventory()
    if from~=own then
        return Native.new(c,{kind='READY_TOOL',transfer=item,
            valid=function() return item:getContainer()==from and from:isInCharacterInventory(c.npc) end,
            create=function() return ISInventoryTransferAction:new(c.npc,item,from,own,50) end,
            observe=function(ok,finished)
                if item:getContainer()==own and own:getItems():contains(item) then return true,true end
                return item:getContainer()==from,false,not finished
            end})
    end
    local twoHands=not secondary and item.isTwoHandWeapon and item:isTwoHandWeapon() or false
    return Native.new(c,{kind='EQUIP',create=function() return ISEquipWeaponAction:new(c.npc,item,50,not secondary,twoHands) end,
        observe=function(ok,finished)
            local hand=secondary and c.npc:getSecondaryHandItem() or c.npc:getPrimaryHandItem()
            return true,hand==item,not finished
        end})
end
local function readyTools(c,tools)
    if c.job.payload.target.kind=='WATER' then
        if tools[1]:getContainer()==c.npc:getInventory() then return true end
        c.node=toolNode(c,tools[1],false) return false
    end
    for i,item in ipairs(tools) do
        local hand=i==2 and c.npc:getSecondaryHandItem() or c.npc:getPrimaryHandItem()
        if item:getContainer()~=c.npc:getInventory() or hand~=item then c.node=toolNode(c,item,i==2) return false end
    end
    return true
end
local function stopAt(c,square,avoidPlants)
    c.approach=c.approach or Spatial.adjacent(c.npc,square,avoidPlants)
    local reached=Spatial.reachable(c.npc,square) and (not avoidPlants or Spatial.walkway(c.npc:getCurrentSquare()))
    local state=c.move(c.approach,reached)
    if state~='Success' then return state end
    c.approach=nil
    local native=c.body.snapshot()
    if not native.nativeStopped then c.body.stop() return 'Running' end
    return 'Success'
end
function O.dropped(c)
    local cell=getCell() if not cell then return nil end
    local x,y,z=math.floor(c.npc:getX()),math.floor(c.npc:getY()),math.floor(c.npc:getZ())
    for dx=-1,1 do for dy=-1,1 do
        local sq=cell:getGridSquare(x+dx,y+dy,z)
        local bodies=sq and sq:getDeadBodys()
        if bodies then for i=0,bodies:size()-1 do local b=bodies:get(i)
            if Spatial.identity(b)==c.job.payload.target.identity then return b,sq end
        end end
    end end
end
function O.settleCorpse(c)
    if not c.job.payload.holding then return true end
    if c.npc:isDraggingCorpse() then return true end
    local b,sq=O.dropped(c)
    if not b then return c.unknown('FIELD_CORPSE_IDENTITY_UNCONFIRMED') end
    return c.change(function(j)
        j.payload.holding=nil j.payload.target.x=sq:getX() j.payload.target.y=sq:getY() j.payload.target.z=sq:getZ()
        j.payload.target.itemId=b:getItem():getID()
    end)
end
local function corpse(c,t)
    if c.job.payload.holding then
        if not c.npc:isDraggingCorpse() then O.settleCorpse(c) return 'Running' end
        local p=Discovery.policy('cleaning',c.job.scopeId)
        local zone=require('EmberRoutesProbe/SettlementZones').get(p.corpseZoneId)
        if not zone or not zone.enabled or zone.settlementId~=c.job.scopeId then c.reason='FIELD_CORPSE_ZONE_REQUIRED' return 'Failure' end
        local a=(zone.areas or {})[1] if not a then return 'Failure' end
        local dest=Spatial.square({x=a.x,y=a.y,z=a.z or 0})
        local own=c.npc:getCurrentSquare()
        local inside=own and require('EmberRoutesProbe/SettlementZones').contains(zone,own:getX(),own:getY(),own:getZ())
        local state=c.move(dest,inside) if state~='Success' then return state end
        local native=c.body.snapshot()
        if not native.nativeStopped and native.nativeMask~=4096 then c.body.stop() return 'Running' end
        c.node=Native.new(c,{kind='DROP_CORPSE',startEffect=true,
            create=function() return ISDropCorpseAction:new(c.npc,dest) end,
            observe=function(ok,finished)
                if c.npc:isDraggingCorpse() then return true,false,not finished end
                local b,sq=O.dropped(c)
                if not b then return false,false end
                local delivered=require('EmberRoutesProbe/SettlementZones').contains(zone,sq:getX(),sq:getY(),sq:getZ())
                local saved=c.change(function(j)
                    j.payload.holding=nil j.payload.workDone=delivered or nil
                    j.payload.target.x=sq:getX() j.payload.target.y=sq:getY() j.payload.target.z=sq:getZ()
                    j.payload.target.itemId=b:getItem():getID()
                end)
                return saved,delivered
            end})
        return c.node and 'Running' or 'Failure'
    end
    if c.npc:isDraggingCorpse() then c.reason='FIELD_NPC_ALREADY_DRAGGING_CORPSE' return 'Failure' end
    local b=Discovery.object(t)
    if not b or Spatial.identity(b)~=t.identity then c.reason='FIELD_CORPSE_MOVED' return 'Failure' end
    local state=stopAt(c,b:getSquare()) if state~='Success' then return state end
    for _,item in ipairs({c.npc:getPrimaryHandItem(),c.npc:getSecondaryHandItem()}) do
        if item then
            local owner=Store.owner(item:getID()) if owner and owner.taskId~=c.job.id then return 'Failure' end
            c.node=Native.new(c,{kind='UNEQUIP',create=function() return ISUnequipAction:new(c.npc,item,50) end,
                observe=function(ok,finished) return true,c.npc:getPrimaryHandItem()~=item and c.npc:getSecondaryHandItem()~=item,not finished end})
            return c.node and 'Running' or 'Failure'
        end
    end
    c.node=Native.new(c,{kind='GRAB_CORPSE',create=function() return ISGrabCorpseAction:new(c.npc,b) end,
        observe=function(ok,finished)
            local dragging=c.npc:isDraggingCorpse()
            local targetStillWorld=b:getStaticMovingObjectIndex()>=0
            if dragging and not targetStillWorld then
                return c.change(function(j) j.payload.holding=true end),true
            end
            if not finished and targetStillWorld then return true,false,true end
            return false,false
        end})
    return c.node and 'Running' or 'Failure'
end
local function work(c,t,tools)
    local square=Spatial.square(t) if not square then c.reason='FIELD_TARGET_UNLOADED' return 'Failure' end
    local o=Discovery.object(t)
    if t.kind~='STAIN' and t.kind~='FORAGE' and (not o or Spatial.identity(o)~=t.identity) then
        c.reason='FIELD_TARGET_REPLACED' return 'Failure'
    end
    local state=stopAt(c,square,t.kind=='WATER' or t.kind=='HARVEST' or t.kind=='CLEAR') if state~='Success' then return state end
    if not readyTools(c,tools) then return c.node and 'Running' or 'Failure' end
    local before,ground,water
    local h={kind=t.kind,valid=function()
        if not Spatial.reachable(c.npc,square) then return false end
        if t.kind=='STAIN' or t.kind=='FORAGE' then return true end
        return Discovery.object(t)==o and Spatial.identity(o)==t.identity
    end,before=function()
        if t.kind=='HARVEST' or t.kind=='FORAGE' then before=Cargo.snapshot(c.npc:getInventory()) return before~=nil end
        if t.kind=='TREE' then ground=Cargo.ground(t) return ground~=nil end
        return true
    end}
    if t.kind=='STAIN' then
        h.create=function() return ISCleanBlood:new(c.npc,square,tools[2]) end
        h.observe=function(ok,finished)
            return true,not EmberRoutesProbeJava.cleaningSquareHasStains(square),not finished
        end
    elseif t.kind=='TREE' then
        h.progressive=true
        h.create=function() return ISChopTreeAction:new(c.npc,o) end
        h.observe=function(ok,finished)
            if ground and not Cargo.outputs(c,ground,Cargo.ground(t),true) then return false,false end
            ground=nil
            return ok,o:getObjectIndex()<0,not finished
        end
    elseif t.kind=='HARVEST' then
        local plant=Discovery.plant(t)
        h.create=function() return ISHarvestPlantAction:new(c.npc,plant,100) end
        h.observe=function(ok,finished)
            if before and not Cargo.outputs(c,before,Cargo.snapshot(c.npc:getInventory())) then return false,false end
            before=nil
            return ok,plant:canHarvest()==false,not finished
        end
    elseif t.kind=='WATER' then
        local plant=Discovery.plant(t) water=plant.waterLvl or 0
        local f=tools[1]:getFluidContainer() local amount=f:getAmount()
        h.progressive=true
        h.willUpdate=function(a) return a.uses>0 and a:getJobDelta()-a.usesUsed*a.deltaPerUse>=a.deltaPerUse end
        h.create=function()
            local goal,_,maximum=Discovery.waterGoal(plant)
            local level=plant.waterLvl or 0
            local uses=math.min(10,ISFarmingMenu.getWaterUsesInteger(tools[1]),math.ceil((goal-level)/10),math.floor((maximum-level)/10))
            return uses>0 and ISWaterPlantAction:new(c.npc,tools[1],uses,square,20+6*uses) or nil
        end
        h.observe=function(ok,finished)
            plant:updateFromIsoObject()
            local changed=(plant.waterLvl or 0)>water and f:getAmount()<amount
            local unchanged=(plant.waterLvl or 0)==water and f:getAmount()==amount
            return ok and (changed or unchanged),changed and finished,not finished
        end
    elseif t.kind=='CLEAR' then
        local plant=Discovery.plant(t)
        h.create=function() return ISShovelAction:new(c.npc,tools[1],plant,100) end
        h.observe=function(ok,finished) return ok,not plant:getObject() or plant:getObject():getObjectIndex()<0,not finished end
    elseif t.kind=='FORAGE' then
        local fs=_G.forageSystem local zone=fs.getForageZoneAt(t.x,t.y) local raw=zone and zone.forageIcons[t.iconId]
        if not raw then c.reason='FIELD_FORAGE_ICON_GONE' return 'Failure' end
        local adapted,why=require('EmberRoutesProbe/FieldForage').prepare(c.npc,raw,zone,square)
        if not adapted then c.reason=why return 'Failure' end
        local icon=adapted.icon
        if not c.job.payload.spotted then
            if not c.change(function(j) j.payload.spotted='COMMITTING' j.effects='UNKNOWN' end) then return 'Failure' end
            -- No unmeasured exploration-distance bonus. Native minimum XP is
            -- credited once; a failed boundary stays UNKNOWN instead of replaying.
            local ok=pcall(fs.itemFound,c.npc,raw.itemType,0)
            if not ok then c.unknown('FIELD_FORAGE_SPOT_UNKNOWN') return 'Failure' end
            if not c.change(function(j) j.payload.spotted='APPLIED' j.effects='KNOWN' end) then return 'Failure' end
        end
        h.create=adapted.create h.invoke=adapted.invoke
        h.observe=function(ok,finished)
            if before and not Cargo.outputs(c,before,Cargo.snapshot(c.npc:getInventory())) then return false,false end
            before=nil
            -- complete deposits originals; perform later retires the icon/ecology.
            local deposited=true
            for i=0,icon.itemList:size()-1 do if icon.itemList:get(i):getContainer()~=c.npc:getInventory() then deposited=false end end
            return ok,deposited,not finished
        end
        h.afterPerform=function() return zone.forageIcons[t.iconId]==nil end
    end
    c.node=Native.new(c,h)
    return c.node and 'Running' or 'Failure'
end
local function waste(c,t)
    local entry=require('EmberRoutesProbe/SettlementLedger').get(c.job.scopeId)
    local ep=entry and require('EmberRoutesProbe/CraftSupply').endpoint(entry,t.sourceId,'take')
    if not ep then c.reason='FIELD_WASTE_SOURCE_UNAVAILABLE' return 'Failure' end
    local list=ep.container:getItems() local item
    if list:size()>2000 then c.reason='FIELD_SOURCE_LIMIT' return 'Failure' end
    for i=0,list:size()-1 do if list:get(i):getID()==t.itemId then item=list:get(i) break end end
    if not item or not instanceof(item,'Food') or not item:isRotten() then c.reason='FIELD_WASTE_CHANGED' return 'Failure' end
    local Transfer=require 'EmberRoutesProbe/WorkTransfer'
    if not Transfer.reachable(c.npc,ep) then
        if not c.approach then local p=Transfer.prepareMove(c,ep) c.approach=p and p.square end
        return c.move(c.approach,false)
    end
    if not c.body.snapshot().nativeStopped then c.body.stop() return 'Running' end
    c.approach=nil c.path=nil
    local own=c.npc:getInventory()
    if require('EmberRoutesProbe/LaborProducers').freeCarry(c.npc)<item:getUnequippedWeight() then c.reason='FIELD_CARRY_FULL' return 'Failure' end
    c.node=Native.new(c,{kind='TAKE_WASTE',transfer=item,
        valid=function()
            return require('EmberRoutesProbe/ContainerRegistry').revalidate(ep,'take','local-world')
                and require('EmberRoutesProbe/ContainerRegistry').logistics(ep)=='STORAGE'
                and require('EmberRoutesProbe/LaborProducers').eligible(item) and not item:getIsCraftingConsumed()
                and Transfer.reachable(c.npc,ep) and item:getContainer()==ep.container and item:isRotten()
                and Store.validField(c.job,c.token,'item:'..item:getID())
        end,
        create=function() return ISInventoryTransferAction:new(c.npc,item,ep.container,own,90) end,
        observe=function(ok,finished)
            if item:getContainer()==own and own:getItems():contains(item) and not ep.container:getItems():contains(item) then
                local saved=c.change(function(j)
                    if not Record.asset(j,item:getID()) then
                        j.payload.assets[#j.payload.assets+1]={id=item:getID(),fullType=item:getFullType(),custody='HELD'}
                    end
                end)
                require('EmberRoutesProbe/ContainerRegistry').inventoryChanged(ep.container)
                return saved,true
            end
            return item:getContainer()==ep.container,false,not finished
        end})
    return c.node and 'Running' or 'Failure'
end
function O.step(c)
    local previous=c.job.payload.attempt
    if not c.node and previous and previous.state=='APPLIED' then
        local complete={TREE=true,STAIN=true,HARVEST=true,WATER=true,CLEAR=true,FORAGE=true,TAKE_WASTE=true,DROP_CORPSE=true}
        if complete[previous.kind] then
            if not c.change(function(j) j.payload.workDone=true end) then return 'Failure' end
        end
    end
    if c.node then
        local state=c.node.run() if state=='Running' then return state end
        if state=='Failure' then c.reason=c.reason or 'FIELD_NATIVE_STOPPED' return state end
        local kind=c.job.payload.attempt.kind c.node=nil
        if kind=='EQUIP' or kind=='READY_TOOL' or kind=='UNEQUIP' or kind=='GRAB_CORPSE' then return 'Running' end
        if kind~='DROP_CORPSE' then c.change(function(j) j.payload.workDone=true end) end
    end
    if c.job.payload.workDone then return 'Success' end
    local t=c.job.payload.target
    if t.kind=='FORAGE_REFRESH' then
        local fs=_G.forageSystem local zone=fs.getForageZoneAt(t.x,t.y)
        if not zone or zone.itemsLeft<=0 then return 'Success' end
        if not Discovery.policy('forager',c.job.scopeId).autoRefillZone then return 'Success' end
        if not c.change(function(j)
            j.payload.sequence=j.payload.sequence+1 j.effects='UNKNOWN'
            j.payload.attempt={id=j.id..':'..j.payload.sequence,kind='FORAGE_REFRESH',state='UNKNOWN',dispatched=true}
        end) then return 'Failure' end
        local ok=pcall(fs.createForageIcons,zone,false,8)
        if not ok then c.unknown('FIELD_FORAGE_REFRESH_UNKNOWN') return 'Failure' end
        c.change(function(j) j.effects='KNOWN' j.payload.attempt.state='APPLIED' j.payload.workDone=true end)
        return 'Success'
    end
    if t.kind=='CORPSE' then return corpse(c,t) end
    if t.kind=='ROTTEN' then return waste(c,t) end
    local tools=ownedTools(c) if not tools then c.reason='FIELD_TOOL_MISSING' return 'Failure' end
    return work(c,t,tools)
end
return O
