-- Existing real scripted lifecycle and owner seam; only native Stats/ModData
-- and body callbacks substituted. No native disk/gameplay acceptance claim.
_ERActivityReliefFixtureOnly=true
local s=dofile('tests/lua/activity-scripted-test.lua')
local f=s.fixture local Effects=require 'EmberRoutesProbe/ActivityRelief'
local Record=require 'EmberRoutesProbe/ActivityReliefRecord'
local Service=require 'EmberRoutesProbe/ActivityService'
local Store=require 'EmberRoutesProbe/ActivityStore'
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local function near(a,b) return math.abs(a-b)<.000001 end
local function complete(e) s.tick(e,160) return e end
local function writes() local n=0 for _,b in pairs(f.bodies) do n=n+b.statWrites end return n end
local e=s.event local r=e.roster.a.relief local body=f.bodies.a
check(near(body.emotions.boredom,40-6*r.hours) and near(body.emotions.unhappiness,20-3*r.hours)
    and near(body.emotions.stress,.5-.02*r.hours) and near(r.hours,.05),
    'short target receives actual hours / fixed one hour, never a full-event payout')
local n=writes() Effects.budget(2)
check(Effects.step(e,'a',true) and writes()==n,'same event receipt cannot repeat native writes')
local untilHours=body.nativeData.EmberRoutesSpeechRelief.untilHours
local second=complete(f.start(s.args()))
check(second.state=='CLOSED' and second.roster.a.relief.reason=='COOLDOWN' and writes()==n
    and body.nativeData.EmberRoutesSpeechRelief.untilHours==untilHours,'new event ID cannot evade or extend the independent reward cooldown')
local originalBudget=Effects.budget
Effects.budget=function() originalBudget(0) end
local delayed=f.start(s.args())
for _=1,180 do s.tick(delayed,1) if delayed.reliefPrepared then break end end
check(delayed.reliefPrepared and delayed.reliefAt<untilHours,'cooldown eligibility freezes before delayed settlement')
f.pump(1,3) Effects.budget=originalBudget complete(delayed)
check(delayed.roster.a.relief.reason=='COOLDOWN' and writes()==n,'waiting beyond expiry cannot backfill a reward that was cooling at completion')
f.pump(1,3)
for _,b in pairs(f.bodies) do b.emotions={boredom=0,unhappiness=0,stress=0} end
local zero=complete(f.start(s.args()))
check(zero.roster.a.relief.reason=='NO_CHANGE' and writes()==n
    and body.nativeData.EmberRoutesSpeechRelief.untilHours==untilHours,'all-zero emotions consume no new cooldown')
for _,b in pairs(f.bodies) do b.emotions={boredom=40,unhappiness=20,stress=.5} end
local cancelled=f.start(s.args())
for _=1,80 do s.tick(cancelled,1) if cancelled.stage and cancelled.stage.sharedStart then break end end
assert(Service.cancel(f.actor,cancelled.id,cancelled.revision)) complete(cancelled)
check(cancelled.state=='CLOSED' and cancelled.roster.a.relief.state=='SKIPPED' and writes()==n,
    'cancellation gives no partial reward')
Effects.budget=function() originalBudget(0) end
local saving=f.start(s.args())
for _=1,180 do s.tick(saving,1) if saving.reliefPrepared then break end end
check(saving.reliefPrepared and saving.roster.a.relief.state=='PREPARED','effects are prepared only after completed body/stage cleanup')
assert(Service.finishScenes('SAVE_INTERRUPTED')) Effects.budget=originalBudget complete(saving)
check(saving.state=='CLOSED' and saving.roster.a.relief.reason=='SAVE_INTERRUPTED' and writes()==n,
    'save barrier skips prepared effects and never executes native stat writes')
f.bodies.b.failStat='unhappiness'
local partial=complete(f.start(s.args()))
check(partial.state=='SETTLING' and partial.roster.b.relief.state=='UNKNOWN'
    and f.bodies.b.nativeData.EmberRoutesSpeechRelief.state=='UNKNOWN','partial native write is retained as unknown in both owners')
check(partial.roster.a.relief.state=='APPLIED' and partial.roster.c.relief.state=='APPLIED'
    and not f.keys.a and not f.keys.b and not f.keys.c,'unknown effect does not retain or reacquire any participant body')
n=writes() f.bodies.b.failStat=nil complete(partial)
check(writes()==n,'subsequent ticks cannot replay a partial unknown write')
local detail=assert(Service.detail(f.actor,partial.id))
check(detail.roster.b.effectsUnknown and detail.counts.unknown==1,'player projection reports unresolved physiological effect')
local capacity={}
for i=1,32 do
    capacity['npc'..i]={joined=true,participationHours=24,participantEpoch=1,duty={lastStatus='SUCCEEDED'}}
end
local capped={reliefVersion=1,scriptProfile='SPEECH_V1',outcome='COMPLETED',roster=capacity}
Record.prepare(capped,5)
check(Record.valid(capped) and capped.roster.npc1.relief.hours==1 and Store.scalar(capped),
    '32 compact versioned receipts fit the scalar envelope and long events cap at one hour')
capped.roster.npc1.relief.state='APPLYING' Record.interrupt(capped,'LOAD_INTERRUPTED')
check(capped.roster.npc1.relief.state=='UNKNOWN' and capped.roster.npc2.relief.state=='SKIPPED' and Record.pending(capped),
    'recovery quarantines applying and discards prepared effects without replay')
f.root.communityActivities=Store.copy(f.root.communityActivities)
assert(Store.current())
check(Store.get(partial.id).state~='CLOSED' and Store.get(partial.id).roster.b.relief.state=='UNKNOWN',
    'cold decode cannot close or retire an unresolved event')
Store.get(e.id).reliefVersion=999 Store.get(e.id).roster.a.relief='unsupported receipt'
f.root.communityActivities=Store.copy(f.root.communityActivities) assert(Store.current())
local unsupported=assert(Service.detail(f.actor,e.id))
check(Store.get(e.id).state~='CLOSED' and unsupported.roster.a.relief.state=='UNKNOWN',
    'unknown effect versions preserve evidence and project a safe diagnostic instead of replaying or crashing UI')
local timestamps={}
for id,b in pairs(f.bodies) do for at in pairs(b.statTimes) do
    timestamps[at]=timestamps[at] or {} timestamps[at][id]=true
end end
local bounded=true
for _,ids in pairs(timestamps) do local count=0 for _ in pairs(ids) do count=count+1 end if count>2 then bounded=false end end
check(bounded,'original Pump permits at most two native effect candidates per tick')
print('activity-relief: '..checks..' PASS (real activity lifecycle; native Stats/body substituted)')
