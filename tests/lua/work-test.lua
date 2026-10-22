-- Orchestration fakes, not game-runtime evidence.
local world = dofile("tests/lua/haul-test.lua")
local ctx, npc, actor = world.ctx, world.npc, world.actor
local checks = 0
local function check(value, why) checks=checks+1 assert(value, why) end
local stores, squares = {}, {}
ModData = { getOrCreate=function(key) stores[key]=stores[key] or {} return stores[key] end }
local function square(x)
    local s={x=x, objects=ctx.list({})}
    function s:getX() return self.x end
    function s:getY() return 0 end
    function s:getZ() return 0 end
    function s:getObjects() return self.objects end
    function s:canReachTo() return true end
    function s:TreatAsSolidFloor() return true end
    function s:isSolid() return false end
    function s:isSolidTrans() return false end
    squares[x]=s return s
end
local function object(x)
    local o={square=square(x),container=ctx.newContainer(),data={}}
    function o.container:getType() return "crate" end
    o.square.objects[1]=o
    function o:getSquare() return self.square end
    function o:getContainer() return self.container end
    function o:getModData() return self.data end
    return o
end
local source, destination=object(4),object(12)
local cell={}
function cell:getGridSquare(x) return squares[x] end
function getCell() return cell end
function npc:getCurrentSquare() return squares[math.floor(self.x)] or square(math.floor(self.x)) end
function getSpecificPlayer() return actor end
function actor:isDead() return false end
EmberRoutesProbeJava.controlledCarrier=function() return npc end
EmberRoutesProbeJava.carrierId=function() return "work-npc" end
EmberRoutesProbeJava.carrierPresent=function(value) return value==npc end
EmberRoutesProbeJava.carrierActive=function(value) return value==npc end
EmberRoutesProbeJava.command=function(_,_,x,y,z) npc.x,npc.y,npc.z=x,y,z return "MOVE_REQUESTED" end
EmberRoutesProbeJava.motionResult=function() return "REACHED" end
EmberRoutesProbeJava.stopCarrier=function() ISTimedActionQueue.clear(npc) return true end
AdjacentFreeTileFinder.Find=function(s) return squares[s:getX()-1] or square(s:getX()-1) end
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Policy=require "EmberRoutesProbe/InventoryPolicy"
local Work=require "EmberRoutesProbe/Work"
local Probe=ctx.Probe
Probe.ready=true
function Probe.cancelAll(reason)
    Work.pause(reason)
    if Probe.cancelCompanion then Probe.cancelCompanion(reason) end
    ctx.Actions.cancel(reason) world.Haul.cancel(reason)
end
local function tag(o,name)
    actor.x=o.square.x+0.5
    return Work.execute(actor,name,o)
end
local function item(kind, container)
    local value=container:AddItem(kind)
    function value:getCategory() return self.category or "Normal" end
    function value:isEquipped() return self.equipped==true end
    function value:isFavorite() return self.favorite==true end
    function value:getFullType() return self.kind end
    function value:getDisplayCategory() return "Other" end
    function value:getOffAgeMax() return 1000000000 end
    return value
end
local function tick(n)
    for _=1,n do ctx.tick(1) Work.tick() end
end
local function job() return Work.record() end
local function clear()
    check(Work.execute(actor,"clear")=="TASK_CLEARED", "safe clear succeeds")
end
local realPrint=print
print=function() end
check(Work.execute(actor,"source",source)=="CONTAINER_PRIVATE", "untagged source denied")
check(tag(source,"inbox"):find("^TAGGED"),"tag source")
check(Work.execute(actor,"source",source):find("^SELECTED"),"select source")
check(tag(destination,"outbox"):find("^TAGGED"),"tag destination")
check(Work.execute(actor,"destination",destination):find("^SELECTED"),"select destination")
local first, second=item("real-a",source.container),item("real-b",source.container)
local private=item("unrelated",destination.container)
local favorite=item("favorite",source.container) favorite.favorite=true
local bag=item("bag",source.container) bag.category="Container"
local sample=item("sample",source.container) sample:getModData().EmberRoutesPersistenceSample=true
check(Work.execute(actor,"run"):find("^STARTED"),"start real inventory plan")
local taskId=job().id
check(Work.execute(actor,"resume")=="BUSY", "duplicate resume denied")
tick(100)
check(job().state=="DONE" and job().delivered==2,"all planned original instances delivered")
check(first:getContainer()==destination.container and second:getContainer()==destination.container,"original objects moved")
check(favorite:getContainer()==source.container and bag:getContainer()==source.container and sample:getContainer()==source.container,"protected items untouched")
check(private:getContainer()==destination.container,"unrelated inventory unchanged")
check(Work.execute(actor,"resume")=="DONE" and job().id==taskId,"finished task not replayed")
local completed=job()
check(Work.execute(actor,"run")=="NO_ELIGIBLE_ITEMS" and job()==completed,"empty next order retains completed report")
local nextCargo=item("next-order",source.container)
completed.state="PAUSED"
check(Work.execute(actor,"run")=="TASK_EXISTS_RESUME_OR_CLEAR" and job()==completed,"paused order cannot be replaced")
completed.state="RUNNING"
check(Work.execute(actor,"run")=="TASK_EXISTS_RESUME_OR_CLEAR","saved running record cannot be silently replaced")
completed.state="DONE"
tag(destination,"private")
check(Work.execute(actor,"run")=="CONTAINER_PRIVATE" and job()==completed,"invalid next endpoint preserves completed report")
tag(destination,"outbox")
local tooMany={}
for i=1,30 do tooMany[i]=item("next-limit"..i,source.container) end
check(Work.execute(actor,"run")=="TASK_LIMIT_30" and job()==completed,"oversized next order preserves completed report")
for _,value in ipairs(tooMany) do source.container:Remove(value) end
npc.actions[1]={}
check(Work.execute(actor,"run")=="NATIVE_ACTION_BUSY" and job()==completed and not Work.busy(),
    "late launch refusal preserves original completed report and no active candidate")
