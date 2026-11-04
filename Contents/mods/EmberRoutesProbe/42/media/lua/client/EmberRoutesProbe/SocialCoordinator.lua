-- Pairing only: standing participants obtain their own authorization; seated ones retain SIT.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local S={}
local world,pairsById,byNpc,advertised=nil,{},{},{}
local function load()
    local root=Registry.data()
    if world~=root then world,pairsById,byNpc,advertised=root,{},{},{} end
end
function S.advertise(id,entry,point,now,actor)
    load() local ok,revision=S.eligible(id,entry) if not ok or not S.participant(id,actor) then S.withdraw(id) return end
    advertised[id]={actor=actor,entry=entry,point=point,untilTime=now+6000,membershipRevision=revision}
end
function S.eligible(id,entry,revision)
    local r=require('EmberRoutesProbe/MembershipService').view(id)
    return r and not r.pending and r.context=='SETTLEMENT' and r.settlementId==entry.id
        and (not revision or r.revision==revision),r and r.revision
end
function S.available(id)
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    local control=runtime and runtime:status(id)
    if control and control.kind=='ACTIVITY' then return false end
    local job=require('EmberRoutesProbe/TaskJobs').current():forNpc(id,'SELF_CARE')[1]
    if not job or job.payload.step=='IDLE' then return true end
    local p=job.payload
    return job.effects=='KNOWN' and p.kind=='LEISURE' and p.leisure and not p.leisure.zoneVisit and not p.leisure.roleDuty
        and (p.leisure.activity=='OBSERVE' or p.leisure.activity=='SOCIAL') and p.step=='ACTING'
end
-- Seated eligibility is proof-based, never a replacement for available().
function S.seated(id,actor)
    local job=require('EmberRoutesProbe/TaskJobs').current():forNpc(id,'SELF_CARE')[1]
    local p=job and job.payload local l=p and p.leisure
    if not job or job.effects~='KNOWN' or p.kind~='LEISURE' or p.step~='ACTING'
        or not l or l.activity~='SIT' or not l.seated or l.finished or l.stopped or l.applying
        or l.zoneVisit or l.roleDuty then return end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    local control=runtime and runtime:status(id,job.id)
    if not control or control.kind~='SELF_CARE' or control.state~='ACTIVE' then return end
    local binding=require('EmberRoutesProbe/Driver').bindId(actor or advertised[id] and advertised[id].actor
        or byNpc[id] and pairsById[byNpc[id]] and pairsById[byNpc[id]].actors[id],id)
    if not binding or not binding.handle:isSittingOnFurniture() or not binding.handle:isResting() then return end
    if not require('EmberRoutesProbe/LeisureService').valid(actor,binding.handle,id,p) then return end
    local site=require('EmberRoutesProbe/ReposeSites').resolve(p.site,nil,binding.handle,id,'REST',job.id)
    if not site then return end
    -- Resolve checks other owners; also require this job's own retained claim.
    local Store=require 'EmberRoutesProbe/LaborStore'
    for _,key in ipairs(require('EmberRoutesProbe/ReposeSites').keys(p.site,'REST')) do
        local owner=Store.resourceOwner(key)
        if not owner or owner.taskId~=job.id then return end
    end
    return {x=site.object:getSquare():getX()+0.5,y=site.object:getSquare():getY()+0.5,
        z=site.object:getSquare():getZ()}
end
function S.participant(id,actor) return S.available(id) or S.seated(id,actor)~=nil end
local function validPair(p)
    return p and (p.entryRevision==nil or p.entry.revision==p.entryRevision) and S.eligible(p.a,p.entry,p.revisions[p.a]) and S.eligible(p.b,p.entry,p.revisions[p.b])
end
function S.pending(id)
    load() local p=byNpc[id] and pairsById[byNpc[id]]
    if p and p.cancelled and not p.accepted[id] then S.release(p.id,id,nil,true) return end
    if p and not validPair(p) then S.withdraw(id) return end
    if p and not p.cancelled then return p.id end
end
function S.peekPending(id)
    load() local p=byNpc[id] and pairsById[byNpc[id]]
    return p and not p.cancelled and validPair(p) and p.id or nil
