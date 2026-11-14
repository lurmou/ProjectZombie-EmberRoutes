-- Dual-worker world fixture. No scenario assertions live here: this file only
-- builds the shared two-worker host that the 18 consumer tests dofile
-- (cooking chain, delivery-service, haul-routing, logistics,
-- logistics-progress, task-transfer-uncertain) and returns it; each consumer
-- runs its own checks. Base host comes from tests/lua/actions-test.lua
-- (package.path, Probe stub, containers, native-action fakes); this file adds
-- the second worker body, x-keyed squares/objects, ModData/getCell, and the
-- EmberRoutesProbeJava bridge doubles. Legacy explicit-transfer Work verbs
-- (inbox/source/outbox/destination/run with STARTED/ITEM_RESERVED) were
-- removed with the format=1 pipeline in 59cb9b5 and are NOT revived: Work
-- now only supports resume/pause/clear through the routed HaulAgent.
-- Execution of this fixture and its consumers is UNVERIFIED here (no Lua
-- interpreter on this machine); only Kahlua compilation is checked.
local ctx=dofile("tests/lua/actions-test.lua")
local npc,actor=ctx.npc,ctx.actor
local Probe=ctx.Probe
local bridge=EmberRoutesProbeJava
-- World roots the production registry reads through ModData (same stub the
-- deleted work-test.lua carried; ContainerRegistry falls back to it when the
-- bridge has no cachedModData).
local stores={}
ModData={getOrCreate=function(key) stores[key]=stores[key] or {} return stores[key] end}
local squares={}
local function square(x)
    local s={x=x,objects=ctx.list({})}
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
local function item(kind,container)
    local value=container:AddItem(kind)
    function value:getCategory() return self.category or "Normal" end
    function value:isEquipped() return self.equipped==true end
    function value:isFavorite() return self.favorite==true end
    function value:getFullType() return self.kind end
    function value:getDisplayCategory() return "Other" end
    function value:getOffAgeMax() return 1000000000 end
    return value
end
local cell={}
function cell:getGridSquare(x) return squares[x] end
function getCell() return cell end
function getSpecificPlayer() return actor end
function isClient() return false end
function isServer() return false end
local uuid=0
function getRandomUUID() uuid=uuid+1 return "uuid-"..uuid end
luautils={getCorrectSquareForWall=function(_,s) return s end}
AdjacentFreeTileFinder={Find=function(s) return squares[s:getX()-1] or square(s:getX()-1) end}
npc.x,npc.y,npc.z=0.5,0.5,0
function npc:getX() return self.x end
function npc:getY() return self.y end
function npc:getZ() return self.z end
function npc:getCurrentSquare() return squares[math.floor(self.x)] or square(math.floor(self.x)) end
function npc:faceThisObject() end
actor.x,actor.z=0.5,0
function actor:getX() return self.x end
function actor:getY() return 0.5 end
function actor:getZ() return self.z end
function actor:getCurrentSquare() return squares[math.floor(self.x)] or square(math.floor(self.x)) end
local function body(id)
    return setmetatable({id=id,root=ctx.newContainer(),actions=ctx.list({}),
        x=0.5,y=0.5,z=0,motion="REACHED",alive=true},{__index=npc})
end
local a,b=body("worker-a"),body("worker-b")
local healthyPart={HasInjury=function() return false end,bandaged=function() return false end,bleeding=function() return false end}
local healthyDamage={getOverallBodyHealth=function() return 100 end,getBodyParts=function() return ctx.list({healthyPart}) end}
function npc:getBodyDamage() return healthyDamage end
function npc:isDead() return self.alive==false end
local bodies={[a.id]=a,[b.id]=b}
local selected=a.id
bridge.selectedId=function() return selected end
bridge.selectCarrier=function(id) if bodies[id] then selected=id return true end return false end
bridge.carrierId=function(worker) return worker.id end
bridge.controlledCarrier=function() local worker=bodies[selected] return worker.alive and worker or nil end
bridge.actionCarrier=bridge.controlledCarrier
bridge.carrierFor=function(id) local worker=bodies[id] return worker and worker.alive and worker or nil end
bridge.carrierPresent=function(worker) return worker and worker.alive end
bridge.carrierActive=bridge.carrierPresent
bridge.motionResult=function(worker) return worker and worker.motion or nil end
bridge.stopCarrier=function(worker) if not worker then return false end worker.motion="STOPPED" return true end
bridge.commandFor=function(id,command,_,x,y,z)
    assert(command=="move","worker submits only explicit move")
    local worker=bodies[id] assert(worker,"unknown carrier "..tostring(id))
    worker.x,worker.y,worker.z=x,y,z worker.motion="REACHED" return "MOVE_REQUESTED"
