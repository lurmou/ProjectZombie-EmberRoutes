-- A recurring personal routine, not a public Order. Attempts are independently
-- fenced; unresolved attempts/custody cannot be replaced by a later episode.
local Validate=require 'EmberRoutesProbe/Validate'
local Record={}
local kinds={EAT=true,DRINK=true,REST=true,SLEEP=true,STUDY=true,LEISURE=true}
local steps={IDLE=true,REQUESTED=true,STOP_CONFIRMED=true,ACTING=true,SETTLING=true,
    RESTORE_PENDING=true,RECONCILE_REQUIRED=true}
local finite=Validate.finite
local itemId=Validate.itemId
local stringId=Validate.stringId
function Record.create(id,npcId)
    return {id=id,npcId=npcId,providerType='SELF_CARE',scopeId='local-world',revision=1,
        state='PREPARING',effects='KNOWN',obligations={},payload={format=1,step='IDLE',sequence=0,claims={}}}
end
function Record.valid(job)
    local p=job and job.payload
    if not (job and job.providerType=='SELF_CARE' and type(p)=='table' and p.format==1
        and steps[p.step] and type(p.sequence)=='number' and p.sequence>=0
        and p.sequence==math.floor(p.sequence) and p.sequence<math.huge and type(p.claims)=='table'
        and #p.claims<=16) then return false end
    if not require('EmberRoutesProbe/LeisureRecord').valid(p)
        or not require('EmberRoutesProbe/LeisureRecord').memory(p.leisureMemory) then return false end
    if p.activityRef~=nil then
        local a=p.activityRef
        if type(a)~='table' then return false end
        if (a.dutyId~=nil or a.dutyFormat~=nil) and not require('EmberRoutesProbe/ActivityDuties').validRef(a) then return false end
        if p.kind~='LEISURE' and p.kind~='STUDY' or type(a)~='table' or not stringId(a.eventId)
            or not stringId(a.id) or not finite(a.controlEpoch) or a.controlEpoch<1 or a.controlEpoch~=math.floor(a.controlEpoch)
            or not finite(a.revision) or a.revision<1 or a.revision~=math.floor(a.revision)
            or a.participantEpoch~=nil and (not finite(a.participantEpoch) or a.participantEpoch<1
                or a.participantEpoch~=math.floor(a.participantEpoch)) then return false end
    end
    local count,seen=0,{}
    for key,value in pairs(p.claims) do
        count=count+1
        if type(key)~='number' or key<1 or key>#p.claims or key~=math.floor(key)
            or type(value)~='string' or #value>256 or #value<1 or seen[value] then return false end
        seen[value]=true
    end
    if count~=#p.claims then return false end
    if p.step~='IDLE' and (not kinds[p.kind] or p.sequence<1
        or p.attemptId~=job.id..':'..tostring(p.sequence)) then return false end
    if p.itemId~=nil and not itemId(p.itemId) or p.sourceId~=nil and not stringId(p.sourceId)
        or p.settlementId~=nil and not stringId(p.settlementId)
        or p.fraction~=nil and (not finite(p.fraction) or p.fraction<=0 or p.fraction>1) then return false end
    if p.destinations~=nil then
        if type(p.destinations)~='table' then return false end
        local n=0
        for key,id in pairs(p.destinations) do
            n=n+1 if n>16 or not stringId(key) or not stringId(id) then return false end
        end
    end
    if p.kind=='STUDY' then
        if p.reliefOnly~=nil and type(p.reliefOnly)~='boolean' then return false end
        local study=p.study
        if study and study.leisure~=nil and type(study.leisure)~='boolean' then return false end
        if type(study)~='table' or not finite(study.version) or study.version<0
            or study.version~=math.floor(study.version) or not stringId(p.settlementId) or not itemId(p.itemId)
            or study.policyRevision~=nil and (not finite(study.policyRevision) or study.policyRevision<0
                or study.policyRevision~=math.floor(study.policyRevision))
            or study.orderId~=nil and not stringId(study.orderId)
            or study.recipeId~=nil and not stringId(study.recipeId)
            or study.knowledge~=nil and not stringId(study.knowledge) then return false end
        local read=p.reading
        if read and (type(read)~='table' or read.attemptId~=p.attemptId or read.itemId~=p.itemId
            or not stringId(read.fullType) or not finite(read.before) or not finite(read.total)
            or read.before<0 or read.total<0 or read.total>0 and read.before>read.total or type(read.started)~='boolean'
            or read.effects~='KNOWN' and read.effects~='UNKNOWN'
            or read.pages~=nil and (not finite(read.pages) or read.pages<0 or read.pages>read.total)
            or read.completed~=nil and type(read.completed)~='boolean'
            or read.stopped~=nil and type(read.stopped)~='boolean'
            or read.completing~=nil and type(read.completing)~='boolean') then return false end
        local relief=p.relief
        if relief then
            if type(relief)~='table' or not finite(relief.sequence) or relief.sequence<1
                or relief.sequence~=math.floor(relief.sequence) or type(relief.finished)~='boolean'
                or relief.kind~='EAT' and relief.kind~='DRINK' and relief.kind~='REST' and relief.kind~='SLEEP' then return false end
            local identity=p.attemptId..':relief'
            if not Record.valid({id=identity,providerType='SELF_CARE',payload={format=1,step='ACTING',
                kind=relief.kind,sequence=relief.sequence,attemptId=identity..':'..relief.sequence,
                itemId=relief.itemId,claims={},consumption=relief.fact,repose=relief.repose,floorSite=relief.floorSite}}) then return false end
        end
    elseif p.reading~=nil or p.study~=nil or p.relief~=nil then return false end
    if p.readingSite~=nil and (p.kind~='STUDY' or not require('EmberRoutesProbe/ReposeRecord').valid(p.readingSite)) then return false end
    if p.floorSite~=nil then
        local floor=p.floorSite
        if p.kind~='SLEEP' or p.site~=nil or type(floor)~='table' or not stringId(floor.settlementId) then return false end
        for _,name in ipairs({'x','y','z'}) do
            if not finite(floor[name]) or floor[name]~=math.floor(floor[name]) then return false end
        end
    end
    local fact=p.consumption
    if p.site~=nil and (p.kind~='REST' and p.kind~='SLEEP'
        and not (p.kind=='LEISURE' and p.leisure and p.leisure.activity=='SIT')
        or not require('EmberRoutesProbe/ReposeRecord').valid(p.site)) then return false end
    if fact then
        if type(fact)~='table' or fact.attemptId~=p.attemptId or fact.kind~=p.kind
            or (fact.kind~='EAT' and fact.kind~='DRINK') or fact.itemId~=p.itemId
            or not stringId(fact.fullType) or not finite(fact.before) or fact.before<=0
            or not finite(fact.fraction) or fact.fraction<=0 or fact.fraction>1 or type(fact.started)~='boolean'
            or (fact.effects~='KNOWN' and fact.effects~='UNKNOWN') then return false end
        if fact.after~=nil and (not finite(fact.after) or fact.after<0) then return false end
        if fact.effects=='KNOWN' and fact.after and fact.after>fact.before+0.0001 then return false end
        if fact.effects=='KNOWN' and (fact.completed or fact.stopped) and (not finite(fact.after) or not finite(fact.consumed)
            or math.abs(fact.consumed-(fact.before-fact.after))>0.0001) then return false end
        if fact.outputs~=nil then
            if type(fact.outputs)~='table' or #fact.outputs>512 then return false end
            local n,ids=0,{}
            for key,id in pairs(fact.outputs) do
                n=n+1
                if not itemId(key) or key<1 or key>#fact.outputs or not itemId(id) or ids[id] or id==p.itemId then return false end
                ids[id]=true
            end
            if n~=#fact.outputs then return false end
        end
    end
    local repose=p.repose
    if repose and (type(repose)~='table' or repose.attemptId~=p.attemptId or repose.kind~=p.kind
        or (repose.kind~='REST' and repose.kind~='SLEEP') or not finite(repose.before)
        or repose.before<0 or repose.before>1 or not finite(repose.gameStart) or repose.gameStart<0
        or type(repose.started)~='boolean' or (repose.effects~='KNOWN' and repose.effects~='UNKNOWN')
        or repose.finished and (not finite(repose.after) or repose.after<0 or repose.after>1)) then return false end
    local transfer=p.transfer
    if transfer and (type(transfer)~='table' or transfer.attemptId~=p.attemptId or not itemId(transfer.itemId)
        or transfer.phase~='TAKE' and transfer.phase~='RETURN') then return false end
    return true
end
function Record.begin(job,kind,resume)
    if not Record.valid(job) then return nil,'PERSONAL_RECORD_INVALID' end
    if not kinds[kind] then return nil,'PERSONAL_KIND_INVALID' end
    if job.effects~='KNOWN' or job.payload.step~='IDLE' then return nil,'PERSONAL_ATTEMPT_RETAINED' end
    for _ in pairs(job.obligations) do return nil,'PERSONAL_OBLIGATION_RETAINED' end
    for _ in pairs(job.payload.claims) do return nil,'PERSONAL_CLAIM_RETAINED' end
    local sequence=job.payload.sequence+1
    return {format=1,step='REQUESTED',sequence=sequence,attemptId=job.id..':'..tostring(sequence),
        kind=kind,resume=resume,claims={},leisureMemory=job.payload.leisureMemory}
end
return Record
