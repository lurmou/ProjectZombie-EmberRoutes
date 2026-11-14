local S=require 'EmberRoutesProbe/Settlement/MembershipService'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Policy=require 'EmberRoutesProbe/Settlement/MembershipPolicy'
local Config=require 'EmberRoutesProbe/Kernel/TickConfig'
local Schedule=require 'EmberRoutesProbe/Work/LaborSchedule'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local cached={}
local function use(name)
    if not cached[name] then cached[name]=require('EmberRoutesProbe/'..name) end
    return cached[name]
end
local M={}
local world,rows,cursor,nextAt=nil,{},0,0
local retired=Schedule.new()
-- These are projections of existing ledgers, never a second custody ledger.
function M.obligations(id)
    local result={}
    use('Runtime/TaskJobs').current():visitNpc(id,function(job)
            if job.effects=='UNKNOWN' then result[#result+1]={kind='EFFECT_UNKNOWN',jobId=job.id} end
            for key,value in pairs(job.obligations or {}) do
                result[#result+1]={kind=key,jobId=job.id,itemId=type(value)=='table' and value.itemId or nil,
                    sourceId=type(value)=='table' and value.sourceId or nil}
            end
            local p=job.payload or {}
            if job.providerType=='SELF_CARE' and p.step~='IDLE' and p.sourceId then
                result[#result+1]={kind='BORROWED_ITEM',itemId=p.itemId,sourceId=p.sourceId,jobId=job.id,count=1,
                    fullType=p.reading and p.reading.fullType}
            end
    end)
    local ledger=Registry.data().obligations
    for _,obligation in pairs(ledger and ledger.byId or {}) do
        if obligation.npcId==id and obligation.state~='SETTLED' and obligation.type=='FURNACE_DUTY' then
            result[#result+1]={kind='furnace',jobId=obligation.jobId}
        end
    end
    local craft=use('Work/BusinessJobs').crafts()[id]
    if craft and not craft.released then result[#result+1]={kind='CRAFT_PENDING',jobId=craft.id} end
    local work=use('Work/Work') local haul=work and work.record and work.record(id)
    if haul and haul.state~='DONE' then result[#result+1]={kind='CARGO_PENDING',jobId=haul.id} end
    local okStore,store=pcall(use,'Field/ToolCustody')
    if okStore and store and store.forNpc then
        local okCustodies,custodies=pcall(store.forNpc,id)
        if okCustodies and type(custodies)=='table' then
            for _,c in ipairs(custodies) do
                result[#result+1]={kind='TOOL_CUSTODY',custodyId=c.id,itemId=c.itemId,state=c.state,role=c.role,sourceId=c.sourceContainerId}
            end
        else
            result[#result+1]={kind='EFFECT_UNKNOWN',reason='TOOL_CUSTODY_UNAVAILABLE'}
        end
    else
        result[#result+1]={kind='EFFECT_UNKNOWN',reason='TOOL_CUSTODY_UNAVAILABLE'}
    end
    return result
end
function M.changed(id)
    local root=Registry.data()
    if world~=root then world,rows,cursor,nextAt=root,{},0,0 retired=Schedule.new() end
    local Probe=use('Kernel/Boot')
    local runtime=use('Runtime/TaskRuntime').current()
    if runtime then runtime:stop(id,'MEMBERSHIP_COMMAND') end
    if Probe.invalidateCare then Probe.invalidateCare(id,use('Runtime/TaskResume').Reasons.MEMBERSHIP_COMMAND) end
    if Probe.invalidateStudy then Probe.invalidateStudy(nil,id) end
    if Probe.invalidateLeisure then Probe.invalidateLeisure(id,'MEMBERSHIP_COMMAND') end
    local r=rows[id] or {} rows[id]=r r.retryAt=0 r.idleAt=0 nextAt=0
    local member=S.view(id)
    if member and member.pending then r.stopping=member.pending.acceptedRevision end
    if member and member.retired then retired:add(id) end
end
local function recover(id,actor,row,runtime,now)
    if not actor or actor:isDead() or runtime:owns(id) or now<(row.recoverAt or 0) then return end
    row.recoverAt=now+5000
    local record=use('Work/Work').record(id)
    if record and record.state=='PAUSED' and not record.uncertain and not record.controlUncertain then
        use('Work/Work').resumeFor(actor,id) return
    end
    local craft=use('Work/BusinessJobs').crafts()[id]
    if craft and craft.state=='PAUSED' and not craft.released and not craft.uncertain and not craft.controlUncertain then
        use('Crafting/Production').execute(actor,'resume',nil,id,{nonPreemptive=true})
        return
    end
    local okStore,store=pcall(use,'Field/ToolCustody')
    if okStore and store and store.forNpc then
        local okCustodies,custodies=pcall(store.forNpc,id)
        if okCustodies and type(custodies)=='table' then
            local hasCustody=false
            for _,c in ipairs(custodies) do
                if c.state=='HELD' and not c.activeJobId and not c.returnJobId
                    or (c.state=='PENDING_RETURN' or c.state=='RECONCILE_REQUIRED') and c.returnJobId then
                    hasCustody=true break
                end
            end
            if hasCustody then
                local okSvc,svc=pcall(use,'Field/ToolReturnService')
                if okSvc and svc and svc.recoverFor then
                    svc.recoverFor(actor,id)
                    return
                end
            end
        end
    end
end
local function advance(id,actor,runtime,now)
    local member=S.view(id) if not member or member.retired then return end
    local row=rows[id] or {} rows[id]=row
    if member.pending then
        -- Exactly once per accepted revision. Repeated stop() would cancel a legitimate custody recovery.
        if row.stopping~=member.pending.acceptedRevision then
            runtime:stop(id,'MEMBERSHIP_COMMAND') row.stopping=member.pending.acceptedRevision row.retryAt=0
        end
        local obligations=M.obligations(id)
        if #obligations>0 then recover(id,actor,row,runtime,now) end
        S.advance(id,actor,obligations,runtime:owns(id)) return
    end
    row.stopping=nil
    if now>=(row.bedCheckAt or 0) then
        row.bedCheckAt=now+Config.memberIdleMs S.reconcileBed(id)
    end
    if member.context=='FOLLOW' then
        if actor and (actor:isDead() or S.character(actor)~=member.leaderId) then
            runtime:stop(id,'LEADER_LOST')
            if not runtime:owns(id) then S.transition(id,member.revision,S.entry(id) and 'RETURN' or 'WAIT','LEADER_LOST') end
            return
        end
        if actor and not runtime:owns(id) and now>=(row.retryAt or 0) then
            row.retryAt=now+5000
            local handle,why=use('Settlement/Companion').startFor(actor,id,member.revision)
            S.note(id,not handle and why or nil)
        end
        return
    end
    if row.returning then
        if row.returning.revision~=member.revision then row.returning=nil return end
        local state=runtime:inspect(row.returning.handle)
        if state and (state.state=='CLOSED' or state.state=='CANCELLED' or state.state=='REJECTED') then
            local attempt=row.returning local arrived,reason=attempt.outcome() row.returning=nil row.retryAt=now+5000
            if arrived and member.context=='RETURN' then S.transition(id,attempt.revision,'SETTLEMENT')
            elseif reason then S.note(id,reason) end
        end
        return
    end
    if member.context~='SETTLEMENT' and member.context~='RETURN' then return end
    -- Commands/pending transfers/leader loss/return completion above stay fast.
    -- Only an already observed, settled membership uses the slow recheck.
    if member.context=='SETTLEMENT' and now<(row.idleAt or 0) then return end
    local entry,why=S.entry(id) if not entry then S.note(id,why) return end
    if not actor or actor:isDead() then return end
    local returnPointReason
    if not entry.returnPoint then
        local initialized,reason=S.ensureReturnPoint(actor,entry.id)
        if not initialized then returnPointReason=reason end
        entry=S.entry(id)
        if not entry then return end
    end
    local binding=Driver.bindId(actor,id) if not binding then S.note(id,'TARGET_UNLOADED') return end
    local n=binding.handle local inside=Policy.inside(entry,{x=n:getX(),y=n:getY()})
    if not runtime:owns(id) and #M.obligations(id)>0 then
        recover(id,actor,row,runtime,now)
        if runtime:owns(id) or inside then S.note(id,'OBLIGATION_PENDING') return end
        -- A stopped body may carry retained/unknown originals back toward its own settlement.
        -- This move neither replays their effects nor releases custody.
    end
    if inside and not runtime:owns(id) then
        if member.context=='RETURN' then S.transition(id,member.revision,'SETTLEMENT')
        elseif member.reason then S.note(id,nil) end
        row.idleAt=now+Config.memberIdleMs return
    end
    if inside and member.context=='SETTLEMENT' then row.idleAt=now+Config.memberIdleMs end
    if inside or runtime:owns(id) or now<(row.retryAt or 0) then return end
    if not entry.returnPoint then S.note(id,returnPointReason or 'RETURN_POINT_INITIALIZING') return end
    row.retryAt=now+5000
    row.returning,why=use('Settlement/MembershipReturn').start(actor,binding,member)
    S.note(id,why)
end
function M.tick()
    local now=Clock.nowMs() if now<nextAt then return end nextAt=now+200
    local root=Registry.data()
    if world~=root then
        world,rows,cursor,nextAt=root,{},0,now+200 retired=Schedule.new()
        for id,r in pairs(root.npcMembership and root.npcMembership.byNpc or {}) do if r.retired then retired:add(id) end end
    end
    local runtime=use('Runtime/TaskRuntime').current()
    if not root.npcMembership or not runtime or not runtime:accepting() then return end
    if root.executionSave and root.executionSave.state=='BLOCKED' then return end
    retired:step(2,function(id)
        if not runtime:owns(id) and #M.obligations(id)==0 then if S.retire(id,true) then retired:remove(id) end end
    end)
    local count=EmberRoutesProbeJava.workerCount() if count<1 or count>256 then return end
    local actor=getSpecificPlayer(0)
    for _=1,math.min(4,count) do
        cursor=cursor%count+1 local id=EmberRoutesProbeJava.workerIdAt(cursor-1)
        local ok,why=pcall(advance,id,actor,runtime,now)
        if not ok then
            runtime:stop(id,'MEMBERSHIP_ERROR')
            local row=rows[id] or {} rows[id]=row
            if row.error~=tostring(why) then
                row.error=tostring(why)
                use('Kernel/Log').write('MEMBERSHIP','npc='..id..' '..row.error)
            end
            S.note(id,'MEMBERSHIP_RECONCILE_REQUIRED')
        end
    end
end
function M.reset() world,rows,cursor,nextAt=nil,{},0,0 retired=Schedule.new() end
function M.install()
    S.changed=M.changed
    local Probe=use('Kernel/Boot')
    Probe.tickMembership=M.tick
    if Probe.registerReset then Probe.registerReset("Membership", M.reset) end
end
return M