end
function S.invite(id,entry,now,choose,roll)
    load()
    for other,row in pairs(advertised) do
        if row.untilTime<=now then advertised[other]=nil end
    end
    if byNpc[id] then return S.pending(id) end
    local mine=advertised[id] if not mine or not S.participant(id) or not S.eligible(id,entry,mine.membershipRevision) then return end
    local best,distance
    -- Roster is bounded (256). Limit eligible geometry/path checks, not just results.
    local checked=0
    for other,row in pairs(advertised) do
        if checked>=4 then break end
        if other~=id and row.untilTime>=now and row.entry.id==entry.id and not byNpc[other] and S.participant(other) and S.eligible(other,entry,row.membershipRevision)
            and row.point.z==mine.point.z then
            local d=(row.point.x-mine.point.x)^2+(row.point.y-mine.point.y)^2
            if d<=900 then
                checked=checked+1
                local seatedA,seatedB=S.seated(id),S.seated(other)
                local a,b
                if not (seatedA and seatedB) then
                    a,b=choose(seatedA or mine.point,seatedB or row.point,id,other,seatedA,seatedB)
                end
                if a and b and (not roll or roll(other)) and (not distance or d<distance) then
                    best={id=other,a=a,b=b,seated=seatedA and id or seatedB and other} distance=d
                end
            end
        end
    end
    if not best then return end
    local key=Registry.id()
    local p={id=key,entry=entry,a=id,b=best.id,points={[id]=best.a,[best.id]=best.b},
        seated=best.seated,actors={[id]=mine.actor,[best.id]=advertised[best.id].actor},accepted={},arrived={},released={},deadline=now+35000,phase='APPROACH',
        entryRevision=entry.revision,revisions={[id]=mine.membershipRevision,[best.id]=advertised[best.id].membershipRevision}}
    pairsById[key]=p byNpc[id]=key byNpc[best.id]=key
    return key
end
function S.accept(key,id,attempt,now)
    load() local p=pairsById[key]
    if not p or not validPair(p) or not S.participant(id) or p.cancelled or now>=p.deadline or byNpc[id]~=key
        or p.accepted[id] and p.accepted[id]~=attempt then return false end
    p.accepted[id]=attempt return true
end
function S.view(key,id,attempt,now)
    load() local p=pairsById[key]
    if not p or not validPair(p) or byNpc[id]~=key or p.cancelled or attempt and p.accepted[id]~=attempt then return end
    if p.phase=='APPROACH' and now>=p.deadline then p.cancelled=true return end
    local point=p.points[id]
    return {id=p.id,phase=p.phase,other=id==p.a and p.b or p.a,point={x=point.x,y=point.y,z=point.z},
        seated=p.seated==id,ready=p.accepted[p.a]~=nil and p.accepted[p.b]~=nil,ends=p.ends}
end
function S.arrive(key,id,attempt,hours)
    load() local p=pairsById[key]
    if not p or not validPair(p) or p.cancelled or p.accepted[id]~=attempt then return false end
    p.arrived[id]=true
    if p.arrived[p.a] and p.arrived[p.b] and p.accepted[p.a] and p.accepted[p.b] and not p.ends then
        p.phase='CONVERSE' p.ends=hours+10/60
    end
    return true
end
function S.cancel(key,id,attempt)
    load() local p=pairsById[key]
    if not p or byNpc[id]~=key or attempt and p.accepted[id] and p.accepted[id]~=attempt then return false end
    p.cancelled=true return true
end
function S.release(key,id,attempt,stopped)
    load() local p=pairsById[key]
    if not p or not stopped or byNpc[id]~=key or p.accepted[id] and p.accepted[id]~=attempt then return false end
    p.released[id]=true byNpc[id]=nil advertised[id]=nil
    if p.released[p.a] and p.released[p.b] then pairsById[key]=nil end
    return true
end
function S.withdraw(id)
    load() advertised[id]=nil
    local key=byNpc[id] local p=key and pairsById[key]
    if p then p.cancelled=true if not p.accepted[id] then S.release(p.id,id,nil,true) end end
end
function S.reset() world=nil load() end
return S
