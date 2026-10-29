-- Pairing only: participants obtain their OWN Runtime/body authorizations.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local S={}
local world,pairsById,byNpc,advertised=nil,{},{},{}
local function load()
    local root=Registry.data()
    if world~=root then world,pairsById,byNpc,advertised=root,{},{},{} end
end
function S.advertise(id,entry,point,now)
    load() local ok,revision=S.eligible(id,entry) if not ok or not S.available(id) then S.withdraw(id) return end
    advertised[id]={entry=entry,point=point,untilTime=now+3000,membershipRevision=revision}
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
    return job.effects=='KNOWN' and p.kind=='LEISURE' and p.leisure and not p.leisure.zoneVisit
        and (p.leisure.activity=='OBSERVE' or p.leisure.activity=='SOCIAL') and p.step=='ACTING'
end
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
function S.invite(id,entry,now,choose)
    load()
    if byNpc[id] then return S.pending(id) end
    local mine=advertised[id] if not mine or mine.untilTime<now or not S.eligible(id,entry,mine.membershipRevision) then return end
    local best,distance
    -- Roster is bounded (256). Limit eligible geometry/path checks, not just results.
    local checked=0
    for other,row in pairs(advertised) do
        if checked>=4 then break end
        if other~=id and row.untilTime>=now and row.entry.id==entry.id and not byNpc[other] and S.available(other) and S.eligible(other,entry,row.membershipRevision)
            and row.point.z==mine.point.z then
            local d=(row.point.x-mine.point.x)^2+(row.point.y-mine.point.y)^2
            if d<=900 then
                checked=checked+1
                if not distance or d<distance then
                    local a,b=choose(mine.point,row.point,id,other)
                    if a and b then best={id=other,a=a,b=b} distance=d end
                end
            end
        end
    end
    if not best then return end
    local key=Registry.id()
    local p={id=key,entry=entry,a=id,b=best.id,points={[id]=best.a,[best.id]=best.b},
        accepted={},arrived={},released={},deadline=now+35000,phase='APPROACH',
        entryRevision=entry.revision,revisions={[id]=mine.membershipRevision,[best.id]=advertised[best.id].membershipRevision}}
    pairsById[key]=p byNpc[id]=key byNpc[best.id]=key
    return key
end
function S.accept(key,id,attempt,now)
    load() local p=pairsById[key]
    if not p or not validPair(p) or not S.available(id) or p.cancelled or now>=p.deadline or byNpc[id]~=key
        or p.accepted[id] and p.accepted[id]~=attempt then return false end
    p.accepted[id]=attempt return true
end
function S.view(key,id,attempt,now)
    load() local p=pairsById[key]
    if not p or not validPair(p) or byNpc[id]~=key or p.cancelled or attempt and p.accepted[id]~=attempt then return end
    if p.phase=='APPROACH' and now>=p.deadline then p.cancelled=true return end
    local point=p.points[id]
    return {id=p.id,phase=p.phase,other=id==p.a and p.b or p.a,point={x=point.x,y=point.y,z=point.z},
        ready=p.accepted[p.a]~=nil and p.accepted[p.b]~=nil,ends=p.ends}
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
