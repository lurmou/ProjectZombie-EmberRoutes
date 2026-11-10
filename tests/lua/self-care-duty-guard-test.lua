-- SelfCare duty guard: a claimed-but-unfinished ordinary job must block idle
-- STUDY/LEISURE discovery and raise the working threshold. The old gate
-- (Probe.hasPendingWork) only sees pendingReservations, so a claimed haul
-- job that is paused was misread as idle and the NPC went to FITNESS.
-- Real JobStore/LaborStore, fake native world/actions. Run under Kahlua with
-- --java-labor (personal-job creation goes through the Java commit kernel).
local checks=0 local function check(v,label) checks=checks+1 assert(v,label) end
local root={} local now=1000 local serial=0
local hunger,safe=0,true
local pendingFlag,retainedFlag,studyEnabled,leisureEnabled=false,false,true,false
getTimestampMs=function() return now end
local actor={isDead=function() return false end} getSpecificPlayer=function() return actor end
local npcs={a={isDead=function() return false end}}
for _,n in pairs(npcs) do n.getX=function() return 1 end n.getY=function() return 1 end n.getZ=function() return 0 end end
local members=dofile('tests/lua/membership-fixture.lua')(function() return {id='home'} end,{'a'})
members.a.context='SETTLEMENT'
instanceof=function(it,kind) return kind=='Food' end
local main={} local item={getID=function() return 9 end,getFullType=function() return 'Base.Apple' end,getHungChange=function() return -0.4 end,getHungerChange=function() return -0.4 end,getBaseHunger=function() return -0.4 end,isRotten=function() return false end,isBurnt=function() return false end,isPoison=function() return false end,getPoisonPower=function() return 0 end,isTainted=function() return false end,isCooked=function() return false end,isCookable=function() return false end,isbDangerousUncooked=function() return false end,isFrozen=function() return false end,isSpice=function() return false end,getRequireInHandOrInventory=function() return nil end,
    getContainer=function() return main end}
local Probe={hasPendingWork=function() return pendingFlag end} package.loaded['EmberRoutesProbe/Kernel/Boot']=Probe
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,
    id=function() serial=serial+1 return 'care'..serial end}
package.loaded['EmberRoutesProbe/Work/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,
    crafts=function() return {} end,flush=function() end}
package.loaded['EmberRoutesProbe/Crafting/CraftRecord']={records=function() return {} end,resources=function() return {} end}
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local submitted={}
local runtime={accepting=function() return true end,owns=function() return false end,
    status=function() return nil end,
    submit=function(_,spec)
        local h={state='PENDING'} submitted[#submitted+1]={spec=spec,handle=h}
        return h
    end,inspect=function(_,h) return h end,
    stopJob=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return runtime end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function(_,id) return {id=id,handle=npcs[id]} end}
package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver']={sample=function(_,id,time)
    return {hunger=hunger,thirst=0,fatigue=0,endurance=1,safe=safe,externalSafe=safe,observedAt=time}
end}
package.loaded['EmberRoutesProbe/Settlement/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/SelfCare/SelfCareResources']={
    new=function(_,npc,kind,personal)
        return {kind=kind,step=function() return {id=9,item=item,container=main,npc=npc},true end}
    end,revalidate=function() return not Store.owner(9) end}
package.loaded['EmberRoutesProbe/SelfCare/SelfCareExecution']={new=function(_,binding,job,candidate)
    return {npcId=binding.id,jobId=job.id,kind='SELF_CARE'}
end}
package.loaded['EmberRoutesProbe/Leisure/StudyService']={candidate=function(_,_,id)
    if not studyEnabled then return nil,true end
    return {id=9,item=item,container=main,npc=npcs[id],entry={id='home'},study={version=0}},true
end,valid=function() return true end}
package.loaded['EmberRoutesProbe/Leisure/LeisureService']={candidate=function()
    if not leisureEnabled then return nil,true end
    return {leisure={format=1,activity='OBSERVE',hours=1},entry={id='home'}},true
end,failed=function() end,note=function() end,consumeResume=function() return true end}
package.loaded['EmberRoutesProbe/Activity/SocialCoordinator']={withdraw=function() end,pending=function() return nil end}
EmberRoutesProbeJava={workerCount=function() return 1 end,workerIdAt=function() return 'a' end}
if ERLaborTestBridge then for name,method in pairs(ERLaborTestBridge) do EmberRoutesProbeJava[name]=method end end
local Service=require 'EmberRoutesProbe/SelfCare/SelfCare'
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'
check(Providers.register({category='dutygap',defaultPriority=3,
    discover=function() end,claim=function() return 'QUEUED' end,
    retained=function() return retainedFlag end}),'duty-gap provider registers')
