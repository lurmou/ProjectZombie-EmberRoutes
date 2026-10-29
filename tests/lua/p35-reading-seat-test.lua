local root,now={},0
getTimestampMs=function() return now end
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
package.loaded['EmberRoutesProbe/Boot']={}
package.loaded['EmberRoutesProbe/CraftSupply']={}
package.loaded['EmberRoutesProbe/WorkTransfer']={}
package.loaded['EmberRoutesProbe/LeisureService']={note=function() end}
EmberRoutesProbeJava={moveSeatWithControl=function() end}
local object={} local proof={id='chair',partId='part',revision=1,parts={{id='part',x=2,y=2,z=0}}}
local hasSeat,blocked=false,false
package.loaded['EmberRoutesProbe/ReposeSites']={new=function(_,_,_,_,_,options)
    assert(options.maxDistance==nil and not options.sameFloor and options.seatingOnly and options.excludeBeds)
    if options.preferredPoint then assert(options.preferredPoint.x==2 and options.preferredPoint.y==2) end
    return {step=function() return hasSeat and {} or nil,true end} end,
    prepare=function() return proof end,keys=function() return {'repose:chair:part'} end,
    resolve=function() return not blocked and {object=object,quality='averageBed'} or nil end}
local moves=0 local failPath=false
package.loaded['EmberRoutesProbe/SelfCareFurniture']={seat=function() return {run=function() moves=moves+1 return failPath and 'Failure' or 'Success' end,halt=function() end} end}
local sitting,ref,resting=false,nil,false
local exits=0
package.loaded['EmberRoutesProbe/LeisurePosture']={new=function() return {
    enter=function() sitting=true ref=object return 'Success' end,
    leave=function() exits=exits+1 return not sitting and ref==nil end} end}
local reads,stops=0,0
package.loaded['EmberRoutesProbe/StudyActions']={read=function() return {
    run=function() reads=reads+1 return reads%2==0 and 'Success' or 'Running' end,
    halt=function() stops=stops+1 return true end} end}
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Seat=require 'EmberRoutesProbe/StudySeat'
local function context(id)
    local job=Record.create(id,id) job.payload=Record.begin(job,'STUDY')
    local p=job.payload p.step='ACTING' p.settlementId='home' p.itemId=9 p.sourceId='shelf'
    p.study={version=0,leisure=true} p.claims={'item:9'}
    job.obligations={RETURN_ORIGINALS={itemId=9,sourceId='shelf'}}
    assert(Jobs.current():create(job))
    local c={payload=p,job=job,token=assert(Store.claimPersonal(job)),actor={},budget={scan=32,paths=1},
        valid=function() return true end,sameAttempt=function() return true end,
        npc={isSittingOnFurniture=function() return sitting end,getSitOnFurnitureObject=function() return ref end},
        body={retained=function() return true end,stop=function() return true end,
            repose=function(_,on) resting=on return true end}}
    c.persist=function() local live=Jobs.current():get(id) return Jobs.current():update(id,live.revision,{payload=c.payload}) end
    return c
end
local c=context('reader') hasSeat=true
local function tick(node) c.budget.scan=32 c.budget.paths=1 return node.run() end
local leaf=Seat.new(c,{})
assert(tick(leaf)=='Running' and sitting and not resting and reads==1,'seat first; native reading while seated without active rest bonus')
assert(Store.resourceOwner('repose:chair:part') and Store.owner(9),'chair and original book share the existing claims authority')
assert(Record.valid(Jobs.current():get('reader')),'active seated reading is a scalar loadable record')
assert(tick(leaf)=='Running' and Store.resourceOwner('repose:chair:part'),'reading completion waits for native get-up')
sitting=false ref=nil
assert(tick(leaf)=='Success')
assert(not Store.resourceOwner('repose:chair:part') and Store.owner(9),'release only chair; book stays owed until real return')
assert(c.payload.leisureMemory.seatPreference.x==2,'released reading seat is only a serializable preference')
assert(c.payload.sourceId=='shelf' and Jobs.current():get('reader').obligations.RETURN_ORIGINALS)
-- Reuse the same attempt for a fresh optional posture; interruption must stop
-- reading first and leave the reservation until actual posture exit.
reads=0 local interrupted=Seat.new(c,{})
assert(tick(interrupted)=='Running' and sitting)
assert(not interrupted.halt() and stops==1 and Store.resourceOwner('repose:chair:part'))
sitting=false ref=nil assert(Seat.release(c))
-- No usable seat: no path, no reservation, and reading begins immediately.
hasSeat=false reads=0 local before=moves
local standing=Seat.new(c,{}) assert(tick(standing)=='Running' and reads==1 and moves==before)
assert(c.payload.readingSite==nil and Store.owner(9))
print('P3.5 reading seats: nearby selection, shared book/seat claims, async exit, stop-before-get-up, save record, standing fallback')

