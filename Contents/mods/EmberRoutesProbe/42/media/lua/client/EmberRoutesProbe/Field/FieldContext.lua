-- FIELD execution context. No independent world cache, body grant or asset ledger.
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Members=require 'EmberRoutesProbe/Settlement/MembershipService'
local Constants=require 'EmberRoutesProbe/Kernel/Constants'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local C={}
function C.new(actor,job,binding,def,root)
    local c={actor=actor,npc=binding.handle,binding=binding,job=job,reason=nil,nextTick=0}
    c.token=Store.claimField(job) if not c.token then return nil end
    function c.same() return Registry.data()==root and Store.validField(c.job,c.token) end
    function c.change(edit,capacity,obligationOps)
        if not c.same() then return false end
        local j=Jobs.current():get(c.job.id) edit(j)
        local ok,value=Store.replaceField(c.job,c.token,j,capacity,obligationOps)
        if not ok then c.reason=value return false end
        c.job=value return true
    end
    function c.unknown(why)
        c.reason=tostring(why or 'FIELD_EFFECT_UNKNOWN')
        return c.change(function(j)
            j.effects='UNKNOWN' j.payload.reason=string.sub(c.reason,1,256)
            if j.payload.attempt then j.payload.attempt.state='UNKNOWN' end
        end)
    end
    if job.payload.target.kind=='CORPSE'
        and not require('EmberRoutesProbe/Field/FieldOperations').reconcileCorpse(c) then return nil end
    -- Confirmed corpse delivery has no further world interaction. Retire its
    -- old obligation under recovery authority, even if ordinary work is barred
    -- outside the settlement or a later command/zone change disables new labour.
    local p=c.job.payload local a=p.attempt
    if p.target.kind=='CORPSE' and c.job.effects=='KNOWN' and p.workDone==true and not p.holding
        and not p.capacity and not p.toolSupply and #p.assets==0
        and a and (a.state=='APPLIED' or a.state=='ABORTED') then
        c.finalizeOnly=true c.recoveryOnly=true
    end
    local function recoveryRequested()
        local member=Members.view(job.npcId)
        local command=member and member.pending
        return member and not member.retired and member.settlementId==job.scopeId
            and (member.context=='RETURN' or command and (command.kind=='UNASSIGN'
                or (command.kind=='TRANSFER' or command.kind=='SETTLE') and command.settlementId~=job.scopeId)) or false
    end
    -- Accepted membership changes wait on old custody. Only already observed
    -- originals may finish delivery under RECOVERY; never resume field labour.
    if recoveryRequested() and c.job.effects=='KNOWN' then
        local cargo=false
        for _,asset in ipairs(c.job.payload.assets) do if asset.custody~='DELIVERED' then cargo=true break end end
        if cargo and not c.job.payload.holding then
            c.recoveryOnly=true
            if not c.change(function(j) j.payload.phase=def.collect and 'COLLECT' or 'DELIVER' end) then return nil end
        end
    end
    function c.valid()
        if not c.same() or c.stopping or c.npc:isDead() or actor:isDead() then return false end
        local recovery=c.finalizeOnly or c.job.payload.phase~='WORK'
        if not recovery and require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary(job.npcId) then return false end
        local entry,_,memberRevision=Members.entry(job.npcId,job.scopeId)
        if not entry then return false end
        c.entry=entry -- trusted internal read-only view; never modify it
        local ledger=require('EmberRoutesProbe/Settlement/SettlementLedger').data()
        local policyRevision=ledger.jobPolicies and ledger.jobPolicies.revision or 0
        local zoneRevision=require('EmberRoutesProbe/Settlement/SettlementZones').revision()
        local cached=c.validity local now=Clock.nowMs()
        if cached and cached.target==c.job.payload.target and cached.recovery==recovery
            and cached.member==memberRevision and cached.entry==entry.revision
            and cached.policy==policyRevision and cached.zones==zoneRevision and now<cached.untilAt then return cached.allowed end
        local purpose=(c.finalizeOnly or c.recoveryOnly and recovery and recoveryRequested()) and 'RECOVERY' or 'FIELD_WORK'
        local m=Members.check(job.npcId,purpose,
            {x=c.npc:getX(),y=c.npc:getY(),z=c.npc:getZ(),scopeId=job.scopeId})
        local allowed=m.allowed==true and (recovery or not def.valid or def.valid(c))
        c.validity={target=c.job.payload.target,recovery=recovery,member=memberRevision,entry=entry.revision,
            policy=policyRevision,zones=zoneRevision,untilAt=now+500,allowed=allowed}
        return allowed
    end
    function c.move(square,arrived)
        if arrived then c.path=nil return 'Success' end
        if not square then c.reason='FIELD_NO_APPROACH' return 'Failure' end
        local key=square:getX()..':'..square:getY()..':'..square:getZ()
        if not c.path or c.path.key~=key then
            local currentSq = c.npc and c.npc.getCurrentSquare and c.npc:getCurrentSquare()
            if currentSq and square and EmberRoutesProbeJava and EmberRoutesProbeJava.macroReachable then
                if not EmberRoutesProbeJava.macroReachable(currentSq, square) then
                    c.reason='MACRO_UNREACHABLE'
                    return 'Failure'
                end
            end
            local ok,result=c.body.move(actor,{x=square:getX()+0.5,y=square:getY()+0.5,z=square:getZ()})
            if not ok or type(result)~='string' or not string.find(result,'^MOVE_REQUESTED') then
                c.reason=tostring(result) return 'Failure'
            end
            c.path={key=key,at=Clock.nowMs()} return 'Running'
        end
        -- Parked: hold the leg's clock so a long unload never times it out.
        if require('EmberRoutesProbe/Runtime/Driver').suspended(c.npc) then
            c.path.at=Clock.nowMs()
            return 'Running'
        end
        local result=EmberRoutesProbeJava.motionResult(c.npc)
        if result=='MOVING' and Clock.nowMs()-c.path.at<Constants.Timeout.MOVE_MS then return 'Running' end
        if result=='REACHED' and math.abs(c.npc:getZ()-square:getZ())<=0.2
            and (c.npc:getX()-(square:getX()+0.5))^2+(c.npc:getY()-(square:getY()+0.5))^2<=0.25 then
            c.path=nil return 'Success'
        end
        c.reason='FIELD_PATH_'..tostring(result) return 'Failure'
    end
    return c
end
return C
