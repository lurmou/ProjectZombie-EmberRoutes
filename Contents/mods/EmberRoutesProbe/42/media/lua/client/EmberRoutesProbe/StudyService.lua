-- Idle PERSONAL offers supplied by the existing public-work arbitration. This
-- module has no tick handler, body owner, separate Job store or asset ledger.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Library=require 'EmberRoutesProbe/LibraryIndex'
local Study={}
local world,offers,versions=nil,{},{}
local function load()
    local root=Registry.data()
    if world~=root then world,offers,versions=root,{},{} end
end
function Study.changed(scope,npcId)
    load()
    if npcId then offers[npcId]=nil return end
    versions[scope]=(versions[scope] or 0)+1
end
function Study.offer(npcId,entry,target)
    load()
    local member=require('EmberRoutesProbe/MembershipService').view(npcId)
    if not member or member.pending or member.context~='SETTLEMENT' or member.settlementId~=entry.id then return end
    local prior=offers[npcId]
    if not target and prior then target=prior.target end
    if not prior or prior.entry.id~=entry.id or (prior.target and prior.target.orderId)~=(target and target.orderId) then
        prior={entry=entry,target=target,offset=1} offers[npcId]=prior
    end
    prior.untilTime=getTimestampMs()+15000 prior.version=versions[entry.id] or 0 prior.membershipRevision=member.revision
    prior.entryRevision=entry.revision
end
function Study.candidate(actor,npc,id,budget,memory)
    load()
    local offer=offers[id]
    if not offer or getTimestampMs()>offer.untilTime or offer.version~=(versions[offer.entry.id] or 0) then
        return nil,true,'STUDY_WAIT_WORK'
    end
    local M=require 'EmberRoutesProbe/MembershipService'
    local eligible=M.check(id,'STUDY',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=offer.entry.id},offer.membershipRevision)
    if not eligible.allowed then return nil,true,eligible.reason end
    if eligible.entryRevision~=offer.entryRevision then return nil,true,'SETTLEMENT_CHANGED' end
    local entry=M.entry(id,offer.entry.id)
    if not entry then return nil,true,'ACCESS_DENIED' end
    local target=offer.target
    if target then
        local o=require('EmberRoutesProbe/PublicWork').order(target.orderId)
        local known=false
        for _,key in ipairs(target.knowledge) do if npc:getKnownRecipes():contains(key) then known=true break end end
        if not o or o.state~='WAITING' or o.jobId or o.recipeId~=target.recipeId or known then
            offer.target=nil target=nil offer.offset=1
        end
    end
    if not offer.target and memory and getGameTime():getWorldAgeHours()<(memory.decisionAfter or 0) then
        return nil,true,'LEISURE_PAUSE'
    end
    local allowance=math.min(8,budget.scan)
    local containers=math.min(1,budget.containers or 0)
    local slice={scan=allowance,containers=containers}
    local candidate,done,reason,offset=Library.choose(actor,npc,entry,target and target.knowledge,slice,offer.offset)
    budget.scan=budget.scan-(allowance-slice.scan)
    budget.containers=budget.containers-(containers-slice.containers)
    offer.offset=done and 1 or offset or offer.offset
    if candidate then
        candidate.membershipRevision=offer.membershipRevision candidate.settlementRevision=offer.entryRevision
        candidate.study={orderId=target and target.orderId,recipeId=target and target.recipeId,
            knowledge=candidate.knowledge,version=versions[entry.id] or 0,
            policyRevision=require('EmberRoutesProbe/PublicWork').priorities(id).revision}
    end
    return candidate,done,reason
end
function Study.decorateLeisure(candidate,id)
    load()
    local member=require('EmberRoutesProbe/MembershipService').view(id)
    candidate.membershipRevision=member and member.revision
    candidate.settlementRevision=candidate.entry.revision
    candidate.study={leisure=true,version=versions[candidate.entry.id] or 0,
        policyRevision=require('EmberRoutesProbe/PublicWork').priorities(id).revision}
    return candidate
end
function Study.valid(actor,npc,id,p)
    if p.activityRef and not require('EmberRoutesProbe/ActivityService').validRef(id,p.activityRef) then return false end
    if p.activityRef and p.reading and p.reading.started then
        local activity=require 'EmberRoutesProbe/ActivityService'
        if not activity.allowsPoint(p.settlementId,id,{x=npc:getX(),y=npc:getY(),z=math.floor(npc:getZ())})
            or activity.policyAt(p.settlementId,id,npc:getX(),npc:getY(),math.floor(npc:getZ()),'READING')==0 then return false end
    end
    load()
    if not p.study or p.study.version~=(versions[p.settlementId] or 0) then return false end
    local M=require 'EmberRoutesProbe/MembershipService'
    local eligible=M.check(id,'STUDY',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=p.settlementId},p.membershipRevision)
    if not eligible.allowed or p.membershipRevision==nil or p.settlementRevision~=eligible.entryRevision then return false end
    -- Live membership check on this repeated advisory path; replaced Ledger
    -- modules without data() keep the old detached view() form.
    local entry=M.entry(id,p.settlementId)
    if not entry or not require('EmberRoutesProbe/SettlementGeometry').inside(entry,npc:getX(),npc:getY()) then return false end
    local priorities=require('EmberRoutesProbe/PublicWork').priorities(id)
    local order=p.study.orderId and require('EmberRoutesProbe/PublicWork').order(p.study.orderId)
    local category=order and order.category=='cooking' and 'cooking' or 'crafting'
    if not p.study.leisure and priorities[category]==0 or p.study.policyRevision and p.study.policyRevision~=priorities.revision then return false end
    if p.study.orderId then
        local o=order
        if not o or o.state~='WAITING' or o.jobId or o.recipeId~=p.study.recipeId then return false end
    end
    return true
end
function Study.completed(id,scope)
    load() offers[id]=nil
    require('EmberRoutesProbe/LaborSignals').changed(id)
    local Probe=require 'EmberRoutesProbe/Boot'
    if Probe.invalidatePersonnel then Probe.invalidatePersonnel(id) end
end
return Study
