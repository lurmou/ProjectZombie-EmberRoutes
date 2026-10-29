-- Actual personal observer loop/admission/Resume protocol, fake body runtime.
local checks=0 local function check(v,label) checks=checks+1 assert(v,label) end
local root={} local now=1000 local serial=0 local stopRequests=0
local safe,hunger,offered=true,0.6,true
getTimestampMs=function() return now end
local actor={isDead=function() return false end} getSpecificPlayer=function() return actor end
local npcs={a={isDead=function() return false end},b={isDead=function() return false end}}
for _,n in pairs(npcs) do n.getX=function() return 1 end n.getY=function() return 1 end n.getZ=function() return 0 end end
local members=dofile('tests/lua/membership-fixture.lua')(function() return {id='home'} end,{'a','b'})
members.a.context='FOLLOW' members.b.context='FOLLOW'
local main={} local item={getID=function() return 9 end,getHungChange=function() return -0.4 end,
    getContainer=function() return main end}
local Probe={} package.loaded['EmberRoutesProbe/Boot']=Probe
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    id=function() serial=serial+1 return 'care'..serial end}
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,
    crafts=function() return {a={id='craft',generation=1,state='RUNNING'}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
local Store=require 'EmberRoutesProbe/LaborStore'
local status={a={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true}}
local rejected=true local submitted={}
local runtime={accepting=function() return true end,owns=function(_,id) return status[id]~=nil end,
    status=function(_,id) return status[id] end,
    submit=function(_,spec)
        if rejected then return nil,'TEST_REJECTED' end
        local h={state='PENDING'} submitted[#submitted+1]={spec=spec,handle=h}
        return h
    end,inspect=function(_,h) return h end,
    stopJob=function() stopRequests=stopRequests+1 return true end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return runtime end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) return {id=id,handle=npcs[id]} end}
package.loaded['EmberRoutesProbe/NeedsObserver']={sample=function(_,id,time)
    return {hunger=hunger,thirst=0,fatigue=0,endurance=1,safe=safe,observedAt=time}
end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='FOLLOW'} end}
local ownOnly
package.loaded['EmberRoutesProbe/SelfCareResources']={
    new=function(_,npc,kind,personal)
        ownOnly=personal
        return {kind=kind,step=function() return offered and {id=9,item=item,container=main,npc=npc},true end}
    end,revalidate=function() return not Store.owner(9) end}
local contexts={}
package.loaded['EmberRoutesProbe/SelfCareExecution']={new=function(_,binding,job,candidate)
    local s={npcId=binding.id,jobId=job.id,kind='SELF_CARE'} contexts[#contexts+1]=s return s
end}
EmberRoutesProbeJava={workerCount=function() return 2 end,workerIdAt=function(i) return i==0 and 'a' or 'b' end}
local Service=require 'EmberRoutesProbe/SelfCare'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
Service.install() Service.tick()
local job=Jobs.current():forNpc('a')[1]
check(job and job.payload.step=='IDLE' and not job.payload.resume and not Store.owner(9),
    'rejected admission rolls back prepared predecessor and unconsumed claim')
check(ownOnly,'follow discovery never visits settlement supplies')
now=5000 rejected=false Service.tick()
job=Jobs.current():forNpc('a')[1]
check(#submitted==1 and job.payload.resume.jobId=='craft' and job.payload.resume.state=='REQUESTED',
    'automatic hunger candidate captures running work before body admission')
check(Store.owner(9).taskId==job.id and Jobs.current():forNpc('b')[1].payload.step=='IDLE',
    'second NPC cannot claim the same original food')
check(Service.blocksWork('a') and not Service.prepareRemoval('a'),'personal attempt blocks public work and removal')
-- Cancellation while pending retains the relation until real predecessor stop.
submitted[1].handle.state='CANCELLED' now=7000 Service.tick()
job=Jobs.current():get(job.id)
check(job.payload.resume.state=='REQUESTED' and Store.owner(9),'pending cancellation does not discard unconfirmed original work relation')
root.executionSave={state='BLOCKED'} now=9000 Service.tick()
check(#submitted==1,'blocked world save cannot dispatch personal work')
root.executionSave=nil
local p=job.payload p.step='ACTING'
assert(Jobs.current():update(job.id,job.revision,{payload=p}))
check(Service.prepareRecovery(nil) and Jobs.current():get(job.id).effects=='UNKNOWN',
    'unconfirmed native call after reload is quarantined, never reissued')
check(not Service.prepareRemoval('a'),'unknown consumption prevents deletion of its carrier')
-- Idle study admission must not preempt already-running ordinary work.
root={} hunger=0 safe=true now=20000
members.a.context='SETTLEMENT' members.b.context='SETTLEMENT'
EmberRoutesProbeJava.workerCount=function() return 1 end
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/StudyService']={candidate=function()
    return {id=9,item=item,container=main,npc=npcs.a,entry={id='home'},study={version=0}},true
end}
local prior=#submitted
status.a={jobId='craft',kind='PRODUCTION',state='ACTIVE',started=true}
Service.tick()
check(#submitted==prior,'idle study cannot replace an ordinary work Session even if an old offer survives')
status.a=nil now=22000 Service.tick()
local studying=Jobs.current():forNpc('a','SELF_CARE')[1]
check(#submitted==prior+1 and studying.payload.kind=='STUDY' and studying.payload.step=='STOP_CONFIRMED',
    'idle study joins the existing durable personal admission and stop-confirmation path')
local p=studying.payload p.sourceId='shelf' p.step='SETTLING' p.resume=nil
assert(Jobs.current():update(studying.id,studying.revision,{payload=p,obligations={RETURN_ORIGINALS={itemId=9,sourceId='shelf'}}}))
members.a.pending={requestId='transfer'} members.a.revision=members.a.revision+1
submitted[#submitted].handle.state='CANCELLED' status.a=nil
local recoveries=#contexts
for _,at in ipairs({25000,27000,29000,31000}) do now=at Service.tick() end
check(#contexts>recoveries,'pending transfer returns a borrowed book even without hunger, thirst or a fresh STUDY grant')
print('PASS '..checks..' automatic personal admission/recovery checks; body runtime mocked')
-- The actual forced-sleep admission must reach ground fallback when no bed is
-- available; the floor stays a resource in the same personal Job.
root={} hunger=0 safe=true now=40000 members.a.pending=nil status.a=nil
members.a.revision=members.a.revision+1
EmberRoutesProbeJava.reposeWithControl=function() return true end
EmberRoutesProbeJava.reposeAtWithControl=function() return true end
EmberRoutesProbeJava.floorSleepSafe=function(_,x,y,z) return x==1 and y==1 and z==0 end
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/ReposeSites']={new=function() return {step=function() return nil,true,'SITE_UNAVAILABLE' end} end}
local beforeSleep=#submitted
assert(Service.force('a','SLEEP')) Service.tick()
local sleeping=Jobs.current():forNpc('a','SELF_CARE')[1]
check(#submitted==beforeSleep+1 and sleeping.payload.kind=='SLEEP' and sleeping.payload.floorSite.x==1,
    'forced sleep falls back to a real floor candidate instead of giving up for no bed')
check(Store.resourceOwner('repose:floor:1:1:0').taskId==sleeping.id,'floor claim belongs to the existing personal task')
print('PASS forced no-bed sleep admission and shared floor claim; native body mocked')
