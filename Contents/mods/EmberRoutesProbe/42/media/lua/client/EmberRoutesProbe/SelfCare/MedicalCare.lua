-- The existing personal service owns observation cadence and execution.
local Health=require 'EmberRoutesProbe/SelfCare/HealthAssessment'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local M={}
local world,observed={}
function M.observe(npc,id,sample,now)
    local root=Registry.data() if world~=root then world,observed=root,{} end
    local facts,reason=Health.read(npc)
    sample.medical=facts sample.medicalReason=reason
    local member=require('EmberRoutesProbe/Settlement/MembershipService').view(id)
    local previous=observed[id]
    local state=facts and (facts.needsCare and 'CARE' or facts.deep and 'DOCTOR') or reason
    local signature=tostring(state)..':'..tostring(facts and facts.bleeding)..':'..tostring(facts and facts.deep)
        ..':'..tostring(facts and facts.partIndex)..':'..tostring(facts and facts.replace)
    observed[id]={facts=facts,reason=reason,scope=member and member.settlementId,at=now,
        state=state,signature=signature,blocker=facts and facts.needsCare and previous and previous.blocker or nil}
    if signature~=(previous and previous.signature) then require('EmberRoutesProbe/Work/LaborSignals').changed(id) if facts then require('EmberRoutesProbe/Chatter/ChatterService').observeHealth(npc,facts) end end
end
-- Read-only view of the last observed medical facts for one NPC, or nil
-- when SelfCare has not observed them yet (or the observation failed).
-- Decide's emergency short-circuit reads this cache instead of running a
-- second body-part scan: SelfCare refreshes it at its 1Hz observe cadence,
-- and a missing entry fails open to normal dispatch. Never calls observe:
-- that would duplicate SelfCare's signal/chatter side effects here.
function M.lastFacts(id)
    local root=Registry.data() if world~=root then world,observed=root,{} end
    local o=observed[id]
    return o and o.facts or nil
end
function M.eligible(item)
    return item and item.getBandagePower and item:getBandagePower()>0
        and item.getType and not string.find(item:getType(),'Dirty')
        and (not item.isInfected or not item:isInfected())
end
function M.begin(p,sample,item)
    local s=sample.medical if not s or s.partIndex==nil then return false end
    p.medical={version=1,attemptId=p.attemptId,partIndex=s.partIndex,itemId=item:getID(),fullType=item:getFullType(),
        phase='PREPARED',replace=s.replace==true,applied=false,removed=false,effects='KNOWN',outputs={}}
    return true
end
function M.blocker(id,reason)
    local root=Registry.data() if world~=root then world,observed=root,{} end
    local o=observed[id]
    if o and o.blocker~=reason then o.blocker=reason require('EmberRoutesProbe/Work/LaborSignals').changed(id) end
end
function M.demands(scope)
    local root=Registry.data() if world~=root then world,observed=root,{} end
    local rows={} local jobs=require('EmberRoutesProbe/Runtime/TaskJobs').current()
    local now=Clock.nowMs()
    for id,o in pairs(observed) do if o.scope==scope then
        local s=o.facts local job=jobs.peekPersonal and jobs:peekPersonal(id)
        local member=require('EmberRoutesProbe/Settlement/MembershipService').view(id)
        local p=job and job.payload
        local m=p and (p.medical or p.relief and p.relief.medical)
        local retained=m and (job.effects~='KNOWN' or m.effects~='KNOWN')
        local handling=m and p.step~='IDLE'
        local stale=now-o.at>2000
        if member and not member.retired and (o.state or retained) then
        rows[#rows+1]={id='DEMAND:medical:'..id,title=getText('IGUI_EmberRoutesProbe_Medical_need'),
            affected=require('EmberRoutesProbe/Warehouse/DisplayNames').name(id),urgency=s and s.bleeding and 'urgent' or 'normal',
            blocked=retained or not handling,blocker=retained and 'MEDICAL_EFFECT_UNCONFIRMED'
                or stale and 'HEALTH_UNAVAILABLE' or o.blocker
                or s and s.deep and not s.needsCare and 'HEALTH_NEEDS_DOCTOR' or handling and p.reason or o.reason
                or not handling and 'MEDICAL_WAITING' or nil,
            demandSummary=getText('IGUI_EmberRoutesProbe_Medical_'..(stale and 'unobserved' or s and s.bleeding and 'bleeding' or 'needsCare')),
            children=handling and {{id=job.id,name=require('EmberRoutesProbe/Warehouse/DisplayNames').name(id),phase='MEDICAL_'..m.phase,
                bucket=job.state=='RUNNING' and 'active' or 'waiting',uncertain=retained,assets={}}} or {}}
        end
    end end
    return rows
end
return M
