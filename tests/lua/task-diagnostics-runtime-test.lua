-- Uses the existing real Actions/Haul modules; engine and item effects remain fakes.
local f=dofile('tests/lua/haul-test.lua')
local npc,actor,Probe,Actions,Haul=f.npc,f.actor,f.ctx.Probe,f.ctx.Actions,f.Haul
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local root,key,serial={},nil,0
local selected='npc-a'
Registry.data=function() return root end
Registry.id=function() serial=serial+1 return 'debug-job-'..serial end
local bridge=EmberRoutesProbeJava
local rawMove,rawStop=bridge.command,bridge.stopCarrier
bridge.controlledCarrier=function() return npc end
bridge.carrierFor=function(id) return id=='npc-a' and npc end
bridge.carrierId=function(body) return body==npc and 'npc-a' or '' end
bridge.selectedId=function() return selected end
bridge.acquireBodyControl=function(body,job,generation) assert(not key) key=job..':'..generation return key end
bridge.bodyStopMask=function(body,k)
    return k==key and ((body.actions:isEmpty() and 0 or 4)+(bridge.motionResult(body)=='MOVING' and 8 or 0)) or -1
end
bridge.stopWithControl=function(body,k) assert(k==key) return rawStop(body) end
bridge.releaseBodyControl=function(body,k) assert(k==key and body.actions:isEmpty()) key=nil return true end
bridge.moveWithControl=function(body,k,a,x,y,z) assert(k==key) return rawMove('move',a,x,y,z) end
bridge.retireBodyControl=function() return true end
bridge.freezeBodyControl=function() return true end
bridge.thawBodyControl=function() return key==nil end
bridge.command=function() error('diagnostic used unowned legacy movement') end
bridge.stopCarrier=function() error('diagnostic used unowned legacy stop') end
Probe.cancelWork=function() error('diagnostic directly cancelled formal work') end
Probe.cancelCompanion=function() error('diagnostic directly cancelled companion') end
local rawAdd,rawClear=ISTimedActionQueue.add,ISTimedActionQueue.clear
local latest
ISTimedActionQueue.add=function(action)
    latest=action
    local q={queue={action},current=action}
    ISTimedActionQueue.queues[action.character]=q
    local perform,stop=action.perform,action.stop
    action.perform=function(self) perform(self) if npc.actions:isEmpty() then q.queue={} q.current=nil end end
    action.stop=function(self) stop(self) if npc.actions:isEmpty() then q.queue={} end end
    rawAdd(action)
end
ISTimedActionQueue.clear=function(body)
    rawClear(body)
    local q=ISTimedActionQueue.queues[body] if q then q.queue={} end
end
Probe.controlledExecution=true Runtime.begin()
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local function tick(n) for _=1,n do f.tick(1) Runtime.current():step() end end
local function drain()
    for _=1,2000 do tick(1) if not Runtime.current():owns('npc-a') then return end end
    error('diagnostic body did not drain')
end
local stopped,incumbentBody=false,nil
local incumbentTicket
local incumbent=assert(Runtime.current():submit({npcId='npc-a',jobId='incumbent-work',kind='WORK',binding={id='npc-a',handle=npc},
    validate=function() return true end,start=function(body) incumbentBody=body return true end,
    tick=function() end,finished=function() return false end,persistFailure=function() return true end,
    stopAdapter=function(controller,ticket)
        incumbentTicket=ticket()
        return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,npc=npc,npcId='npc-a',jobId='incumbent-work',
            same=function() return true end,pause=function() stopped=true return incumbentBody.clear() end,
            effects=function() return 'KNOWN' end,persist=function() return true end})
    end}))
