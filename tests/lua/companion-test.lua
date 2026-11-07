local assertions,time=0,0
local function check(v,m) assertions=assertions+1 assert(v,m) end
local reads,starts,stops,moves=0,0,0,0
local npc={id='n',x=0}
local actor={x=6,dead=false}
function npc:getX() reads=reads+1 return self.x end
function npc:getY() return 0 end
function npc:getZ() return 0 end
function actor:getX() reads=reads+1 return self.x end
function actor:getY() return 0 end
function actor:getZ() return 0 end
function actor:isDead() return self.dead end
function actor:Say() end
function getTimestampMs() return time end
function getText(key) return key end
DebugLog={log=function() end}
package.loaded['EmberRoutesProbe/Kernel/Boot']={ready=true,hasJava=function() return true end,build={prefix='TEST'}}
package.loaded['EmberRoutesProbe/Settlement/MembershipService']={followSlot=function(id,leader,revision)
    assert(id=='n' and leader==actor and revision==1) return 2
end}
local Factory=require 'EmberRoutesProbe/Settlement/CompanionAgent'
local motion='STOPPED'
EmberRoutesProbeJava={carrierPresent=function(b) return b==npc end,carrierId=function(b) return b.id end,
    motionResult=function() return motion end,
    stopCarrier=function() error('uncontrolled stop forbidden') end,
    command=function() error('uncontrolled move forbidden') end}
local current=true
local grant={current=function() return current end,
    stop=function() stops=stops+1 motion='STOPPED' return true end,
    follow=function(leader,rank)
        check(leader==actor and rank==2,'follow receives its explicit membership slot')
        starts=starts+1 motion='FOLLOW_ACTIVE' return true,'FOLLOW_STARTED'
    end,
    move=function(leader,point)
        check(leader==actor and point.x==0,'return uses captured home')
        moves=moves+1 motion='MOVING' return true,'MOVE_REQUESTED'
    end}
local worker=Factory.new()
worker.membershipRevision=1
check(worker.execute(actor,'follow',nil,{id='n',handle=npc})=='CONTROL_REQUIRED','no body grant has no legacy fallback')
check(worker.execute(actor,'follow',grant,{id='n',handle=npc})=='FOLLOW','start controlled follow')
check(starts==1 and worker.home.x==0,'one native follow start and home capture')
local before=reads
for i=1,100 do time=i*20 worker.tick() end
check(starts==1 and reads==before,'ticks poll status without coordinate snapshots or repeated starts')
motion='FOLLOW_WAITING' time=2500 worker.tick()
check(worker.mode=='FOLLOW','native waiting keeps the macro intent')
motion='FOLLOW_WAIT_VEHICLE' time=3000 worker.tick()
check(worker.mode=='FOLLOW' and moves==0,'vehicle waiting never issues a foot chase')
local saved=worker.exportState()
check(saved.mode=='FOLLOW' and saved.id=='n' and saved.homeX==0,'export contains stable scalar intent')
check(saved.actor==nil and saved.body==nil,'export never contains native grants or leader handles')
current=false motion='FOLLOW_STALLED' time=3500 worker.tick()
check(worker.mode=='FOLLOW','old worker cannot react after its grant expires')
current=true worker.tick()
check(worker.mode=='BLOCKED' and worker.reason=='FOLLOW_STALLED' and motion=='STOPPED','failure halts owned body and records reason')
check(worker.restoreState(actor,saved,grant) and starts==2,'restoration starts a fresh controlled follower')
saved.id='replacement'
check(not worker.restoreState(actor,saved,grant),'saved intent cannot move replacement NPC')
saved.id='n'
check(worker.execute(actor,'home',grant,{id='n',handle=npc})=='RETURNING' and moves==1,'return starts the real move')
motion='REACHED' time=4000 worker.tick()
check(worker.mode=='HOLD' and worker.reason=='HOME_REACHED','return requires reached evidence')
check(worker.restoreState(actor,saved,grant),'follow can resume after a return')
actor.dead=true time=4500 worker.tick()
check(worker.mode=='HOLD' and motion=='STOPPED','leader death stops controlled movement')
actor.dead=false
check(not worker.restoreState(actor,saved,nil),'recovery cannot bypass body authorization')
local original=grant.follow
grant.follow=function() return false,'CONTROL_DENIED' end
check(worker.execute(actor,'follow',grant,{id='n',handle=npc})=='CONTROL_DENIED'
    and worker.mode=='BLOCKED','native refusal cannot be reported as an active follower')
check(not worker.restoreState(actor,saved,grant),'restore also propagates native refusal')
grant.follow=original
assert(worker.restoreState(actor,saved,grant))
time=10000
for _,state in ipairs({'FOLLOW_TRAVERSAL','FOLLOW_QUEUED','FOLLOW_YIELD_SIDE','FOLLOW_YIELD_BACK','FOLLOW_TIMEOUT','FOLLOW_PATH_FAILED'}) do
    motion=state time=time+500 worker.tick()
    check(worker.mode=='FOLLOW' and motion==state,'normal navigation state must retain the current session: '..state)
end
motion='UNRECOGNIZED_NAV_STATE' time=time+500 worker.tick()
check(worker.mode=='BLOCKED' and motion=='STOPPED','unknown native state still stops safely')
print('PASS '..assertions..' companion agent checks; native host mocked')
