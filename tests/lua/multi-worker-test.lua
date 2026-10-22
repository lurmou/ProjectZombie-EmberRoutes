-- Real Lua controllers, deliberately fake native actions/Java bodies. No engine claim.
local fixture=dofile("tests/lua/work-test.lua")
local Work=require "EmberRoutesProbe/Work"
local Store=require "EmberRoutesProbe/LaborStore"
local Companion=require "EmberRoutesProbe/Companion"
local Probe=fixture.ctx.Probe
local actor=fixture.actor
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local originalPrint=print print=function() end
local function body(id)
    local npc=setmetatable({id=id,root=fixture.ctx.newContainer(),actions=fixture.ctx.list({}),
        x=0.5,y=0.5,z=0,motion="REACHED",alive=true},{__index=fixture.npc})
    return npc
end
local a,b=body("worker-a"),body("worker-b")
local bodies={[a.id]=a,[b.id]=b}
local selected=a.id
local bridge=EmberRoutesProbeJava
bridge.selectedId=function() return selected end
bridge.selectCarrier=function(id) if bodies[id] then selected=id return true end return false end
bridge.carrierId=function(npc) return npc.id end
bridge.controlledCarrier=function() local npc=bodies[selected] return npc.alive and npc or nil end
bridge.actionCarrier=bridge.controlledCarrier
bridge.carrierFor=function(id) local npc=bodies[id] return npc and npc.alive and npc or nil end
bridge.carrierPresent=function(npc) return npc and npc.alive end
bridge.carrierActive=bridge.carrierPresent
bridge.motionResult=function(npc) return npc.motion end
bridge.stopCarrier=function(npc) npc.motion="STOPPED" return true end
bridge.commandFor=function(id,command,_,x,y,z)
    check(command=="move","worker submits only explicit move")
    local npc=bodies[id] npc.x,npc.y,npc.z=x,y,z npc.motion="REACHED" return "MOVE_REQUESTED"
end
bridge.command=function() error("implicit selected movement forbidden in multi-worker execution") end
function Probe.cancelAll(reason,id)
    id=id or selected
    Work.pause(reason,id) Companion.cancel(reason,id)
    fixture.ctx.Actions.cancel(reason,id) fixture.world.Haul.cancel(reason,id)
end
local queued={}
function ISTimedActionQueue.add(action)
    queued[action.character]=action action.character.actions[1]=action
    action:startActionAnim()
end
function ISTimedActionQueue.hasAction(action) return action and queued[action.character]==action end
function ISTimedActionQueue.clear(npc)
    if queued[npc] then queued[npc]:stop() end
