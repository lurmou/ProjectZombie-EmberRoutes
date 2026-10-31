-- Real activity services, role adapter, SelfCareExecution, Runtime/Jobs/Claims.
-- Native body/queue callbacks are substitutes; no game or disk-save acceptance.
_ERActivityFixtureOnly=true
local f=dofile('tests/lua/activity-lifecycle-test.lua')
local Service=require 'EmberRoutesProbe/ActivityService'
local Store=require 'EmberRoutesProbe/ActivityStore'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Driver=require 'EmberRoutesProbe/Driver'
local Script=require 'EmberRoutesProbe/ActivityScripted'
local checks=0 local function check(v,m) assert(v,m) checks=checks+1 end
local queues=ISTimedActionQueue.queues
local gestures,lines=0,0
local owners={}
CharacterStat={BOREDOM='boredom',UNHAPPINESS='unhappiness',STRESS='stress'}
getText=function(key) return key end ZombRand=function() return 0 end
EmberRoutesProbeJava.socialVisible=function(a,b) return not a.dead and not b.dead end
for _,b in pairs(f.bodies) do
    local body=b
    body.emotions={boredom=40,unhappiness=20,stress=.5} body.nativeData={} body.statWrites=0 body.statTimes={}
    function body:getModData() return self.nativeData end
    function body:getStats()
        return {get=function(_,key) return body.emotions[key] end,set=function(_,key,value)
            if body.failStat==key then error('injected native stat failure') end
            body.statWrites=body.statWrites+1 body.statTimes[getTimestampMs()]=true
            local changed=body.emotions[key]~=value body.emotions[key]=value return changed
        end}
    end
    function b:faceLocationF(x,y) self.facing={x=x,y=y} end
    function b:playEmote() gestures=gestures+1 end
    function b:setVariable() end function b:clearVariable() end
    function b:addLineChatElement() lines=lines+1 end
    function b:getInventory() return {} end
end
package.loaded['TimedActions/ISBaseTimedAction']=true
package.loaded['TimedActions/ISEatFoodAction']=true package.loaded['TimedActions/ISDrinkFluidAction']=true
package.loaded['EmberRoutesProbe/WorkTransfer']={}
package.loaded['EmberRoutesProbe/CraftSupply']={}
local function remove(a) queues[a.character]={queue={}} end
ISBaseTimedAction={new=function(_,character) return {character=character,
    forceStop=function(self) self:stop() end,
    forceComplete=function(self) if self:complete() then self:perform() end end} end,perform=remove,stop=remove}
ISTimedActionQueue.add=function(a) queues[a.character]={queue={a},current=a} a:start() end
ISTimedActionQueue.hasAction=function(a) return queues[a.character] and queues[a.character].current==a end
local function args()
    local a=f.args({'a','b','c'}) a.definitionId='emberroutes:group_discussion' a.speakerId='b' a.durationHours=.05 a.rules={OBSERVE=1}
    return a
end
local function submit(e,id)
    if f.runtime:owns(id) then return end
    local ref=Service.context(id) if not ref then return end
    local candidate=Script.candidate(e,id,{id='home'},{revision=1,entryRevision=1},ref,getGameTime():getWorldAgeHours())
    if not candidate then return end
    local j=Jobs.current():peekPersonal(id)
    if not j then local new=Record.create('care-'..id,id) assert(Jobs.current():create(new)) j=Jobs.current():peek(new.id) end
    if j.payload.step~='IDLE' then return end
    local p=assert(Record.begin(j,'LEISURE')) p.step='STOP_CONFIRMED' p.activityRef=ref
    p.membershipRevision=1 p.settlementRevision=1 p.settlementId='home' p.leisure=candidate.leisure
    p.claims={require('EmberRoutesProbe/LeisureRecord').tileKey(p.leisure.point)}
    assert(Jobs.current():update(j.id,j.revision,{payload=p})) j=Jobs.current():get(j.id)
    local spec,context=require('EmberRoutesProbe/SelfCareExecution').new(f.actor,assert(Driver.bindId(f.actor,id)),j,candidate,
        function() return {nodes=16,scan=32,paths=1,containers=4} end,false,nil,function() return true end)
    assert(f.runtime:submit(spec))
    owners[id]={spec=spec,context=context}
end
local function tick(e,n)
    for _=1,n do
        f.pump(1,.001)
        for _,body in pairs(f.bodies) do local q=queues[body] if q and q.current then q.current:update() end end
        if e.state=='RUNNING' and e.stage.index==2 then for id in pairs(e.roster) do submit(e,id) end end
    end
end
local a=args()
check(Service.preview(f.actor,a)~=nil,'controlled SCRIPTED profile passes actual authority/definition preview')
local e=f.start(a)
for _=1,100 do tick(e,1) if e.stage and e.stage.index==2 then break end end
check(e.stage and e.stage.index==2 and not e.stage.sharedStart,'prepare waits for owned arrival body cleanup; role time has not begun')
check(e.organizerId=='a' and e.speakerId=='b','organizer and speaker remain separate stable identities')
for _=1,100 do tick(e,1) if e.stage.sharedStart then break end end
check(e.stage.sharedStart and e.stage.sharedEnd,'only real started role Sessions arm the common clock')
check(Jobs.current():peekPersonal('b').payload.leisure.roleDuty=='ROLE_SPEAK'
    and Jobs.current():peekPersonal('a').payload.leisure.roleDuty=='ROLE_LISTEN','role constraints feed the original individual executor')
