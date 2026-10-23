-- Legacy formats/drafts use installed Kahlua and HandcraftAction; engine is mocked.
local f=dofile('tests/lua/craft-probe-test.lua')
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Companion=require 'EmberRoutesProbe/Companion'
local checks,key=0,nil
local function check(value,message) checks=checks+1 assert(value,message) end
local bridge=EmberRoutesProbeJava
bridge.acquireBodyControl=function(npc,job,generation) assert(not key) key=job..':'..generation return key end
bridge.bodyStopMask=function(npc,k) return k==key and (npc.actions:isEmpty() and 0 or 4) or -1 end
bridge.stopWithControl=function(npc,k) assert(k==key) return true end
bridge.releaseBodyControl=function(npc,k) assert(k==key and npc.actions:isEmpty()) key=nil return true end
bridge.freezeBodyControl=function() return true end
bridge.thawBodyControl=function() return key==nil end
bridge.retireBodyControl=function() return true end
bridge.controlledCarrier=function() return f.npc end
bridge.motionResult=function() return f.npc.motion or 'STOPPED' end
bridge.moveWithControl=function(npc,k,actor,x,y,z)
    assert(k==key and npc.actions:isEmpty()) npc.x=x npc.motion='REACHED' return 'MOVE_REQUESTED'
end
bridge.stopCarrier=function() error('managed legacy craft used legacy stop') end
f.Probe.cancelAll=function() error('managed legacy craft bypassed controller') end
local rawAdd,rawClear=ISTimedActionQueue.add,ISTimedActionQueue.clear
ISTimedActionQueue.queues={}
ISTimedActionQueue.add=function(action)
    local q={queue={action},current=action}
    ISTimedActionQueue.queues[action.character]=q
    local perform,stop=action.perform,action.stop
    action.perform=function(self)
        perform(self)
        if q.current==self and not f.queued() then q.queue={} q.current=nil end
    end
    action.stop=function(self)
        stop(self)
        if q.current==self and not f.queued() then q.queue={} end
    end
    rawAdd(action)
end
ISTimedActionQueue.clear=function(npc)
    rawClear(npc)
    local q=ISTimedActionQueue.queues[npc] if q then q.queue={} end
end
local function fresh()
    f.Probe.controlledExecution=false Runtime.reset()
    local material,tool=f.legacyFresh()
    key=nil ISTimedActionQueue.queues={}
    Runtime.begin() f.Probe.controlledExecution=true
    return material,tool
end
local function run() return f.Craft.execute(f.actor,'run',f.object,f.npc.id,true) end
local function tick(effects)
    f.tick(false) Runtime.current():step()
    if effects and f.queued() then f.queued():perform() end
end
local function drain(effects)
    for _=1,2000 do tick(effects) if not Runtime.current():owns(f.npc.id) then return end end
    error('legacy craft body did not drain')
end
local function queued(craft)
    for _=1,500 do
        tick(false)
        local action=f.queued()
        if action and (not craft or action.craftRecipe) then return action end
        if action then action:perform() end
    end
    error('legacy craft action not reached')
end
local material,tool=fresh()
check(run()=='QUEUED','legacy order enters body admission')
check(not f.Craft.record(f.npc.id) and not f.Store.owner(material.id) and not f.object.mod.EmberRoutesCraftProbeBenchId,
    'queued request has no record, claims or bench write')
drain(true)
local record=f.Craft.record(f.npc.id)
check(record.format==2 and record.state=='DONE' and record.released and f.nativeCalls()==1 and key==nil,
    'format2 completes and releases body after original delivery')
check(tool.container==f.tools.container and f.products.container.items:size()==1,'same legacy tool and result delivered')
material,tool=fresh()
check(run()=='QUEUED','draft fixture accepted')
tick(false) tick(false) -- Context exists; no planning tick has claimed inputs.
check(not f.Craft.record(f.npc.id) and key~=nil,'draft has a body but no persisted record')
f.Work.pause('USER',f.npc.id) drain(false)
check(key==nil and not f.Craft.record(f.npc.id) and not f.Store.owner(material.id),'unpublished draft stops without phantom ownership')
check(f.Craft.status(f.npc.id).released,'draft remains diagnostic-only')
material,tool=fresh() check(run()=='QUEUED','draft handoff fixture accepted')
tick(false) tick(false)
check(Companion.execute(f.actor,'follow'),'follow can interrupt an unpublished draft')
for _=1,25 do tick(false) end
check(not f.Craft.record(f.npc.id) and not f.Store.owner(material.id)
    and Companion.exportState(f.npc.id).mode=='FOLLOW','draft stop is confirmed before successor moves')
material,tool=fresh()
check(run()=='QUEUED','pause/resume fixture accepted')
local old=queued(false) old:perform()
local job=f.Craft.record(f.npc.id).id
f.Work.pause('USER',f.npc.id) drain(false)
record=f.Craft.record(f.npc.id)
check(record.state=='PAUSED' and not record.released and material.container==f.npc.root and f.Store.owner(material.id),
    'paused transfer retains exact carried original')
