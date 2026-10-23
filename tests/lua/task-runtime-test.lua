local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Stop=require 'EmberRoutesProbe/TaskBusinessStop'
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local bodies={a={id='a'},b={id='b'}}
local keys,masks={},{}
local grants,moves,clears=0,0,0
local delayStop=false
local onClear
ISTimedActionQueue={queues={},add=function(action)
    local q=ISTimedActionQueue.queues[action.character] or {queue={}}
    ISTimedActionQueue.queues[action.character]=q q.queue[#q.queue+1]=action q.current=action
end,clear=function(npc)
    clears=clears+1
    if onClear then onClear() end
    ISTimedActionQueue.queues[npc]={queue={}}
end}
EmberRoutesProbeJava={
    carrierPresent=function(body) return bodies[body.id]==body end,
    carrierId=function(body) return body.id end,
    acquireBodyControl=function(body,job,generation)
        assert(not keys[body.id]) grants=grants+1
        keys[body.id]=job..':'..generation return keys[body.id]
    end,
    moveWithControl=function(body,key)
        assert(key==keys[body.id]) moves=moves+1 masks[body.id]=1 return 'MOVE_REQUESTED'
    end,
    stopWithControl=function(body,key)
        assert(key==keys[body.id])
        if not delayStop then masks[body.id]=0 end return true
    end,
    bodyStopMask=function(body,key) assert(key==keys[body.id]) return masks[body.id] or 0 end,
    releaseBodyControl=function(body,key)
        assert(key==keys[body.id] and (masks[body.id] or 0)==0) keys[body.id]=nil return true
    end,
    freezeBodyControl=function() return true end,
    thawBodyControl=function() return keys.a==nil and keys.b==nil end,
    retireBodyControl=function() return true end,
}
local function spec(id,job)
    bodies[id]=bodies[id] or {id=id}
    local state={starts=0,ticks=0,paused=false,persist=true,effects='KNOWN',valid=true}
    local binding={id=id,handle=bodies[id]}
    local value={npcId=id,jobId=job,kind='TEST',binding=binding,
        validate=function() return state.valid end,
        start=function(body) state.body=body state.starts=state.starts+1 return true end,
        tick=function() state.ticks=state.ticks+1 end,
        finished=function() return state.done==true end,
        persistFailure=function(fact) state.failure=fact.effects return state.persist end,
    }
    value.stopAdapter=function(controller,ticket)
        return Stop.new({controller=controller,ticket=ticket,npc=bodies[id],npcId=id,jobId=job,
            same=function() return true end,
            pause=function() state.paused=true return state.body.clear() end,
            effects=function() return state.effects end,
            persist=function(fact) state.saved=fact.effects return state.persist end})
    end
    return value,state
end
local function steps(runtime,n) for _=1,n do assert(runtime:step()) end end
local r=Runtime.new()
local a,old=spec('a','work')
local h=assert(r:submit(a))
check(old.starts==0 and grants==0,'submit has no effects')
steps(r,2)
check(old.starts==1 and grants==1 and r:inspect(h).state=='ACTIVE','grant before exactly one start')
check(old.body.move({}, {x=1,y=1,z=0}),'body move authorized')
local b,other=spec('b','follow') local hb=assert(r:submit(b)) steps(r,3)
check(other.starts==1 and other.ticks>0,'two NPCs progress independently')
local invalidReplacement=spec('b','invalid-replacement')
invalidReplacement.validate=function() return false end
check(not r:submit(invalidReplacement) and other.body.current(),'invalid replacement does not interrupt existing work')
local passive=spec('b','passive') passive.nonPreemptive=true
check(not r:submit(passive) and other.body.current(),'automatic non-preemptive request cannot steal an active body')
local action={character=bodies.a}
check(old.body.add(action),'owned queue admits native action')
check(not old.body.add({character=bodies.b}),'wrong NPC queue refused')
local p,nextState=spec('a','escape')
delayStop=true old.effects='UNKNOWN' old.persist=false
local hp=assert(r:submit(p))
check(not r:submit(p),'one successor candidate per NPC')
check(not old.body.move({}, {x=2,y=2,z=0}),'request fences old movement immediately')
onClear=function()
    check(not old.body.add(action),'sync stop callback cannot enqueue')
    check(not r:submit(p),'sync stop callback cannot admit successor')
    check(not r:step(),'sync stop callback cannot reenter tick')
end
steps(r,3) onClear=nil
check(nextState.starts==0 and old.paused and keys.a~=nil,'native stop not yet observed blocks successor')
masks.a=0 steps(r,2)
check(old.saved=='UNKNOWN' and nextState.starts==0,'unknown must be recorded before release')
old.persist=true steps(r,1)
check(r:inspect(h).state=='CLOSED' and nextState.starts==0,'closure does not start replacement in cleanup turn')
steps(r,2)
check(nextState.starts==1 and r:inspect(hp).state=='ACTIVE','new session only after persisted stop')
local priorClears=clears
check(not old.body.clear() and not old.body.stop() and not old.body.add(action) and not old.body.requestStop('LATE'),
    'late body cannot clear stop or queue on successor')
check(clears==priorClears and nextState.body.current(),'new owner retains body')
check(other.body.current() and r:inspect(hb).state=='ACTIVE','handoff does not affect second NPC')
check(r:beginSave(),'one save barrier')
check(not nextState.body.current() and not other.body.current(),'save fences both immediately')
check(not r:submit(p),'save closes admission')
check(not r:finishSave(true),'save waits for native sessions')
delayStop=false steps(r,4)
check(not r:finishSave(false),'failed save stays blocked')
check(r:finishSave(true),'explicit checked live recovery opens admission')
local invalid,never=spec('a','stale') invalid.validate=function() return false end
local hi,reason=r:submit(invalid)
check(not hi and never.starts==0 and reason=='CANDIDATE_CHANGED','stale resume rejected before native grant')
local changed,delayed=spec('a','changed-after-queue')
local hc=assert(r:submit(changed)) steps(r,1) delayed.valid=false steps(r,3)
check(delayed.starts==0 and r:inspect(hc).reason=='CANDIDATE_CHANGED','revalidate candidate immediately before body acquisition')
local failed,state=spec('a','error')
failed.start=function(body) state.body=body state.starts=state.starts+1 body.move({}, {}) error('after native effect') end
local hf=assert(r:submit(failed)) steps(r,4)
check(state.starts==1 and state.failure=='UNKNOWN' and r:inspect(hf).state=='CLOSED','failed start never replayed; unknown recorded')
local unchanged,noEffects=spec('a','precondition')
unchanged.start=function() return false,'PRECONDITION','UNCHANGED' end
local hu=assert(r:submit(unchanged)) steps(r,4)
check(noEffects.failure=='KNOWN' and r:inspect(hu).state=='CLOSED','explicit unchanged rejection does not invent unknown assets')
local stopped,notStarted=spec('a','pending') local hs=assert(r:submit(stopped))
check(r:stop('a','USER') and r:inspect(hs).state=='CANCELLED' and notStarted.starts==0,'cancel queued candidate without effects')
local queueBlocked,q=spec('a','lua-busy')
ISTimedActionQueue.queues[bodies.a]={queue={{}},current={}}
local hq=assert(r:submit(queueBlocked)) steps(r,4)
check(q.starts==0 and r:inspect(hq).reason=='CONTROL_DENIED','pending Lua actions block native grant')
ISTimedActionQueue.queues[bodies.a]=nil
local last,late=spec('a','retire') assert(r:submit(last)) steps(r,2)
r:retire()
check(not late.body.current() and not late.body.add(action) and not r:submit(p),'retirement fences old world')
steps(r,3)
check(keys.a==nil,'retired owner can still stop and release')
local bounded=Runtime.new()
for i=1,256 do
    local candidate=spec('n'..i,'limit-'..i)
    assert(bounded:submit(candidate))
end
local overflow=spec('a','overflow')
check(not bounded:submit(overflow),'world admission storage is bounded')
check(bounded:stop('n1','USER') and bounded:submit(overflow)~=nil,'pending cancellation frees admission capacity')
local read=bounded:status('a','overflow')
check(read and read.state=='PENDING' and not bounded:status('a','other-job'),'read model matches exact pending Job identity')
read.state='FORGED'
check(bounded:status('a','overflow').state=='PENDING' and not bounded:status('n1'),'status is detached and cancelled candidates disappear')
print('PASS '..checks..' runtime/queue checks; native bodies/save NOT RUN')
