-- P1 save orchestration. Business ledgers own assets; TaskRuntime owns bodies.
local Probe=require 'EmberRoutesProbe/Boot'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Craft=require 'EmberRoutesProbe/CraftProbe'
local Companion=require 'EmberRoutesProbe/Companion'
local Actions=require 'EmberRoutesProbe/Actions'
local Haul=require 'EmberRoutesProbe/Haul'
local Log=require 'EmberRoutesProbe/Log'
local Save={}
local active,loaded
local function roster()
    local ids={}
    local count=EmberRoutesProbeJava.workerCount()
    if count>256 then error('SAVE_ROSTER_LIMIT') end
    for i=0,count-1 do
        local id=EmberRoutesProbeJava.workerIdAt(i)
        if type(id)~='string' or id=='' then error('SAVE_NPC_ID_REQUIRED') end
        ids[#ids+1]=id
    end
    return ids
end
local function stopped(npc)
    local queues=ISTimedActionQueue and ISTimedActionQueue.queues
    if type(queues)~='table' then return false end
    local q=queues[npc]
    return not q or type(q.queue)=='table' and #q.queue==0 and q.current==nil
end
local function validReceipt(value)
    if value==nil then return true end -- Old saves keep manual recovery.
    if type(value)~='table' or value.format~=1 or type(value.id)~='string'
        or (value.state~='CAPTURED' and value.state~='BLOCKED') or type(value.byNpc)~='table' then return false end
    local count=0
    for id,r in pairs(value.byNpc) do
        count=count+1
        if count>256 or type(id)~='string' or type(r)~='table' or r.npcId~=id
            or type(r.jobId)~='string' or type(r.kind)~='string'
            or (r.effects~='KNOWN' and r.effects~='UNKNOWN') then return false end
    end
    return true
end
function Save.load()
    if Probe.prepareMembershipRecovery then Probe.prepareMembershipRecovery() end
    if Probe.resetStock then Probe.resetStock() end
    -- Normalize legacy records and rebuild every original-ID/capacity claim
    -- BEFORE the runtime may admit any observation or recovery candidate.
    Craft.prepareRecovery()
    Store.data()
    require('EmberRoutesProbe/FieldWork').prepareRecovery()
    local root=Registry.data()
    if Probe.publicDispatch then require('EmberRoutesProbe/PublicWork').prepareRecovery() end
    if not validReceipt(root.executionSave) then error('SAVE_RECOVERY_FORMAT_INVALID') end
    if Probe.prepareCareRecovery and Probe.prepareCareRecovery(root.executionSave)~=true then error('PERSONAL_RECOVERY_FAILED') end
    if require('EmberRoutesProbe/ActivityParticipant').prepareRecovery(root.executionSave)~=true then error('ACTIVITY_RECOVERY_FAILED') end
    loaded=root active=nil
    if root.executionSave and root.executionSave.state=='BLOCKED' and Probe.beforeStockSave then Probe.beforeStockSave() end
end
function Save.prepare()
    -- Preference-only scenes own no bodies/assets. Unknown activity data stays
    -- disabled and preserved; it must not block the existing world save barrier.
    require('EmberRoutesProbe/ActivityService').finishScenes('SAVE_INTERRUPTED')
    local root=Registry.data()
    if loaded~=root then Save.load() end
    if active then return active.world==root and active.runtime==Runtime.current(),'SAVE_ACTIVE' end
    if Probe.beforeStockSave then Probe.beforeStockSave() end
    local runtime=Runtime.current()
    if not runtime then return false,'ADMISSION_CLOSED' end
    local all,intents=roster(),{}
    for _,id in ipairs(all) do intents[id]=Companion.exportState(id) end
    active={world=root,runtime=runtime,ids=all,intents=intents}
    return runtime:beginSave()
end
function Save.failed(reason)
    if active and active.world~=Registry.data() then active=nil return 'WORLD_RETIRED' end
    if active then active.failed=reason end
    if Probe.beforeStockSave then Probe.beforeStockSave() end
    if active and active.world==Registry.data() then
        local receipt=active.world.executionSave
        if receipt then receipt.state='BLOCKED' receipt.reason=tostring(reason) end
        if active.opened then
            -- A recovery publisher may throw after thaw but before this normal
            -- tick returns. Re-freeze and cancel pending candidates immediately.
            active.runtime:beginSave() active.opened=false
        end
        active.runtime:finishSave(false)
    end
    if Probe.afterCraftSave then Probe.afterCraftSave(nil) end
    Log.write('PERSISTENCE','RECOVERY_BLOCKED '..tostring(reason))
    return EmberRoutesProbeJava.blockAllCheckpoints(tostring(reason))
end
local function cleanup(s,actor)
    for _,id in ipairs(s.ids) do
        local npc=EmberRoutesProbeJava.carrierFor(id,actor)
        if npc then
            -- Dedicated synchronous save capability, never an ACTIVE task body.
            -- Only already idle bodies; no movement, add, stop or queue clearing.
            local live=true
            local body={current=function()
                return live and active==s and Registry.data()==s.world
                    and EmberRoutesProbeJava.saveBodyReady(id,npc) and stopped(npc)
            end}
            body.clear=body.current -- Only confirms the queue is already empty.
            local ok,result=pcall(function()
                if not body.current() then return false end
                return Haul.cleanup(npc,body) and Actions.cleanupForHaul(npc,body)
            end)
            live=false
            if not ok or result~=true then return false end
        end
    end
    return not Actions.fixtures and #Haul.fixtures==0 and not Haul.npc
end
function Save.capture()
    local ok,why=Save.prepare()
    if not ok then return Save.failed(why) end
    local s=active
    s.failed=nil s.results=nil
    local facts,reason=s.runtime:captureSave()
    local receipt={format=1,id=Registry.id(),state='BLOCKED',byNpc=facts and facts.byNpc or {}}
    s.world.executionSave=receipt s.receipt=receipt
    for id,r in pairs(receipt.byNpc) do
        local intent=s.intents[id]
        if r.kind=='COMPANION' and intent and intent.jobId==r.jobId then r.intent=intent end
    end
    if not facts or not facts.ready then return Save.failed(reason or 'STOP_OR_EFFECTS_UNCONFIRMED') end
    local actor=getSpecificPlayer(0)
    if not actor or actor:isDead() or not cleanup(s,actor) then return Save.failed('SAVE_FIXTURE_CLEANUP_BLOCKED') end
    local results={}
    for _,id in ipairs(s.ids) do
        local intent=s.intents[id] or {}
        local result=EmberRoutesProbeJava.captureCheckpointFor(id,intent.mode or 'HOLD',intent.hasHome==true,
            intent.homeX or 0,intent.homeY or 0,intent.homeZ or 0)
        results[id]=result
        Log.write('PERSISTENCE','CAPTURE npc='..id..' '..tostring(result))
        if type(result)~='string' or not (string.find(result,'^CHECKPOINT_SAVED')
            or string.find(result,'^CHECKPOINT_EMPTY') or string.find(result,'^CHECKPOINT_RETAINED')) then
            return Save.failed('WORKER_CAPTURE_FAILED '..id..' '..tostring(result))
        end
    end
    require('EmberRoutesProbe/BusinessJobs').flush()
    receipt.state='CAPTURED'
    if not EmberRoutesProbeJava.armSaveReceipt() then return Save.failed('SAVE_RECEIPT_UNAVAILABLE') end
    s.results=results
    return 'CHECKPOINT_SAVED '..#s.ids -- Captured into ModData, not a disk receipt.
end
function Save.candidate(actor,id)
    local receipt=Registry.data().executionSave
    if not validReceipt(receipt) or not receipt or receipt.state~='CAPTURED' then return false end
    local r=receipt.byNpc[id]
    if not r or r.reason~='SAVE' or r.effects~='KNOWN' or not r.bodyStopped or not r.persisted then return false end
    if r.kind=='COMPANION' then
        if type(r.intent)~='table' or r.intent.id~=id or r.intent.jobId~=r.jobId then return false end
        return Companion.restoreState(actor,r.intent)
    elseif r.kind=='PRODUCTION' or r.kind=='CRAFT_PROBE' then
        return Craft.restoreCandidate(actor,id,r.jobId)
    elseif r.kind=='COOKING' then
        return require('EmberRoutesProbe/CookingService').wake(actor,id,r.jobId)
    elseif r.kind=='FIELD_WORK' then
        return require('EmberRoutesProbe/FieldWork').wake(actor,id,r.jobId)
    elseif r.kind=='TRANSFER' then
        local job=Store.record(id)
        if job and job.id==r.jobId and job.producer=='DELIVERY' and not job.controlUncertain and not job.activeAttempt then
            return require('EmberRoutesProbe/Work').resumeFor(actor,id)
        end
    end
    -- Transfers remain paused with their original Job/cargo. Existing logistics
    -- may submit a non-preemptive resume; diagnostics are never auto-replayed.
    return false
end
function Save.ready()
    if not active or active.world~=Registry.data() then return false,'NO_LIVE_BARRIER' end
    if active.failed then return false,active.failed end
    return active.runtime:saveReady()
end
function Save.pending()
    return active~=nil and active.results~=nil and not active.failed
end
function Save.tick(actor)
    local s=active
    if not s or not s.results or s.failed then return end
    if Registry.data()~=s.world or Runtime.current()~=s.runtime then
        active=nil return -- An old world cannot block/thaw/publish into its successor.
    end
    if not EmberRoutesProbeJava.verifySaveReceipt() then Save.failed('SAVED_RECORDS_NOT_CONFIRMED') return end
    Store.data() -- Recheck claims; resume executors additionally re-index physical originals.
    local ok,why=s.runtime:finishSave(true)
    if not ok then Save.failed(why) return end
    s.opened=true
    -- Admission only, after the synchronous native save returned to normal ticks.
    -- The captured current Job determines the source. Old retained cargo does
    -- not forbid safe follow movement; all candidates are non-preemptive.
    if Probe.afterCraftSave then Probe.afterCraftSave(s.results) end
    for _,id in ipairs(s.ids) do
        local r=s.receipt.byNpc[id]
        if r and r.kind=='COMPANION' and string.find(s.results[id] or '','^CHECKPOINT_SAVED') then Save.candidate(actor,id) end
    end
    if Probe.afterStockSave then Probe.afterStockSave() end
    Log.write('PERSISTENCE','LIVE_RECOVERY_OPEN records matched; whole-world crash consistency NOT VERIFIED')
    active=nil
end
function Save.restore(actor,id)
    if loaded~=Registry.data() then Save.load() end
    local receipt=Registry.data().executionSave
    if receipt and receipt.state=='BLOCKED' then return 'RESTORE_BLOCKED SAVE_RECONCILE_REQUIRED' end
    local result=EmberRoutesProbeJava.restoreCheckpointFor(id,actor)
    if string.find(result,'^CHECKPOINT_RESTORED') then Save.candidate(actor,id) end
    return result
end
function Save.reset() active,loaded=nil,nil end
return Save