end
function ISInventoryTransferAction:new(npc,item,from,to)
    local action={character=npc,item=item,from=from,to=to}
    function action:isValid() return true end
    function action:startActionAnim() end
    function action:update() end
    function action:stop() queued[npc]=nil npc.actions[1]=nil end
    function action:perform()
        from:Remove(item) to.items[#to.items+1]=item item.container=to
        queued[npc]=nil npc.actions[1]=nil
    end
    return action
end
local time=getTimestampMs()
getTimestampMs=function() return time end
local function tick(n,effects)
    for _=1,n do
        time=time+100
        if effects then
            for _,npc in ipairs({a,b}) do local action=queued[npc] if action then action:perform() end end
        end
        Work.tick()
    end
end
local function route(npc,source,destination)
    selected=npc.id actor.x=source.square.x+0.5
    Work.execute(actor,"inbox",source)
    check(Work.execute(actor,"source",source):find("^SELECTED"),"per-worker source selected")
    actor.x=destination.square.x+0.5 Work.execute(actor,"outbox",destination)
    check(Work.execute(actor,"destination",destination):find("^SELECTED"),"per-worker destination selected")
end
local source,destination=fixture.object(4),fixture.object(12)
route(a,source,destination)
local first=fixture.item("worker-a-original",source.container)
check(Work.execute(actor,"run"):find("^STARTED"),"first worker accepted")
local aTask=Work.record(a.id)
route(b,source,destination)
check(Work.execute(actor,"run")=="ITEM_RESERVED","another worker cannot claim same physical original")
local second=fixture.item("worker-b-original",source.container)
check(Work.execute(actor,"run"):find("^STARTED"),"second worker claims only new unowned original")
check(#Work.record(b.id).items==1 and Work.record(b.id).items[1]==second:getID(),"disjoint manifests")
tick(2,false)
check(queued[a] and queued[b],"two independent native queues active despite UI selecting B")
local stale=queued[a]
Work.pause("USER",a.id)
check(not queued[a] and queued[b] and Work.record(b.id).state=="RUNNING","pausing A leaves B working")
stale:perform()
check(first:getContainer()==source.container,"old callback cannot perform after generation invalidation")
tick(12,true)
check(Work.record(b.id).state=="DONE" and second:getContainer()==destination.container,"B finishes while A paused")
check(aTask.state=="PAUSED" and first:getContainer()==source.container,"A retains its claim and original")
selected=a.id Work.execute(actor,"resume") selected=b.id tick(15,true)
check(aTask.state=="DONE" and first:getContainer()==destination.container,"A resumes with explicit identity while B selected")
check(not Store.owner(first:getID()) and not Store.owner(second:getID()),"verified completion releases item claims")
selected=a.id Work.execute(actor,"clear") selected=b.id Work.execute(actor,"clear")

source,destination=fixture.object(4),fixture.object(12)
function destination.container:getFreeCapacity() return 1-#self.items end
function destination.container:hasRoomFor(_,item) return self:getFreeCapacity()>=item:getUnequippedWeight() end
route(a,source,destination)
local capacityA=fixture.item("capacity-a",source.container)
Work.execute(actor,"run")
route(b,source,destination)
local capacityB=fixture.item("capacity-b",source.container)
Work.execute(actor,"run") tick(2,false)
check(queued[a] and not queued[b] and capacityB:getContainer()==source.container,"central capacity prevents two takes for one free slot")
check(Work.busy(b.id),"capacity contention waits without abandoning task")
queued[a]:perform() Work.pause("SAVE",a.id)
local held=Work.record(a.id)
check(held.reservation and capacityA:getContainer()==a.root,"held cargo retains durable destination reservation")
tick(4,true)
check(capacityB:getContainer()==source.container and Work.busy(b.id),"paused held cargo still owns reserved space")
local oldGeneration=held.generation
Work.reset()
package.loaded["EmberRoutesProbe/LaborStore"]=nil
package.loaded["EmberRoutesProbe/WorkAgent"]=nil
package.loaded["EmberRoutesProbe/Work"]=nil
Work=require "EmberRoutesProbe/Work" Store=require "EmberRoutesProbe/LaborStore"
check(Store.record(a.id).generation>oldGeneration and Store.record(a.id).reservation,"reload rebuilds claims from scalar intent")
selected=b.id Work.execute(actor,"resume") tick(3,true)
check(capacityB:getContainer()==source.container and Work.busy(b.id),"restored reservation blocks conflicting worker")
selected=a.id Work.execute(actor,"resume") tick(15,true)
check(capacityA:getContainer()==destination.container and Work.record(a.id).state=="DONE","held original delivered after controller reload")
check(Work.record(b.id).state=="PAUSED" and Work.record(b.id).reason=="DESTINATION_FULL","native physical capacity remains final guard")
destination.container:Remove(capacityA)
selected=b.id Work.execute(actor,"resume") tick(15,true)
check(capacityB:getContainer()==destination.container and Work.record(b.id).state=="DONE","waiting worker can resume after real space freed")

-- Both companions retain independent bindings; selected worker never retargets A.
selected=a.id actor.x=6 Companion.execute(actor,"follow")
selected=b.id Companion.execute(actor,"follow") Companion.tick()
check(Companion.exportState(a.id).mode=="FOLLOW" and Companion.exportState(b.id).mode=="FOLLOW","two follower intents coexist")
Companion.cancel("USER",a.id)
check(Companion.exportState(a.id).mode=="HOLD" and Companion.exportState(b.id).mode=="FOLLOW","companion cancellation is scoped")
Companion.cancelAll("TEST_END")

local Persistence=require "EmberRoutesProbe/Persistence"
local saved,blocked,restored={},{},{}
bridge.workerCount=function() return 2 end
bridge.workerIdAt=function(index) return index==0 and a.id or b.id end
bridge.saveCheckpointFor=function(id,mode)
    check(not Work.busy(a.id) and not Work.busy(b.id) and not queued[a] and not queued[b],"save quiesces every worker before first capture")
    saved[id]=mode return "CHECKPOINT_SAVED"
end
bridge.blockAllCheckpoints=function(reason) blocked[#blocked+1]=reason return "CHECKPOINT_BLOCKED" end
selected=a.id Companion.execute(actor,"follow") selected=b.id
Persistence.save()
check(saved[a.id]=="FOLLOW" and saved[b.id]=="HOLD","save captures each worker's own intent")
check(Companion.exportState(a.id).mode=="FOLLOW" and selected==b.id,"save restores A follow without changing UI selection")
local goodSave=bridge.saveCheckpointFor
bridge.saveCheckpointFor=function(id,...) if id==b.id then return "SAVE_UNAVAILABLE" end return goodSave(id,...) end
Persistence.save()
check(#blocked==1 and blocked[1]:find("WORKER_SAVE_FAILED"),"any refused capture poisons mixed older checkpoints")
bridge.saveCheckpointFor=goodSave
bridge.restoreCheckpoint=function() restored[#restored+1]=selected return "CHECKPOINT_RESTORED" end
bridge.checkpointMode=function() return "HOLD" end
bridge.checkpointHasHome=function() return false end
bridge.checkpointHomeX=function() return 0 end bridge.checkpointHomeY=bridge.checkpointHomeX bridge.checkpointHomeZ=bridge.checkpointHomeX
function actor:getCurrentSquare() return {} end
Probe.restorePending=true Persistence.tick()
check(#restored==1 and restored[1]==a.id and selected==b.id,"auto restore advances one record per tick and restores UI selection")
Persistence.tick() Persistence.tick() Persistence.tick()
check(#restored==2 and restored[2]==b.id,"auto restore visits each record once without per-frame retries")
print=originalPrint
print("PASS "..checks.." multi-worker controller/claim/capacity/recovery assertions; native fakes NOT runtime evidence")
return {fixture=fixture,a=a,b=b,bridge=bridge,actor=actor,tick=tick,queued=queued,
    select=function(id) selected=id end,Work=Work}