hasSeat=true failPath=true reads=0
local failed=Seat.new(c,{})
assert(tick(failed)=='Running' and reads==0,'failed approach must stop before stand-reading fallback')
assert(tick(failed)=='Running' and not Store.resourceOwner('repose:chair:part'),'failed seat releases its reservation after exit evidence')
assert(tick(failed)=='Running' and reads==1 and Store.owner(9),'fallback starts the same original book once')
assert(tick(failed)=='Success' and reads==2,'fallback can finish without retrying the unreachable seat')
print('P3.5 reading seats: failed native approach clears only seat and falls back to the same book')

hasSeat=true failPath=true reads=0 now=0
local visits={} local blockedSnapshot
local originals={}
for i=1,3 do originals[i]={id='chair'..i,partId='part',revision=1,key='seat'..i,parts={{id='part',x=i,y=2,z=0}}} end
local sites=package.loaded['EmberRoutesProbe/ReposeSites']
-- A slow scan is still pending past the former 2-second/eight-slice cutoff.
local savedScan=sites.new local scanSteps=0
sites.new=function() return {step=function()
    scanSteps=scanSteps+1
    if scanSteps<12 then return nil,false,'SITE_OBSERVING' end
    return {},true
end} end
hasSeat=true failPath=false reads=0 now=0
local slow=Seat.new(c,{})
for i=1,11 do now=now+1000 assert(tick(slow)=='Running' and reads==0 and not sitting) end
assert(tick(slow)=='Running' and sitting and reads==1,'slow discovery eventually seats instead of misreporting no seat')
assert(tick(slow)=='Running') sitting=false ref=nil assert(tick(slow)=='Success')
sites.new=savedScan failPath=true reads=0
sites.new=function(_,_,_,_,excluded)
    blockedSnapshot=excluded
    return {step=function()
        for i=1,3 do if not excluded['seat'..i] then return {key='seat'..i,index=i},true end end
        return nil,true
    end}
end
sites.prepare=function(row) visits[#visits+1]=row.index return originals[row.index] end
sites.keys=function(p) return {'repose:'..p.id..':'..p.partId} end
local retried=Seat.new(c,{})
for i=1,2 do
    assert(tick(retried)=='Running' and reads==0)
    assert(tick(retried)=='Running' and c.payload.readingSite==nil and Store.owner(9))
    now=now+1000
end
failPath=false
assert(tick(retried)=='Running' and sitting and reads==1)
assert(#visits==3 and visits[1]==1 and visits[2]==2 and visits[3]==3,'retry excludes each failed seat and can sit at the third')
assert(tick(retried)=='Running') sitting=false ref=nil assert(tick(retried)=='Success')
assert(not Store.resourceOwner('repose:chair3:part') and Store.owner(9))
-- All three fail: fall back without a fourth attempt; no duplicate reading.
visits={} failPath=true reads=0
local capped=Seat.new(c,{})
for i=1,3 do
    assert(tick(capped)=='Running') assert(tick(capped)=='Running') now=now+1000
end
assert(tick(capped)=='Running' and reads==1 and #visits==3,'three failed seats then standing, never an unbounded retry')
assert(tick(capped)=='Success')
print('P3.5 alternate seats: stop/release before retry, exclude originals, third-seat success, hard retry limit')
