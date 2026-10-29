local root={} local now,serial=0,0 local md={} local dead=false
local actor={isDead=function() return dead end,getModData=function() return md end}
local npc={x=20,y=1,z=0,getX=function(s) return s.x end,getY=function(s) return s.y end,getZ=function(s) return s.z end}
local e={id='home',factionId='f',revision=1,areas={{x=0,y=0,w=10,h=10}},returnPoint={x=2,y=2,z=0,revision=1}}
local other={id='other',factionId='f',revision=1,areas={{x=30,y=0,w=10,h=10}}}
local ledger={factionId='f',entries={home=e,other=other}}
getTimestampMs=function() return now end getSpecificPlayer=function() return actor end
local loaded=true local motion='MOVING' local spec,handle,owned local follow=0 local stops=0
getCell=function() return {getGridSquare=function() return loaded and {isFree=function() return true end} or nil end} end
EmberRoutesProbeJava={workerCount=function() return 1 end,workerIdAt=function() return 'a' end,motionResult=function() return motion end}
local rt={accepting=function() return true end,owns=function() return owned==true end,status=function() end,
    stop=function() stops=stops+1 owned=false return true end,inspect=function(_,h) return {state=h.state} end,
    submit=function(_,s) assert(s.validate()) spec=s handle={state='ACTIVE'} owned=true
        assert(s.start({move=function() return true,'MOVE_REQUESTED' end})) return handle end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() serial=serial+1 return 'id'..serial end}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return ledger end,authorized=function() return not dead end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {id='a',handle=npc} end,valid=function() return true end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return rt end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Boot']={}
package.loaded['EmberRoutesProbe/BusinessJobs']={crafts=function() return {} end}
package.loaded['EmberRoutesProbe/Work']={record=function() end}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {visitNpc=function(_,id,fn)
    for _,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do if j.npcId==id then fn(j) end end
end} end}
package.loaded['EmberRoutesProbe/Companion']={startFor=function() follow=follow+1 owned=true end}
local S=require 'EmberRoutesProbe/MembershipService' local M=require 'EmberRoutesProbe/MembershipRuntime'
S.newWorld() S.register('a') M.install()
local function command(kind,target)
    local r=S.view('a') return S.request(actor,'a',{kind=kind,settlementId=target,expectedRevision=r.revision,requestId='cmd'..r.revision})
end
local function tick() now=now+201 M.tick() end
command('SETTLE','home') tick() tick()
assert(spec and S.view('a').context=='SETTLEMENT','outside settlement gets a return candidate without changing context')
local first=spec
local savedRevision=e.revision e.revision=e.revision+1
assert(not first.validate(),'changing settlement geometry invalidates an in-flight return') e.revision=savedRevision
local savedPoint=e.returnPoint e.returnPoint={x=2,y=2,z=0,revision=2}
assert(not first.validate(),'replacing a return point at the same coordinates still invalidates the old target') e.returnPoint=savedPoint
npc.x,npc.y=2,2 motion='REACHED' spec.tick() assert(spec.finished()) owned=false handle.state='CLOSED' tick()
assert(S.view('a').context=='SETTLEMENT')
npc.x=20 command('RETURN') tick() tick()
local revision=S.view('a').revision
assert(S.view('a').context=='RETURN')
npc.x=2 spec.tick() owned=false handle.state='CLOSED' tick()
assert(S.view('a').context=='SETTLEMENT' and S.view('a').revision>revision)
command('FOLLOW') tick() tick() assert(follow==1 and S.view('a').context=='FOLLOW')
dead=true tick() tick() assert(S.view('a').context=='RETURN' and S.view('a').settlementId=='home','leader death preserves membership')
dead=false md={} npc.x=20 loaded=false tick()
assert(S.view('a').reason=='TARGET_UNLOADED' and not owned,'unloaded return waits without movement')
loaded=true
root.taskJobs={byId={book={id='book',npcId='a',providerType='SELF_CARE',effects='KNOWN',
    obligations={RETURN_ORIGINALS={itemId=9}},payload={step='SETTLING',kind='STUDY',sourceId='shelf',itemId=9}}}}
command('TRANSFER','other') tick()
assert(S.view('a').reason=='OBLIGATION_PENDING' and S.view('a').settlementId=='home')
root.taskJobs.byId.book=nil tick()
assert(S.view('a').settlementId=='other','transfer commits only after existing custody completes')
first.tick() assert(S.view('a').settlementId=='other','late old return cannot overwrite new assignment')
print('Membership runtime: return candidates, explicit arrival, leader death, unloaded targets, borrowed-book handoff')