check(not require('EmberRoutesProbe/SocialCoordinator').available('b'),'ordinary pair discovery cannot recruit a speaking role')
local old=Service.context('b')
tick(e,100)
check(e.state=='CLOSED' and e.outcome=='COMPLETED','three phases finish after real role completion and confirmed owner cleanup')
check(#e.phaseHistory==2 and e.stage.index==3 and e.stage.exitCount==3,'bounded phase history and final aggregate exit facts are retained')
check(not Service.validRef('b',old),'old phase context cannot execute after transition')
check(gestures>0 and lines>0 and not f.keys.a and not f.keys.b and not f.keys.c,'native gesture/bubble adapter ran and every body owner released')
check((e.roster.a.participationHours or 0)>0,'actual role Sessions supply participation facts')
check(e.roster.a.relief.state=='APPLIED' and f.bodies.a.emotions.boredom<40,
    'successful native role completion reaches the actual activity effect writer')
if _ERActivityReliefFixtureOnly then return {fixture=f,args=args,tick=tick,event=e} end
local interrupted=f.start(args())
for _=1,100 do tick(interrupted,1) if interrupted.stage and interrupted.stage.sharedStart then break end end
f.delay.b=true f.masks.b=1
assert(Service.cancel(f.actor,interrupted.id,interrupted.revision)) tick(interrupted,10)
check(interrupted.state~='CLOSED' and interrupted.outcome=='CANCELLED','cancel cannot bypass an unconfirmed speaker stop')
f.delay.b=false f.masks.b=0 tick(interrupted,40)
check(interrupted.state=='CLOSED','speaker stop confirmation completes cancellation without replay')
local saved=f.start(args())
for _=1,100 do tick(saved,1) if saved.stage and saved.stage.sharedStart then break end end
assert(Service.finishScenes('SAVE_INTERRUPTED')) assert(f.runtime:beginSave()) tick(saved,30)
check(f.runtime:saveReady(),'scripted roles obey the existing world save stop barrier')
assert(f.runtime:finishSave(true)) tick(saved,30)
check(saved.state=='CLOSED' and saved.outcome=='INCOMPLETE','save wind-down retains facts and never resumes the performance')
local failed=f.start(args())
for _=1,100 do tick(failed,1) if failed.stage and failed.stage.sharedStart then break end end
f.epochs.b=f.epochs.b+1 tick(failed,40)
check(failed.state=='CLOSED' and failed.outcome=='INCOMPLETE','new speaker command ends the activity without a replacement speaker')
local gap=f.start(args())
for _=1,100 do tick(gap,1) if gap.stage and gap.stage.sharedStart then break end end
f.pump(20,.001) -- engine role observations absent for two real seconds
tick(gap,100)
check(gap.state=='CLOSED' and gap.outcome=='INCOMPLETE','missing native observations cannot be backfilled as successful role time')
local planned=assert(Service.schedule(f.actor,args(),assert(Service.issue(f.actor,'home')),getGameTime():getWorldAgeHours()+1,0,1))
check(assert(Service.schedules(f.actor,'home'))[1].args.speakerId=='b','calendar snapshots retain independent speaker identity')
assert(Service.cancelSchedule(f.actor,planned.id,planned.revision))
local prepared=f.start(args()) local untilTime=getGameTime():getWorldAgeHours()+1
-- No personal role executor is submitted in this case.
while getGameTime():getWorldAgeHours()<untilTime do f.pump(1,.02) end
check(prepared.state=='CLOSED' and prepared.outcome=='INCOMPLETE','a missing role executor times out without fabricating participation')
local unknown=f.start(args())
for _=1,100 do tick(unknown,1) if unknown.stage and unknown.stage.sharedStart then break end end
owners.c.context.effects='UNKNOWN' assert(owners.c.context.persist())
tick(unknown,40)
check(unknown.state=='SETTLING' and unknown.outcome=='INCOMPLETE' and unknown.roster.c.duty.current,
    'owner-reported unknown effects retain evidence instead of completing or replaying roles')
check(not f.keys.a and not f.keys.b and unknown.roster.a.settled and unknown.roster.b.settled,
    'known participants finish cleanup independently of an unknown listener')
local Phase=require 'EmberRoutesProbe/ActivityPhaseRecord'
local stageActors={}
for i=1,32 do stageActors['npc'..i]={jobId='job'..i,participantEpoch=1} end
local bounds={id='bounded',worldId='world',controlEpoch=1,stageEpoch=1,speakerId='npc1',gatherDeadline=1,createdAt=0}
local record=assert(Phase.new(bounds,1,stageActors,1))
local malformed=Store.copy(record) malformed.index=nil malformed.id=nil
check(Phase.valid(record) and Store.scalar(record) and not Phase.valid(malformed),'32-role phase record fits the format; a missing phase identity is rejected')
stageActors.extra={jobId='extra',participantEpoch=1}
check(not Phase.new(bounds,1,stageActors,1),'scripted technical capacity rejects overflow before execution')
f.root.communityActivities=Store.copy(f.root.communityActivities)
check(Store.current() and not Store.get(e.id).stageBlocked and Store.get(e.id).stage.format==2,
    'completed format-2 phases cold-decode without resuming roles')
print('activity-scripted: '..checks..' PASS (real services/role actions/Runtime; native host mocked)')