tick(3)
check(incumbentBody and not stopped,'incumbent has body before diagnostic admission')
check(Actions.execute(actor,'suite')=='QUEUED' and not Actions.fixtures,'queued suite creates no fixtures')
check(not stopped and key~=nil,'diagnostic submission does not synchronously clear incumbent')
drain()
check(stopped and Runtime.current():inspect(incumbent).state=='CLOSED','diagnostic starts after incumbent stopping proof')
check(Actions.batch.state=='PASSED' and #Actions.batch.records==10 and key==nil,'controlled suite verifies native fake effects and closes')
local fixture=Actions.fixtures
check(Actions.execute(actor,'pack')=='QUEUED','controlled pack accepted')
tick(3) local old=latest
check(Runtime.current():owns('npc-a'),'pack owns body')
selected='npc-b' Actions.execute(actor,'cancel')
check(Runtime.current():owns('npc-a') and Actions.isBusy(),'other selected NPC cannot cancel fixture owner')
selected='npc-a'
check(Actions.execute(actor,'cancel')=='STOP_REQUESTED','cancel only requests stop')
drain()
check(Actions.fixtures==fixture and key==nil,'cancellation keeps exact fixture set')
check(Actions.execute(actor,'pack')=='QUEUED','successor pack accepted')
tick(3) local successor=latest
old:perform() old:stop()
check(ISTimedActionQueue.queues[npc].current==successor and not npc.actions:isEmpty(),'old callbacks cannot dequeue successor')
drain()
check(fixture.cargo:getContainer()==fixture.bag,'successor transfers original fixture once')
check(Actions.execute(actor,'cleanup')=='QUEUED','fixture cleanup requires body admission') drain()
check(not Actions.fixtures and key==nil,'controlled cleanup releases fixtures')
local otherRoot=f.ctx.newContainer()
local otherNpc={getInventory=function() return otherRoot end}
local foreign=otherRoot:AddItem('OTHER_NPC_FIXTURE')
local otherFixtures={npc=otherNpc,items={foreign},ready=true}
Actions.fixtures=otherFixtures
check(Haul.execute(actor,'run')=='QUEUED' and #Haul.fixtures==0,'haul queues without allocating source items')
drain()
check(Haul.batch.state=='PASSED' and #Haul.batch.records==17 and key==nil,'controlled haul movement and all transfers finish')
check(Actions.fixtures==otherFixtures and foreign:getContainer()==otherRoot,'haul cannot clean another NPC fixture set')
Actions.fixtures=nil -- Teardown of the isolated foreign-owner sentinel.
check(Haul.execute(actor,'cleanup')=='QUEUED','haul cleanup uses same body protocol') drain()
check(#Haul.fixtures==0 and key==nil,'haul cleanup disposes only owned fixtures')
check(Actions.execute(actor,'prepare')=='QUEUED','fixture preparation is a controlled one-shot') drain()
local cargo=Actions.fixtures.cargo
npc.root:Remove(cargo)
check(Actions.execute(actor,'eat')=='QUEUED','unknown identity detected at physical evidence boundary') drain()
check(root.diagnosticRecovery.byNpc['npc-a'].ids[1] and key==nil,'unknown diagnostic originals recorded before body closes')
check(Actions.execute(actor,'prepare')~='QUEUED','unresolved diagnostic cannot mint a replacement set')
check(Actions.execute(actor,'cleanup')=='QUEUED','unresolved cleanup may be attempted explicitly') drain()
check(Actions.fixtures and root.diagnosticRecovery.byNpc['npc-a'] and key==nil,
    'missing original cleanup preserves both remaining fixtures and older receipt')
-- Explicitly restore the very same original, then allow only the cleanup command.
npc.root.items[#npc.root.items+1]=cargo cargo.container=npc.root
check(Actions.execute(actor,'cleanup')=='QUEUED','exact-original cleanup may reconcile retained diagnostic') drain()
check(root.diagnosticRecovery.byNpc['npc-a']==nil and not Actions.fixtures,'verified cleanup clears matching recovery record')
check(Actions.execute(actor,'prepare')=='QUEUED','mismatched receipt fixture accepted') drain()
root.diagnosticRecovery.byNpc['npc-a']={kind='ACTIONS',jobId='unrelated-originals',ids={99999}}
check(Actions.execute(actor,'cleanup')=='QUEUED','cleanup can dispose its verified current set') drain()
check(root.diagnosticRecovery.byNpc['npc-a'].jobId=='unrelated-originals','cleanup cannot erase a different original set')
root.diagnosticRecovery.byNpc['npc-a']=nil -- Isolated corrupted-receipt fixture teardown only.
print('PASS '..checks..' controlled diagnostic checks; engine effects mocked')
return {f=f,Runtime=Runtime,root=root,tick=tick,drain=drain,checks=checks}
