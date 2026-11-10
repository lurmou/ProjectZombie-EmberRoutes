-- One advertisement table for leisure facilities (Sims-style object
-- broadcast, pilot for SOCIAL / READING / SMOKE / SIT / PUBLIC_LIFE).
-- Facilities -- and, for SOCIAL, partner NPCs -- publish ads of one shape:
--   {activity, key, point, benefit, condition, payload}
--   activity  : LeisureRegistry id the ad serves
--   key       : stable identity of the advertised facility/pair
--   point     : where the facility is (NPC position when it is carried,
--               e.g. a cigarette in the NPC's own inventory)
--   benefit   : Policy.weight for the activity (same value the old seek
--               produced for the candidate pool); query prefers the best
--   condition : function(env, ad) -> boolean, the activity's existing
--               eligibility gate, moved verbatim -- never a new gate
--   payload   : what the seek wrapper needs to decorate the ad into a
--               candidate (book, cigarette+fire, found seat, social pair,
--               zone-visit candidate)
-- Seeks only query the table (Ads.lookup). Finding lives in the collectors
-- below, one per activity, which reuse the existing bounded indexes
-- (LibraryIndex, inventory scan, ReposeSites facility index, LifeZoneVisits
-- zone list, SocialCoordinator roster). No full-map scan: query iterates
-- only registered ads, and every collector is budget-bounded exactly as
-- the seek it replaces was. Benefit/condition semantics are unchanged.
-- LeisureService installs the two rules the collectors cannot own
-- (zoneRule, standable) via Ads.install before any lookup runs.
local Policy=require 'EmberRoutesProbe/Leisure/LeisurePolicy'
local Config=require 'EmberRoutesProbe/Leisure/LeisureConfig'
local Tick=require 'EmberRoutesProbe/Kernel/TickConfig'
local Ads={}
local rules={}
local adsByActivity={}
local scopeKey=nil
function Ads.install(installed) rules=installed or {} end
function Ads.reset() adsByActivity={} scopeKey=nil end
local function scope(env)
    local offer=env.offer or {}
    local key=tostring(env.id)..'|'..tostring(offer.entryRevision)..'|'..tostring(offer.membershipRevision)
    if key~=scopeKey then scopeKey=key adsByActivity={} end
end
local function publish(activity,ad)
    local list=adsByActivity[activity] or {}
    adsByActivity[activity]=list
    list[#list+1]=ad
end
local function drop(activity) adsByActivity[activity]=nil end
-- Test/probe read of the registered ads for one activity.
function Ads.list(activity) return adsByActivity[activity] or {} end
local conditions={
    SOCIAL=function(env,ad)
        if not rules.zoneRule then return false end
        return (rules.zoneRule(ad.payload.entry,ad.point,'SOCIAL',env.id) or 0)>0
            and (rules.zoneRule(ad.payload.entry,ad.payload.otherPoint,'SOCIAL',ad.payload.other) or 0)>0
    end,
    READING=function(env,ad)
        return Policy.allowed('READING',env.s,{hold=true})
            and require('EmberRoutesProbe/Leisure/LibraryIndex').revalidate(ad.payload.candidate)
    end,
    SMOKE=function(env,ad) return Policy.allowed('SMOKE',env.s,{hold=true}) end,
    SIT=function(env,ad)
        return Policy.allowed('SIT',env.s,{hold=true})
            and EmberRoutesProbeJava~=nil and EmberRoutesProbeJava.reposeAtWithControl~=nil
    end,
    PUBLIC_LIFE=function(env,ad)
        return Policy.allowed('STROLL',env.s,{hold=true})
            and env.hours>=((env.memory or {}).moveAfter or 0)
    end,
}
function Ads.query(activity,env)
    local best
    for _,ad in ipairs(adsByActivity[activity] or {}) do
        local condition=conditions[activity]
        if (not condition or condition(env,ad)) and (not best or ad.benefit>best.benefit) then best=ad end
    end
    return best
end
local function objectPoint(object,fallback)
    local square=object and object.getSquare and object:getSquare()
    if square and square.getX then return {x=square:getX()+0.5,y=square:getY()+0.5,z=square:getZ()} end
    return fallback
end
local function collectSocial(env)
    local Social=require 'EmberRoutesProbe/Activity/SocialCoordinator'
    local zoneRule,standable=rules.zoneRule,rules.standable
    local rule=zoneRule(env.entry,env.point,'SOCIAL',env.id)
    if not rule or rule==0 then Social.withdraw(env.id) return true end
    if env.hours>=(env.cooling.SOCIAL or 0) then
        Social.advertise(env.id,env.entry,env.point,env.now,env.actor)
    end
    local key=Social.pending(env.id)
    local time=getGameTime():getTimeOfDay()
    local chance=time>=Config.socialChance.from and time<Config.socialChance.to
        and Config.socialChance.evening or Config.socialChance.other
    if rule==2 then chance=math.min(1,chance*2) end
    if not key and env.hours>=(env.cooling.SOCIAL or 0) and env.budget.paths>0 then
        env.budget.paths=env.budget.paths-1
        -- One outcome per eligible partner in each existing discovery round.
        local round=math.floor(env.now/Tick.socialRoundMs)
        if env.state.round~=round then env.state.round=round env.state.rolls={} end
        key=Social.invite(env.id,env.entry,env.now,function(a,b,aid,bid,seatedA,seatedB)
            local partner=require('EmberRoutesProbe/Runtime/Driver').bindId(env.actor,bid)
            if not partner then return end
            local allowed={env.npc,partner.handle}
            if seatedA or seatedB then
                local seat=seatedA or seatedB
                local seatedId,standingId=seatedA and aid or bid,seatedA and bid or aid
                if (zoneRule(env.entry,seat,'SOCIAL',seatedId) or 0)==0 then return end
                for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
                    if env.budget.scan<1 then return end env.budget.scan=env.budget.scan-1
                    local p={x=seat.x+offset[1],y=seat.y+offset[2],z=seat.z}
                    local square=standable(env.entry,p,allowed)
                    local seatSquare=getCell():getGridSquare(math.floor(seat.x),math.floor(seat.y),seat.z)
                    if square and seatSquare and square:canReachTo(seatSquare) and (zoneRule(env.entry,p,'SOCIAL',standingId) or 0)>0 then
                        if seatedA then return seat,p else return p,seat end
                    end
                end
                return
            end
            local target={x=math.floor(b.x)+0.5,y=math.floor(b.y)+0.5,z=b.z}
            for _,offset in ipairs({{1,0},{0,1},{-1,0},{0,-1}}) do
                local p={x=target.x+offset[1],y=target.y+offset[2],z=target.z}
                if env.budget.scan<1 then return end env.budget.scan=env.budget.scan-1
                local sa,sb=standable(env.entry,p,allowed),standable(env.entry,target,allowed)
                local aRule,bRule=zoneRule(env.entry,p,'SOCIAL',aid),zoneRule(env.entry,target,'SOCIAL',bid)
                if sa and sb and aRule and aRule>0 and bRule and bRule>0 and sa:canReachTo(sb) then return p,target end
            end
        end,function(other)
            local passed=env.state.rolls[other]
            if passed==nil then
                passed=ZombRand(10000)/10000<chance
                env.state.rolls[other]=passed
            end
            return passed
        end)
    end
    if key then
        local mine=Social.view(key,env.id,nil,env.now)
        local other=mine and Social.view(key,mine.other,nil,env.now)
        if not mine or not other or (zoneRule(env.entry,mine.point,'SOCIAL',env.id) or 0)==0
            or (zoneRule(env.entry,other.point,'SOCIAL',mine.other) or 0)==0 then
            Social.withdraw(env.id) return true
        end
        publish('SOCIAL',{activity='SOCIAL',key=key,point=mine.point,
            benefit=Policy.weight('SOCIAL',env.s,Config.weights.SOCIAL or 1),
            condition=conditions.SOCIAL,
            payload={key=key,entry=env.entry,other=mine.other,otherPoint=other.point}})
    end
    return true
end
local function collectReading(env)
    if env.resume and env.budget.scan<1 then return false end
    if env.hours<(env.cooling.READING or 0) or env.budget.scan<1 then return true end
    local candidate,done,reason,offset=require('EmberRoutesProbe/Leisure/LibraryIndex').choose(
        env.actor,env.npc,env.entry,nil,env.budget,env.state.offset,true,env.resume and env.resume.itemId)
    env.state.offset=done and 1 or offset or env.state.offset
    if candidate then
        publish('READING',{activity='READING',key='item:'..candidate.id,
            point=objectPoint(candidate.container,env.point),
            benefit=Policy.weight('READING',env.s,Config.weights.READING or 1),
            condition=conditions.READING,payload={candidate=candidate}})
        return true
    end
    if not done then return false,reason end
    return true
end
local function collectSmoke(env)
    if not Policy.allowed('SMOKE',env.s,{hold=true}) or env.hours<(env.cooling.SMOKE or 0)
        or env.budget.scan<1 then return true end
    env.state.cache=env.state.cache or {}
    local smoke,done=require('EmberRoutesProbe/Leisure/LeisureSmoke').find(env.npc,env.budget,env.state.cache)
    if smoke then
        publish('SMOKE',{activity='SMOKE',key='item:'..smoke.item:getID(),point=env.point,
            benefit=Policy.weight('SMOKE',env.s,Config.weights.SMOKE or 1),
            condition=conditions.SMOKE,payload={item=smoke.item,fire=smoke.fire}})
        return true
    end
    if not done then return false end
    return true
end
-- Seated idle reuses the P2 furniture discovery/reservation untouched: a
-- prepared proof plus its repose keys ride the LEISURE payload the same
-- way REST carries them, so occupancy claims interlock with the same store.
-- The collector only finds and advertises the seat; the seek wrapper still
-- prepares the proof (the claim step), exactly as the old seek did.
local function collectSit(env,opts)
    local preview,nearby=opts and opts.preview,opts and opts.nearby
    if env.resume and env.budget.scan<1 then return false end
    if not Policy.allowed('SIT',env.s,{hold=true}) or env.hours<(env.cooling.SIT or 0)
        or env.budget.scan<1
        or not (EmberRoutesProbeJava and EmberRoutesProbeJava.reposeAtWithControl) then return true end
    if env.resume then
        local h=env.resume local p=h.point
        env.budget.scan=env.budget.scan-1
        local square=getCell():getGridSquare(p.x,p.y,p.z)
        local objects=square and square:getObjects()
        if not objects or objects:size()>64 then return true end
        local Sites=require 'EmberRoutesProbe/SelfCare/ReposeSites'
        for i=0,objects:size()-1 do
            local object=objects:get(i)
            local meta=object:getModData().EmberRoutesRepose
            if meta and meta.id==h.objectId and meta.partId==h.partId then
                local quality,seats=require('EmberRoutesProbe/Settlement/SettlementFacilities').describe(object)
                if not quality and (not seats or seats<1) then return true end
                local proof=Sites.prepare({object=object,revision=meta.revision,key=h.targetKey,
                    settlementId=env.entry.id},env.actor,env.npc,env.id,'REST')
                if proof then
                    publish('SIT',{activity='SIT',key=proof.key,point=h.point,
                        benefit=Policy.weight('SIT',env.s,Config.weights.SIT or 1),
                        condition=conditions.SIT,
                        payload={site=proof,claims=Sites.keys(proof,'REST'),targetKey=proof.key}})
                end
                return true
            end
        end
        return true
    end
    local Facilities=require 'EmberRoutesProbe/Settlement/SettlementFacilities'
    local facility=Facilities.watch(env.entry,Facilities.describe)
    local location=math.floor(env.point.x)..':'..math.floor(env.point.y)..':'..env.point.z
    local stamp=tostring(facility.version)..':'..tostring(env.offer.seatEpoch or 0)..':'..location
    if env.state.stamp~=stamp and not env.state.iter then
        env.state.retryAt=nil env.state.stamp=stamp
        if nearby then env.state.offset=1 end
    end
    if env.now<(env.state.retryAt or 0) then return true end
    env.offer.blocked=env.offer.blocked or {}
    env.state.blocked=env.offer.blocked
    if not env.state.iter then
        env.state.iter=require('EmberRoutesProbe/SelfCare/ReposeSites').new(env.actor,env.npc,env.id,'REST',env.state.blocked,
            {seatingOnly=true,excludeBeds=true,preferredPoint=env.memory and env.memory.seatPreference,
                indexedOnly=nearby,maxDistance=nearby and 4 or nil,sameFloor=nearby,
                offset=nearby and env.state.offset or nil})
    end
    local slice=math.min(8,env.budget.scan)
    local found,done,reason,nextOffset=env.state.iter:step(slice)
    if nearby then env.state.offset=nextOffset or 1 end
    env.budget.scan=env.budget.scan-slice
    if not done then return false,reason end
    env.state.iter=nil
    if found then
        publish('SIT',{activity='SIT',key=found.key,point=objectPoint(found.object,env.point),
            benefit=Policy.weight('SIT',env.s,Config.weights.SIT or 1),
            condition=conditions.SIT,
            payload={found=found,preview=preview or nil}})
        return true
    end
    env.state.retryAt=env.now+Config.seatRetryMs
    return true
end
local function collectPublicLife(env)
    local candidate,done,reason=require('EmberRoutesProbe/Settlement/LifeZoneVisits').seek(env,rules.standable)
    if candidate then
        publish('PUBLIC_LIFE',{activity='PUBLIC_LIFE',key=candidate.targetKey,point=candidate.point,
            benefit=Config.weights.PUBLIC_LIFE,condition=conditions.PUBLIC_LIFE,
            payload={candidate=candidate}})
        return true
    end
    if not done then return false,reason end
    return true
end
local collectors={
    SOCIAL=collectSocial,
    READING=collectReading,
    SMOKE=collectSmoke,
    SIT=collectSit,
    PUBLIC_LIFE=collectPublicLife,
}
-- Refresh one activity's ads from its bounded source, then return the best
-- ad whose condition still holds. Returns ad|nil, done, reason with the
-- same protocol the Registry seek functions use.
function Ads.lookup(activity,env,opts)
    scope(env)
    drop(activity)
    local collect=collectors[activity]
    if not collect then return nil,true,'AD_UNKNOWN_ACTIVITY' end
    local done,reason=collect(env,opts)
    if not done then return nil,false,reason end
    return Ads.query(activity,env),true
end
return Ads
