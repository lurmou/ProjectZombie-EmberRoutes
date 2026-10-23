-- Real runtime/controller/save coordinator; world, ledgers and disk boundary faked.
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local root,serial,key,frozen,mask,paused={},0,nil,false,0,false
local starts,ticks,captures,reads,resumes,rebuilt=0,0,0,0,0,false
local diskId,captureFails,stopDelayed,cleanupFails
local npc={}
local actor={isDead=function() return false end,getCurrentSquare=function() return {} end,Say=function() end}
function getSpecificPlayer() return actor end
function isClient() return false end function isServer() return false end
local Probe={ready=true,enabled=true,controlledExecution=true,hasJava=function() return true end}
package.loaded['EmberRoutesProbe/Boot']=Probe
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local Registry={data=function() return root end,id=function() serial=serial+1 return 'id-'..serial end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
local Store={data=function() rebuilt=true return root.labor end,
    record=function(id) return root.labor and root.labor[id] end}
package.loaded['EmberRoutesProbe/LaborStore']=Store
local Craft={prepareRecovery=function() Store.data() end,record=function(id) return root.craft and root.craft[id] end}
package.loaded['EmberRoutesProbe/CraftProbe']=Craft
local Companion={exportState=function() return {id='a',jobId='follow-job',mode='FOLLOW',hasHome=true,homeX=2,homeY=3,homeZ=0} end}
package.loaded['EmberRoutesProbe/Companion']=Companion
local oldCapability
local Actions={cleanupForHaul=function(expected,body)
    check(expected==npc and frozen and not key and body.current() and body.clear(),'cleanup only under verified frozen-idle system access')
    check(not body.add and not body.move and not body.stop,'save cleanup has no task authority')
    oldCapability=body return not cleanupFails
end}
local Haul={fixtures={},cleanup=function(expected,body) return expected==npc and body.current() end}
package.loaded['EmberRoutesProbe/Actions']=Actions package.loaded['EmberRoutesProbe/Haul']=Haul
Probe.beforeStockSave=function() paused=true end
Probe.afterStockSave=function() paused=false resumes=resumes+1 end
Probe.resetStock=function() paused=false end
ISTimedActionQueue={queues={},clear=function(body) ISTimedActionQueue.queues[body]={queue={}} end}
EmberRoutesProbeJava={
    workerCount=function() return 1 end,workerIdAt=function() return 'a' end,
    carrierFor=function() return npc end,carrierPresent=function(b) return b==npc end,carrierId=function() return 'a' end,
    acquireBodyControl=function(_,job,generation) assert(not key and not frozen) key=job..generation return key end,
    bodyStopMask=function(_,k) return k==key and mask or -1 end,
    releaseBodyControl=function(_,k) assert(k==key and mask==0) key=nil return true end,
    stopWithControl=function(_,k) assert(k==key) if not stopDelayed then mask=0 end return true end,
    freezeBodyControl=function() frozen=true return true end,
    thawBodyControl=function() if key then return false end frozen=false return true end,
    retireBodyControl=function() frozen=true return true end,
    saveBodyReady=function(_,b) return frozen and b==npc and not key and mask==0 end,
    captureCheckpointFor=function()
        check(frozen and not key and paused,'stock admission and task grants frozen before capture')
        captures=captures+1 return captureFails and 'CHECKPOINT_BLOCKED injected' or 'CHECKPOINT_SAVED'
    end,
    armSaveReceipt=function() assert(root.executionSave.id) return true end,
    verifySaveReceipt=function() reads=reads+1 return diskId==root.executionSave.id end,
    blockAllCheckpoints=function() return 'CHECKPOINT_BLOCKED' end,
    restoreCheckpointFor=function(id) check(rebuilt and id=='a','claims rebuilt before stable-id body restore') return 'CHECKPOINT_RESTORED' end,
}
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Stop=require 'EmberRoutesProbe/TaskBusinessStop'
local Save=require 'EmberRoutesProbe/TaskPersistence'
local current
local function submit(job,kind)
    local c={job=job,kind=kind,unknown=false}
    local h,why=Runtime.current():submit({npcId='a',jobId=job,kind=kind,binding={id='a',handle=npc},
        nonPreemptive=true,captureStop=true,validate=function() return true end,
        start=function(body) check(rebuilt,'ledger loaded before task grant') c.body=body starts=starts+1 return true end,
        tick=function() ticks=ticks+1 end,finished=function() return false end,
        stopAdapter=function(controller,ticket)
            return Stop.new({controller=controller,ticket=ticket,npc=npc,npcId='a',jobId=job,
                same=function() return true end,pause=function(reason) c.reason=reason return c.body.clear() end,
                effects=function() return c.unknown and 'UNKNOWN' or 'KNOWN' end,
                persist=function(fact) c.saved=fact.effects return true end})
        end,persistFailure=function(fact) c.saved=fact.effects return true end})
    current=c return h,why,c
end
Companion.restoreState=function(_,intent) local h,why=submit(intent.jobId,'COMPANION') return h~=nil,why end
Craft.restoreCandidate=function(_,id,job)
    local r=Craft.record(id)
    if not r or r.id~=job or r.uncertain then return false end
    return submit(job,'PRODUCTION')~=nil
end
Probe.afterCraftSave=function(results)
    if results and root.craft then
        local r=root.craft.a
        if r then Craft.restoreCandidate(actor,'a',r.id) end
    end
end
local function reset()
    Runtime.reset() Save.reset()
    key=nil frozen=false mask=0 diskId=nil root={} rebuilt=false
    captureFails=false stopDelayed=false cleanupFails=false
    Runtime.begin() Save.load()
end
local function step(n) for _=1,n do Runtime.current():step() end end
reset()
local h,_,c=submit('follow-job','COMPANION') step(2)
local before=ticks
check(string.find(Save.capture(),'^CHECKPOINT_SAVED') and c.saved=='KNOWN','one-shot save reconciles current owner without tick loop')
check(ticks==before and frozen and paused and not key,'OnSave never advances business or resumes stock')
check(not oldCapability.current() and not oldCapability.clear(),'save cleanup capability revoked before returning')
check(not Runtime.current():submit({}),'save admission remains closed')
diskId=root.executionSave.id
local oldStarts=starts
Save.tick(actor)
check(not frozen and not paused and starts==oldStarts,'normal tick opens only admission; restore does not execute immediately')
step(2)
check(starts==oldStarts+1 and current.job=='follow-job','follow restoration retains exact Job identity')
check(not c.body.current() and not c.body.clear(),'old body capability cannot affect restored task')

reset()
root.craft={a={id='production-job',released=false}}
submit('production-job','PRODUCTION') step(2)
Save.capture() diskId=root.executionSave.id
Save.tick(actor) step(2)
check(current.job=='production-job' and current.kind=='PRODUCTION','formal retained job resumes through runtime')
check(not Save.candidate(actor,'a'),'stale follow intent cannot become competing restore source')
check(root.craft.a.id=='production-job','recovery does not replace retained Job identity')

reset()
submit('follow-job','COMPANION') step(2)
captureFails=true
check(Save.capture()=='CHECKPOINT_BLOCKED' and root.executionSave.state=='BLOCKED','checkpoint capture failure blocks snapshot')
diskId=root.executionSave.id local priorResumes=resumes
Save.tick(actor)
check(frozen and paused and resumes==priorResumes,'failed capture never reopens stock or runtime')

reset()
submit('follow-job','COMPANION') step(2)
Save.capture() -- Disk still contains older data; an OnPostSave signal cannot substitute.
priorResumes=resumes local priorReads=reads
Save.tick(actor) Save.tick(actor)
check(frozen and paused and reads==priorReads+1 and resumes==priorResumes,'missing disk receipt blocks once without per-frame retry')

reset()
local _,_,uncertain=submit('work','PRODUCTION') step(2) uncertain.unknown=true
check(Save.capture()=='CHECKPOINT_BLOCKED' and uncertain.saved=='UNKNOWN','unknown effects persist before save rejection')
check(root.executionSave.byNpc.a.effects=='UNKNOWN' and root.executionSave.state=='BLOCKED','unknown closure never becomes clean save')

reset()
local _,_,moving=submit('moving','COMPANION') step(2) mask=8 stopDelayed=true
check(Save.capture()=='CHECKPOINT_BLOCKED' and moving.saved=='UNKNOWN','unconfirmed native stop preserves unknown obligations')
check(key and frozen and root.executionSave.byNpc.a.bodyStopped==false,'unconfirmed stop retains native grant')

reset()
submit('follow-job','COMPANION') step(2)
Save.capture() diskId=root.executionSave.id
root={} -- World replaced before the next tick.
priorResumes=resumes priorReads=reads
Save.tick(actor)
check(resumes==priorResumes and reads==priorReads and not root.executionSave,'old world cannot publish or thaw the successor')

reset()
submit('follow-job','COMPANION') step(2)
check(Save.prepare() and paused and frozen,'advance preparation freezes dispatch without native save')
step(4)
check(not key and string.find(Save.capture(),'^CHECKPOINT_SAVED'),'normally drained owner captured without replaying start')
diskId=root.executionSave.id Save.failed('NATIVE_SAVE_FAILED injected') Save.tick(actor)
check(frozen and paused,'explicit engine failure cannot be overridden by matching record file')

reset()
submit('follow-job','COMPANION') step(2)
Save.capture() diskId=root.executionSave.id
local publish=Probe.afterCraftSave
Probe.afterCraftSave=function(results) if results then error('publisher failed after thaw') end end
local published=pcall(Save.tick,actor)
check(not published,'publisher error reaches outer Persistence guard')
Save.failed('LIVE_RECOVERY_ERROR injected')
check(frozen and paused and not key,'publisher error after thaw re-freezes before any candidate executes')
Probe.afterCraftSave=publish

reset()
root.executionSave={format=1,id='loaded',state='CAPTURED',byNpc={a={npcId='a',jobId='follow-job',kind='COMPANION',
    effects='KNOWN',bodyStopped=true,persisted=true,reason='SAVE',intent=Companion.exportState()}}}
root.craft={a={id='paused-cargo-job',released=false,uncertain=true}}
Save.load()
check(Save.restore(actor,'a')=='CHECKPOINT_RESTORED','load uses stable-ID restore lifecycle')
check(not Save.candidate(actor,'a'),'a second recovery candidate cannot preempt the pending first candidate') step(2)
check(current.job=='follow-job','cold load retains saved follow Job')
check(root.craft.a.id=='paused-cargo-job' and root.craft.a.uncertain,'safe follow movement preserves unknown cargo Job rather than banning movement')
print('PASS '..checks..' unified save/runtime checks; native save/load and disk effects mocked')