check(f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)=='QUEUED','legacy resume requests a new body session')
local successor=queued(false)
old:stop() old:perform()
check(f.queued()==successor and f.nativeCalls()==0,'late old callbacks cannot clear successor queue')
drain(true)
check(f.Craft.record(f.npc.id).id==job and f.nativeCalls()==1 and key==nil,'same legacy job completes once after resume')
material,tool=fresh() check(run()=='QUEUED','handoff fixture accepted')
queued(true)
check(Companion.execute(f.actor,'follow'),'follow competes through shared controller')
for _=1,30 do tick(false) end
check(f.Craft.record(f.npc.id).state=='PAUSED' and f.object.occupant==nil
    and Companion.exportState(f.npc.id).mode=='FOLLOW','bench and old body released before follow starts')
check(f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)=='QUEUED','legacy resume can replace following')
drain(true) check(f.nativeCalls()==1 and key==nil,'follow-to-legacy handoff produces once')
material,tool=fresh() check(run()=='QUEUED','unknown fixture accepted')
local action=queued(true) f.setMode('consume_error') action:perform() drain(false)
check(f.Craft.record(f.npc.id).uncertain and not f.Craft.record(f.npc.id).released and key==nil,'unknown consumption retains obligation but closes safe body')
check(f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)=='RECONCILE_REQUIRED' and f.nativeCalls()==1,'unknown legacy commit cannot replay')
material,tool=fresh() check(run()=='QUEUED','missing original fixture accepted')
queued(false):perform() f.npc.root:Remove(material)
f.Work.pause('USER',f.npc.id) drain(false)
check(f.Craft.record(f.npc.id).uncertain and f.Store.owner(material.id) and key==nil,
    'missing exact original records UNKNOWN without losing its claim')
material,tool=fresh() check(run()=='QUEUED','resume planning fixture accepted')
queued(false):perform() f.Work.pause('USER',f.npc.id) drain(false)
check(f.Craft.execute(f.actor,'resume',nil,f.npc.id,true)=='QUEUED','resume planning accepted')
tick(false) tick(false) f.npc.root:Remove(material)
f.Work.pause('USER',f.npc.id) drain(false)
check(f.Craft.record(f.npc.id).uncertain and key==nil,'resume planning still checks previously claimed originals')
material,tool=fresh() check(run()=='QUEUED','unstarted cancel accepted')
f.Work.pause('USER',f.npc.id) drain(false)
check(not f.Craft.record(f.npc.id) and not f.Store.owner(tool.id) and key==nil,'cancelled request never starts')
material,tool=fresh() check(run()=='QUEUED','saved draft fixture accepted')
tick(false) tick(false)
local draftJob=f.Craft.status(f.npc.id).id
f.Work.pause('SAVE',f.npc.id) drain(false)
f.Craft.afterSave({[f.npc.id]='CHECKPOINT_SAVED'}) f.Craft.tickPending()
check(not f.Craft.record(f.npc.id) and f.nativeCalls()==0,'saved draft only enqueues during automatic continuation')
drain(true)
check(f.Craft.record(f.npc.id).id==draftJob and f.nativeCalls()==1,'saved draft retains job ID after actual grant')
material,tool=fresh() check(run()=='QUEUED','saved original fixture accepted')
queued(false):perform() job=f.Craft.record(f.npc.id).id
f.Work.pause('SAVE',f.npc.id) drain(false)
f.Craft.afterSave({[f.npc.id]='CHECKPOINT_SAVED'}) f.Craft.tickPending()
check(f.nativeCalls()==0 and f.Craft.record(f.npc.id).state=='PAUSED','saved original resumes asynchronously')
drain(true)
check(f.Craft.record(f.npc.id).id==job and f.nativeCalls()==1,'automatic continuation preserves original job and effect count')
material,tool=fresh() check(run()=='QUEUED','automatic recovery fixture accepted')
queued(true) f.Work.pause('SAVE',f.npc.id) drain(false)
f.Craft.afterSave({[f.npc.id]='CHECKPOINT_SAVED'})
check(Companion.execute(f.actor,'follow'),'new manual follow accepted after saved pause')
for _=1,20 do tick(false) end
f.Craft.tickPending()
for _=1,20 do tick(false) end
check(Companion.exportState(f.npc.id).mode=='FOLLOW' and f.nativeCalls()==0,'automatic old recovery cannot steal newer manual body')
-- Old format1 loans only return existing originals to their original owner.
material,tool=fresh()
f.materials.container:Remove(material) f.npc.root:AddItem(material)
f.tools.container:Remove(tool) f.npc.root:AddItem(tool)
record={format=1,id='legacy-loan',npcId=f.npc.id,requester=f.actor.id,benchId='old-bench',generation=1,
    state='PAUSED',phase='COLLECTING',released=false,materialId=material.id,toolId=tool.id,outputIds={}}
f.Craft.record(f.npc.id) -- Initialize the legacy persisted-record envelope.
f.registry.data().craftProbes.byNpc[f.npc.id]=record
local actorInventory=f.actor.getInventory f.actor.getInventory=function(self) return self.root end
check(f.Craft.execute(f.actor,'return',nil,f.npc.id,true)=='QUEUED','format1 recovery enters shared admission')
drain(true)
check(record.state=='CANCELLED' and record.released and material.container==f.actor.root and tool.container==f.actor.root
    and f.nativeCalls()==0 and key==nil,'format1 returns original loans without recreating or crafting')
f.actor.getInventory=actorInventory
print('PASS '..checks..' controlled legacy craft checks; installed action Lua, native effects mocked')