end
-- No implicit selected movement: Driver.move uses commandFor when present, so
-- a bare command() call is a fixture misuse, not a second movement path.
bridge.command=function() error("implicit selected movement forbidden in multi-worker execution") end
bridge.workerCount=function() return 2 end
bridge.workerIdAt=function(index) return index==0 and a.id or b.id end
-- Plain checkpoint doubles so Persistence.save() has a bridge to talk to; the
-- old scenario's quiescence assertions do not belong in a fixture.
bridge.saveCheckpointFor=function() return "CHECKPOINT_SAVED" end
bridge.blockAllCheckpoints=function() return "CHECKPOINT_BLOCKED" end
bridge.restoreCheckpoint=function() return "CHECKPOINT_RESTORED" end
bridge.checkpointMode=function() return "HOLD" end
bridge.checkpointHasHome=function() return false end
bridge.checkpointHomeX=function() return 0 end
bridge.checkpointHomeY=bridge.checkpointHomeX
bridge.checkpointHomeZ=bridge.checkpointHomeX
-- actions-test uses a load-only Work stub; this fixture exercises the real
-- coordinator, so discard that stub before resolving the production module.
package.loaded['EmberRoutesProbe/Work/Work']=nil
local Work=require "EmberRoutesProbe/Work/Work"
local time=getTimestampMs()
getTimestampMs=function() return time end
-- Fake the native action gate Haul.transferStep polls on: start records a
-- finish time, polls WAIT until then, stop clears it.
local nativeUntil=0
bridge.nativeActionStart=function(_,_,duration) nativeUntil=getTimestampMs()+duration*10 return true end
bridge.nativeActionFinished=function() return getTimestampMs()>=nativeUntil end
bridge.nativeActionStop=function() nativeUntil=0 end
local queued={}
function ISTimedActionQueue.add(action)
    queued[action.character]=action action.character.actions[1]=action
    action:startActionAnim()
end
function ISTimedActionQueue.hasAction(action) return action and queued[action.character]==action end
function ISTimedActionQueue.clear(worker)
    if queued[worker] then queued[worker]:stop() end
end
function ISInventoryTransferAction:new(worker,item,from,to)
    local action={character=worker,item=item,from=from,to=to}
    function action:isValid() return true end
    function action:startActionAnim() end
    function action:update() end
    function action:stop() queued[worker]=nil worker.actions[1]=nil end
    function action:perform()
        from:Remove(item) to.items[#to.items+1]=item item.container=to
        queued[worker]=nil worker.actions[1]=nil
    end
    return action
end
local function tick(n,effects)
    for _=1,n do
        time=time+100
        if effects then
            for _,worker in ipairs({a,b}) do local action=queued[worker] if action then action:perform() end end
        end
        Work.tick()
    end
end
-- Test doubles mirror Kernel/Boot cancel order (pause-all first, then every
-- companion exactly once, then actions, then haul). Domains resolve lazily so
-- the fixture loads even when a consumer never touches Companion/Haul.
function Probe.cancelAll(reason,id)
    id=id or (bridge.selectedId and bridge.selectedId())
    Work.pause(reason,id)
    local ok,Companion=pcall(require,"EmberRoutesProbe/Settlement/Companion")
    if ok and Companion then Companion.cancel(reason,id) end
    ctx.Actions.cancel(reason,id)
    local okHaul,Haul=pcall(require,"EmberRoutesProbe/Hauling/Haul")
    if okHaul and Haul then Haul.cancel(reason,id) end
end
function Probe.cancelEvery(reason)
    if Probe.pauseAllWork then Probe.pauseAllWork(reason)
    elseif Probe.cancelWork then Probe.cancelWork(reason) end
    if Probe.cancelEveryCompanion then Probe.cancelEveryCompanion(reason)
    elseif Probe.cancelCompanion then Probe.cancelCompanion(reason)
    else
        local ok,Companion=pcall(require,"EmberRoutesProbe/Settlement/Companion")
        if ok and Companion then Companion.cancelAll(reason) end
    end
    if Probe.cancelActions then Probe.cancelActions(reason) else ctx.Actions.cancel(reason) end
    if Probe.cancelHaul then Probe.cancelHaul(reason)
    else
        local okHaul,Haul=pcall(require,"EmberRoutesProbe/Hauling/Haul")
        if okHaul and Haul then Haul.cancel(reason) end
    end
end
local fixture={ctx=ctx,npc=npc,actor=actor,object=object,item=item,square=square,stores=stores}
return {fixture=fixture,a=a,b=b,bridge=bridge,actor=actor,tick=tick,queued=queued,
    select=function(id) selected=id end,Work=Work}