npc.actions[1]=nil
destination.container:Remove(first)
npc.root.items[#npc.root.items+1]=first first.container=npc.root
check(Work.execute(actor,"run")=="CARGO_RETAINED_RESUME_FIRST" and job()==completed,"DONE with cargo back on NPC still blocks replacement")
npc.root:Remove(first)
destination.container.items[#destination.container.items+1]=first first.container=destination.container
check(Work.execute(actor,"run"):find("^STARTED") and job().id~=taskId,"next valid order replaces completed task without manual clearing")
local nextTaskId=job().id
tick(100)
check(job().state=="DONE" and job().id==nextTaskId and nextCargo:getContainer()==destination.container,
    "consecutive order delivers only its new original instance")
check(first:getContainer()==destination.container and second:getContainer()==destination.container,
    "completed previous goods remain untouched")
clear()
local cargo=item("save-cargo",source.container)
cargo:setCondition(2) cargo:getModData().UserOwnedMarker="keep-state"
Work.execute(actor,"run")
for _=1,100 do tick(1) if cargo:getContainer()==npc.root then break end end
check(cargo:getContainer()==npc.root,"cargo acquired")
local Persistence=require "EmberRoutesProbe/Persistence"
local checkpointCalls=0
EmberRoutesProbeJava.saveCheckpoint=function()
    checkpointCalls=checkpointCalls+1
    check(job().state=="PAUSED" and npc.actions:isEmpty(),"actual persistence handler pauses work before native checkpoint")
    return "CHECKPOINT_SAVED"
end
EmberRoutesProbeJava.blockCheckpoint=function(reason) error("unexpected blocked checkpoint "..reason) end
Persistence.save()
check(checkpointCalls==1,"normal persistence boundary called exactly once")
local function scalarOnly(value)
    if type(value)=="table" then
        for key, child in pairs(value) do if not scalarOnly(key) or not scalarOnly(child) then return false end end
        return true
    end
    return type(value)=="string" or type(value)=="number" or type(value)=="boolean"
end
check(scalarOnly(Registry.data()),"persisted registry and job contain no action, actor or item handles")
check(job().state=="PAUSED" and npc:getCharacterActions():isEmpty(),"save stops all actions")
check(Work.execute(actor,"clear")=="CARGO_RETAINED_RESUME_FIRST","cannot forget held cargo")
check(Work.hasCargo(actor),"removal guard sees held cargo")
check(not Work.prepareRemoval(actor) and job()~=nil,"remove cannot discard a job holding cargo")
Work.reset() -- Same scalar world data, all transient execution state is discarded.
check(not Work.busy(),"no automatic replay after reset")
local oldName=cargo:getName()
check(Work.execute(actor,"resume"):find("^STARTED"),"explicit resume rebuilds steps")
tick(80)
check(job().state=="DONE" and cargo:getContainer()==destination.container and cargo:getName()==oldName,"saved cargo delivered as original")
check(cargo:getCondition()==2 and cargo:getModData().UserOwnedMarker=="keep-state","condition and custom metadata preserved")
clear()
local revoked=item("revoked",source.container)
Work.execute(actor,"run")
for _=1,100 do tick(1) if not npc.actions:isEmpty() then break end end
check(not npc.actions:isEmpty(),"native take action queued")
-- Revoke after last controller tick, immediately before native effect.
source.data.EmberRoutesContainer.tag="private"
tick(25)
check(job().state=="PAUSED" and revoked:getContainer()==source.container,"effect boundary refuses revoked access")
tag(source,"inbox")
Work.execute(actor,"resume") tick(100)
check(job().state=="DONE", "restoring tag allows explicit retry")
clear()
local full=item("full",source.container)
destination.container.full=true
Work.execute(actor,"run") tick(5)
check(job().state=="PAUSED" and job().reason=="DESTINATION_FULL" and full:getContainer()==source.container,"full target does not take item")
destination.container.full=false
Work.execute(actor,"resume") tick(100) clear()
local lost=item("lost",source.container)
Work.execute(actor,"run") Work.pause("USER")
source.container:Remove(lost)
check(Work.execute(actor,"resume"):find("^ITEM_MISSING"),"missing item refused without replacement")
clear()
local midFull=item("became-full-after-take",source.container)
Work.execute(actor,"run")
for _=1,100 do tick(1) if midFull:getContainer()==npc.root then break end end
destination.container.full=true
tick(5)
check(job().state=="PAUSED" and midFull:getContainer()==npc.root,"target filling after take retains original cargo")
destination.container.full=false
Work.execute(actor,"resume") tick(100) clear()
local wrongNpcItem=item("wrong-npc",source.container)
Work.execute(actor,"run") Work.pause("USER")
local originalNpcId=EmberRoutesProbeJava.carrierId
EmberRoutesProbeJava.carrierId=function() return "other-npc" end
check(Work.execute(actor,"resume")=="NPC_ID_MISMATCH", "another NPC cannot acquire task")
check(Work.hasCargo(actor), "unknown owner fails closed for deletion")
EmberRoutesProbeJava.carrierId=originalNpcId
Work.execute(actor,"resume") tick(100) clear()
check(wrongNpcItem:getContainer()==destination.container,"original owner resumes its original item")
local duplicate=item("dup",source.container)
source.container.items[#source.container.items+1]=duplicate
check(Work.execute(actor,"run")=="ITEM_ID_DUPLICATED","duplicate planning IDs denied")
table.remove(source.container.items)
source.container:Remove(duplicate)
local held,missing=item("held-before-missing",source.container),item("missing-later",source.container)
Work.execute(actor,"run")
for _=1,100 do tick(1) if held:getContainer()==npc.root then break end end
Work.pause("SAVE")
source.container:Remove(missing)
check(Work.execute(actor,"resume"):find("^STARTED"),"held cargo can be safely delivered even if a later source item is missing")
tick(100)
check(held:getContainer()==destination.container and job().state=="PAUSED" and job().reason:find("^ITEM_MISSING"),
    "deliver existing cargo then pause missing item without replacement")
clear()
local limited={}
for i=1,31 do limited[i]=item("limit"..i,source.container) end
check(Work.execute(actor,"run")=="TASK_LIMIT_30" and job()==nil,"oversized task refused before mutation")
for _,value in ipairs(limited) do source.container:Remove(value) end
local pathItem=item("path-failure",source.container)
npc.x=0.5
local originalMove=EmberRoutesProbeJava.command
EmberRoutesProbeJava.command=function() return "INVALID_TILE" end
Work.execute(actor,"run") tick(5)
check(job().state=="PAUSED" and job().reason=="INVALID_TILE" and pathItem:getContainer()==source.container,"path rejection is a structured pause")
EmberRoutesProbeJava.command=originalMove
Work.execute(actor,"resume") tick(100) clear()
local removalItem=item("remove-before-take",source.container)
Work.execute(actor,"run") Work.pause("USER")
check(Work.prepareRemoval(actor) and job()==nil and removalItem:getContainer()==source.container,
    "explicit removal with no held cargo releases task metadata without deleting source items")
source.container:Remove(removalItem)
local Filter=require "EmberRoutesProbe/StorageFilter"
local allowed=item("Mod.Allowed",source.container)
local rejected=item("Mod.Rejected",source.container)
local config=Filter.new() config.types[allowed:getFullType()]=true
actor.x=destination.square.x+0.5
check(Registry.configure(actor,destination,config)=="FILTER_CONFIGURED","filter configuration submitted through registry")
Work.execute(actor,"run") tick(100)
check(job().state=="DONE" and allowed:getContainer()==destination.container and rejected:getContainer()==source.container,
    "plan moves only target-accepted instances")
clear()
check(Work.execute(actor,"run")=="NO_ELIGIBLE_ITEMS","rejected remainder is not taken")
config.types[rejected:getFullType()]=true Registry.configure(actor,destination,config)
Work.execute(actor,"run")
for _=1,100 do tick(1) if not npc.actions:isEmpty() then break end end
check(not npc.actions:isEmpty(),"filter-sensitive transfer queued")
-- No notification: exercise the native effect guard independently of UI callbacks.
destination.data.EmberRoutesContainer.filter.types[rejected:getFullType()]=false
tick(25)
check(job().state=="PAUSED" and rejected:getContainer()==source.container,"target rejection at effect boundary prevents taking cargo")
Registry.configure(actor,destination,config)
Work.execute(actor,"resume") tick(100)
check(rejected:getContainer()==destination.container and job().state=="DONE","filter corrected then original task resumed")
clear()
Policy.registerTag("readonly", {read=true,write=false})
tag(destination,"readonly")
check(Work.execute(actor,"destination",destination)=="CONTAINER_PRIVATE","registered tag capability checked for destination")
tag(destination,"outbox")
local id=destination.data.EmberRoutesContainer.id
local originalStores=stores
stores={}
check(not Registry.resolve(id),"new world cannot resolve previous-world registry")
stores=originalStores
destination.square.objects[1]=nil
check(not Registry.resolve(id),"removed physical object cannot resolve stable ID")
print=realPrint
print("PASS "..checks.." real-haul policy/orchestration checks; engine runtime NOT verified")
return {world=world,ctx=ctx,npc=npc,actor=actor,object=object,item=item,square=square,stores=stores}