Service.install()
local function tick() now=now+5000 Service.tick() end
local function submissions() return #submitted end
-- A valid format-3 HAUL job: payload PAUSED, JobStore state set by caller.
-- The haul carries item 7 on purpose: the STUDY book / food item is 9, and
-- a haul legitimately owning item 9 would make the STUDY candidate fail
-- revalidation for an unrelated reason and hide whether the guard ran.
local function haulPayload(state,delivered)
    return {id='haul-1',npcId='a',format=3,executor='ENTITY',producer='LOGISTICS',
        source='pantry',destination='crate',settlementId='home',items={7},
        manifest={{itemId=7,custodyState=delivered and 'DELIVERED' or 'UNCOLLECTED',
            sourceId='pantry',deliveryPolicy='AUTO_STORAGE',
            deliveryReceipt=delivered and {destinationId='crate',attemptId='haul-1:upgrade:7'} or nil}},
        plannedCount=1,routeRevision=0,attemptSequence=0,sequence=0,generation=0,
        state=state or 'PAUSED',reason='CREATED',phase='COLLECT',
        claims=delivered and {} or {'item:7'}}
end
local function createHaul()
    local ok,why=Jobs.current():create({id='haul-1',npcId='a',providerType='HAUL',
        scopeId='local-world',revision=1,state='PREPARING',effects='KNOWN',
        obligations={business=true},payload=haulPayload('PAUSED',false)})
    check(ok,'haul job creates: '..tostring(why))
    local job=Jobs.current():get('haul-1')
    local moved,why2=Jobs.current():update('haul-1',job.revision,{state='SUSPENDED'})
    check(moved,'paused haul reaches SUSPENDED: '..tostring(why2))
    return Jobs.current():get('haul-1')
end
local function finishHaul(job,terminal)
    local payload=haulPayload('DONE',true)
    local ok,why=Jobs.current():update('haul-1',job.revision,
        {state='SETTLING',payload=payload,obligations={}})
    check(ok,'haul settles with cleared claims: '..tostring(why))
    job=Jobs.current():get('haul-1')
    if terminal=='DONE' then
        local done,why2=Jobs.current():update('haul-1',job.revision,{state='DONE'})
        check(done,'haul reaches DONE: '..tostring(why2))
    else
        local cancelled,why2=Jobs.current():cancel('haul-1',job.revision,{state='CANCELLED'})
        check(cancelled,'haul reaches CANCELLED: '..tostring(why2))
    end
    return Jobs.current():get('haul-1')
end
local function freshWorld()
    root={} now=now+5000 members.a.context='SETTLEMENT'
    pendingFlag,retainedFlag=false,false
end
-- 1. Baseline: idle NPC discovers STUDY, then LEISURE when study is off.
local before=submissions() tick()
check(submissions()==before+1,'idle NPC discovers STUDY')
studyEnabled=false leisureEnabled=true before=submissions() freshWorld() tick()
check(submissions()==before+1,'idle NPC discovers LEISURE when study offers nothing')
studyEnabled=true leisureEnabled=false
-- 2. Claimed-but-paused haul blocks both discoveries (the reported incident:
-- a paused haul job was misread as idle and the NPC went to FITNESS).
freshWorld() local haul=createHaul() before=submissions() tick()
check(submissions()==before,'paused haul blocks STUDY discovery')
studyEnabled=false leisureEnabled=true before=submissions() freshWorld()
-- fresh world drops the haul; recreate it for the LEISURE half
haul=createHaul() tick()
check(submissions()==before,'paused haul blocks LEISURE discovery')
studyEnabled=true leisureEnabled=false
-- 3. The same haul, once DONE, releases the NPC.
freshWorld() haul=createHaul() finishHaul(haul,'DONE') before=submissions() tick()
check(submissions()==before+1,'DONE haul releases STUDY discovery')
-- 4. A CANCELLED haul also releases the NPC. Its payload state stays PAUSED,
-- so a payload.state ~= 'DONE' check would wrongly keep the NPC on duty.
freshWorld() haul=createHaul() finishHaul(haul,'CANCELLED') before=submissions() tick()
check(submissions()==before+1,'CANCELLED haul releases STUDY discovery')
-- 5. Generic provider path: Providers.retained blocks, then releases.
freshWorld() retainedFlag=true before=submissions() tick()
check(submissions()==before,'Providers.retained blocks STUDY discovery')
retainedFlag=false before=submissions() tick()
check(submissions()==before+1,'Providers.retained false releases STUDY discovery')
-- 6. The old gate still works: a pending reservation alone still blocks.
freshWorld() pendingFlag=true before=submissions() tick()
check(submissions()==before,'pending reservation still blocks STUDY discovery')
pendingFlag=false
-- 7. Working threshold: hunger 0.4 eats when idle (enter 0.25) but not when
-- a haul is claimed (working threshold 0.50), and no discovery replaces it.
freshWorld() hunger=0.4 before=submissions() tick()
check(submissions()==before+1,'hunger 0.4 eats when idle')
freshWorld() hunger=0.4 haul=createHaul() before=submissions() tick()
check(submissions()==before,'hunger 0.4 neither eats nor discovers while hauling')
hunger=0
print('PASS '..checks..' self-care duty-guard checks; body runtime mocked')
