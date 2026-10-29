-- Real JobStore/LaborClaims/BT/custody/execution, fake native world/actions.
local checks=0
local function check(v,label) checks=checks+1 assert(v,label) end
local root={} local time=1000 local accepted=true local nextId=0
function instanceof(item,kind) return kind=='Food' and item.amount~=nil end
getTimestampMs=function() return time end
local function list(values)
    return {size=function() return #values end,get=function(_,i) return values[i+1] end,
        contains=function(_,item) for _,v in ipairs(values) do if v==item then return true end end return false end,
        isEmpty=function() return #values==0 end}
end
local function container()
    local values={} local c={values=values}
    c.getItems=function() return list(values) end
    c.hasRoomFor=function() return true end
    return c
end
local main,source=container(),container()
local npc={getInventory=function() return main end,isDead=function() return false end,
    isOnFire=function() return false end,getSurroundingAttackingZombies=function() return 0 end,
    getCharacterActions=function() return list({}) end}
local endpoint={id='pantry',container=source,object={}}
local function food(id,where,amount)
    local item={id=id,where=where,amount=amount or 0.4}
    item.getID=function() return item.id end
    item.getContainer=function() return item.where end
    item.getFullType=function() return 'Base.Bread' end
    item.getHungChange=function() return -item.amount end
    item.getIsCraftingConsumed=function() return false end
    if where then where.values[#where.values+1]=item end
    return item
end
local function move(item,to)
    local from=item.where
    if from then for i,v in ipairs(from.values) do if v==item then table.remove(from.values,i) break end end end
    item.where=to if to then to.values[#to.values+1]=item end
end
local Registry={data=function() return root end,id=function() nextId=nextId+1 return 'id'..nextId end,
    resolve=function() return endpoint end,revalidate=function() return endpoint end,
    logistics=function() return 'STORAGE' end,accepts=function() return accepted end,inventoryChanged=function() end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
package.loaded['EmberRoutesProbe/LaborProducers']={transfer=function() return true end}
package.loaded['EmberRoutesProbe/Driver']={}
package.loaded['EmberRoutesProbe/SelfCareResources']={eligible=function() return true end,
    revalidate=function(candidate) return candidate.item:getContainer()==candidate.container end}
package.loaded['EmberRoutesProbe/CraftSupply']={returnRoute=function() return nil,'RETURN_TARGET_UNAVAILABLE' end}
package.loaded['TimedActions/ISInventoryTransferAction']=true
package.loaded['TimedActions/ISEatFoodAction']=true package.loaded['TimedActions/ISDrinkFluidAction']=true
local queued,live,retained=nil,true,true
ISTimedActionQueue={queues={[npc]={queue={}}},hasAction=function(a) return a==queued end}
local function removeQueued() queued=nil ISTimedActionQueue.queues[npc]={queue={}} end
local body={current=function() return live end,retained=function() return retained end,
    add=function(action)
        queued=action ISTimedActionQueue.queues[npc]={queue={action},current=action}
        if action.start then action:start() end return true
    end,
    clear=function() if queued then queued:stop() end removeQueued() return true end}
ISInventoryTransferAction={new=function(_,who,item,from,to)
    return {character=who,isValid=function() return item.where==from end,
        startActionAnim=function() end,update=function() end,
        perform=function() move(item,to) removeQueued() end,stop=removeQueued}
end}
local eats=0 local produce=false local partial=0.025
ISEatFoodAction={new=function(_,who,item,fraction)
    return {character=who,isValid=function() return true end,start=function() end,update=function() end,
        complete=function()
            eats=eats+1 item.amount=math.max(0,item.amount-fraction*item.amount)
            if item.amount<0.0001 then move(item,nil) end
            if produce then food(item.id+100,main,0) end
            return true
        end,perform=removeQueued,
        stop=function() item.amount=math.max(0,item.amount-partial) removeQueued() end}
end}
EmberRoutesProbeJava={carrierActive=function() return true end}
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
Transfer.reachable=function() return true end
local Execute=require 'EmberRoutesProbe/SelfCareExecution'
local budget={nodes=16,scan=32,paths=1}
local controller={inspect=function() return {state='STOPPING',npcId='a',jobId='care'} end,
    bodySnapshot=function() return {available=true,nativeStopped=true} end,stopBody=function() return true end}
local jobs=Jobs.current() Store.data()
assert(jobs:create(Record.create('care','a')))
local function begin(item,borrow,fraction)
    live,retained=true,true accepted=true
    local job=jobs:get('care')
    local p=assert(Record.begin(job,'EAT',job.payload.resume))
    p.step='STOP_CONFIRMED' p.claims={'item:'..item.id} p.itemId=item.id p.fraction=fraction or 0.25
    if borrow then p.sourceId='pantry' end
    local obligations=borrow and {RETURN_ORIGINALS={itemId=item.id,sourceId='pantry'}} or {}
    assert(jobs:update(job.id,job.revision,{payload=p,obligations=obligations}))
    job=jobs:get('care') assert(Store.claimPersonal(job))
    local spec,c=Execute.new({}, {id='a',handle=npc},job,
        {id=item.id,item=item,container=item.where,endpoint=borrow and endpoint or nil},function() return budget end)
    assert(spec.validate()) assert(spec.start(body))
    return spec,c
end
local function tick(spec)
    budget={nodes=16,scan=32,paths=1} spec.tick()
end
local function native()
    assert(queued,'native action expected')
    local action=queued
    if action.complete then action:complete() end
    action:perform()
end
local function stop(spec)
    live=false
    local adapter=spec.stopAdapter(controller,function() return {} end)
    assert(adapter.requestStop('SAVE'))
    local fact=adapter.observeStop()
    assert(fact.bodyStopped)
    assert(adapter.persistEffects(fact))
    assert(adapter.persistEffects(fact),'effect persistence must be idempotent if native release needs another observation')
    retained=false return fact
end
local bread=food(1,source)
local spec,c=begin(bread,true)
tick(spec) check(queued and eats==0,'take precedes consumption') native()
tick(spec) native() check(eats==1,'native consumption once')
tick(spec) native() tick(spec)
check(spec.finished() and bread.where==source,'leftover original returned before completion')
check(stop(spec).effects=='KNOWN','intentional return is not unknown consumption')
local saved=jobs:get('care')
check(saved.payload.step=='IDLE' and #saved.payload.claims==0 and not Store.owner(1),'completed personal routine releases only its claims')
local resume={jobId='old',kind='PRODUCTION',epoch=0,state='STOP_CONFIRMED',generation=7}
saved.payload.resume=resume assert(jobs:update(saved.id,saved.revision,{payload=saved.payload}))
local partialFood=food(2,main)
spec,c=begin(partialFood,false) tick(spec)
check(stop(spec).effects=='KNOWN' and math.abs(partialFood.amount-0.375)<0.00001,'cancelled native action records actual partial effect')
saved=jobs:get('care')
check(saved.payload.consumption.stopped and saved.payload.step=='IDLE' and saved.payload.resume.jobId=='old',
    'partial effect and original work relation survive together')
spec,c=begin(partialFood,false) tick(spec)
saved=jobs:get('care') saved.payload.resume.state='INVALIDATED'
assert(jobs:update(saved.id,saved.revision,{payload=saved.payload}))
native() tick(spec) stop(spec)
check(jobs:get('care').payload.resume.state=='INVALIDATED','effect callbacks preserve concurrent user override')
produce=true local last=food(3,source,0.1)
spec,c=begin(last,true,1) tick(spec) native() tick(spec) native() tick(spec)
check(Store.owner(103) and Store.owner(103).taskId=='care','native empty container joins the same claim authority')
native() tick(spec) stop(spec)
check(last.where==nil and c.items[103].where==source and not Store.owner(103),'depleted food is not recreated; original native output returned')
produce=false local blocked=food(4,source)
spec,c=begin(blocked,true) tick(spec) native() tick(spec) native()
accepted=false tick(spec)
check(spec.finished() and blocked.where==main,'filter failure stops before invalid return')
check(stop(spec).effects=='KNOWN','known return failure is not invented consumption uncertainty')
saved=jobs:get('care')
check(saved.payload.step=='SETTLING' and Store.owner(4) and saved.obligations.RETURN_ORIGINALS,
    'unavailable return retains custody and obligation without body ownership')
local recovery=Execute.new({}, {id='a',handle=npc},saved,nil,function() return budget end,true,{[4]=blocked})
accepted=true live=true retained=true assert(recovery.start(body)) tick(recovery) native() tick(recovery) stop(recovery)
check(jobs:get('care').payload.step=='IDLE' and blocked.where==source and eats==4,'recovery returns leftovers without eating again')
local alternative={id='other',container=container(),object={}}
Registry.resolve=function(id) return id=='other' and alternative or endpoint end
Registry.accepts=function(ep) return ep==alternative or accepted end
package.loaded['EmberRoutesProbe/CraftSupply'].returnRoute=function()
    return {step=function() return alternative,true end}
end
local rerouted=food(70,source)
spec,c=begin(rerouted,true) tick(spec) native() tick(spec) native() accepted=false
tick(spec) native() tick(spec) stop(spec)
check(rerouted.where==alternative.container and jobs:get('care').payload.destinations['70']=='other',
    'rejected source filter routes and records the same original in another compatible store')
check(not Store.owner(70) and jobs:get('care').payload.step=='IDLE','alternate delivery settles custody without another consumption')
accepted=true
local stale=food(5,main) spec,c=begin(stale,false)
root={} check(not spec.validate(),'retired world cannot act on originals')
-- End-to-end stop receipt -> personal BT -> exact predecessor restoration with
-- real TaskRuntime/Controller/Sessions, retaining only native host doubles.
local Driver=package.loaded['EmberRoutesProbe/Driver']
Driver.valid=function(binding) return binding.id=='a' and binding.handle==npc end
Driver.acquireControl=function(binding) return {binding=binding} end
Driver.stopEvidence=function() return {available=true,nativeStopped=queued==nil} end
Driver.stopControlled=function() return queued==nil end
Driver.releaseControl=function() return queued==nil end
ISTimedActionQueue.add=function(action)
    queued=action ISTimedActionQueue.queues[npc]={queue={action},current=action}
    if action.start then action:start() end
end
ISTimedActionQueue.clear=function() if queued then queued:stop() end removeQueued() end
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Resume=require 'EmberRoutesProbe/TaskResume'
local runtime=Runtime.new({stopped=Resume.stopped})
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return runtime end}
local original={id='original-craft',generation=1,state='RUNNING'}
package.loaded['EmberRoutesProbe/BusinessJobs'].crafts=function() return {a=original} end
local cap local resumeCount=0
local predecessor={npcId='a',jobId=original.id,kind='PRODUCTION',binding={id='a',handle=npc},
    validate=function() return true end,start=function(body) cap=body original.state='RUNNING' return true end,
    tick=function() end,finished=function() return false end,persistFailure=function() return true end}
predecessor.stopAdapter=function(ctrl,ticket)
    return require('EmberRoutesProbe/TaskBusinessStop').new({controller=ctrl,ticket=ticket,
        npc=npc,npcId='a',jobId=original.id,same=function() return true end,
        pause=function(reason)
            original.state='PAUSED' original.reason=reason original.generation=original.generation+1
            return cap.clear()
        end,effects=function() return 'KNOWN' end,persist=function() return true end})
end
package.loaded['EmberRoutesProbe/Production']={execute=function(_,command,_,id,options)
    assert(command=='resume' and id=='a' and options.nonPreemptive)
    predecessor.nonPreemptive=true
    local h=runtime:submit(predecessor) if not h then return 'WAIT' end
    resumeCount=resumeCount+1 return 'QUEUED'
end}
local running=assert(runtime:submit(predecessor)) runtime:step() runtime:step()
jobs=Jobs.current() Store.data() assert(jobs:create(Record.create('care2','a')))
local fresh=food(20,main)
local j=jobs:get('care2') local p=assert(Record.begin(j,'EAT'))
p.itemId=20 p.claims={'item:20'} p.fraction=0.25
assert(jobs:update(j.id,j.revision,{payload=p}))
assert(Resume.prepare({},'a','care2')) j=jobs:get('care2') assert(Store.claimPersonal(j))
local life=Execute.new({}, {id='a',handle=npc},j,{id=20,item=fresh,container=main},function() return budget end)
local living=assert(runtime:submit(life))
for _=1,20 do
    budget={nodes=16,scan=32,paths=1} runtime:step()
    if queued then native() end
end
check(runtime:inspect(running).state=='CLOSED' and runtime:inspect(living).state=='CLOSED',
    'real runtime closes predecessor before granting and finishing personal body')
check(original.state=='PAUSED' and original.reason=='SELF_CARE' and jobs:get('care2').payload.step=='IDLE',
    'real business stop reason and personal cleanup coexist')
assert(not Resume.resume({},'a','care2')) runtime:step() runtime:step()
check(Resume.resume({},'a','care2') and resumeCount==1 and original.state=='RUNNING'
    and jobs:get('care2').payload.resume.state=='RESTORED','same original craft starts once after self-care')
print('PASS '..checks..' integrated personal BT/custody/stop checks; native world mocked')
local Custody=require 'EmberRoutesProbe/SelfCareCustody'
local held=food(999,main,0.5) local prepared=0
local oldPrepare,oldReachable=Transfer.prepareMove,Transfer.reachable
Transfer.prepareMove=function() prepared=prepared+1 return {preview=true} end
Transfer.reachable=function() return false end
local lookahead={npc=npc,actor={},payload={itemId=999,sourceId='pantry',settlementId='home'},
    items={[999]=held},budget={scan=4},effects='KNOWN'}
accepted=true Custody.prepareReturn(lookahead)
check(lookahead.returnPreview.target==endpoint and prepared==1 and held:getContainer()==main and not queued,
    'return lookahead prepares a destination while retaining original and body')
local oldRevalidate=Registry.revalidate
local supply=package.loaded['EmberRoutesProbe/CraftSupply'] local oldRoute=supply.returnRoute
supply.returnRoute=function() return nil,'RETURN_TARGET_UNAVAILABLE' end
Registry.revalidate=function() return nil end accepted=false time=time+1001
Custody.prepareReturn(lookahead)
check(not lookahead.returnPreview.target and not lookahead.returnPreview.point and lookahead.effects=='KNOWN'
    and held:getContainer()==main,'stale/full destination discards only the advisory plan')
Registry.revalidate=oldRevalidate Transfer.prepareMove,Transfer.reachable=oldPrepare,oldReachable
supply.returnRoute=oldRoute
print('PASS original return lookahead and stale-destination fallback; no early body/asset effect')
