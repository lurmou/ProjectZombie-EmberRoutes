-- Incremental destination discovery only. Reuses the caller's scan/path budget;
-- the existing personal Job remains the sole owner of movement and stopping.
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Config=require 'EmberRoutesProbe/LeisureConfig'
local Visits={}
function Visits.tileKey(point)
    return require('EmberRoutesProbe/LeisureRecord').tileKey(point)
end
local function seed(id)
    local n=0 for i=1,#id do n=(n*31+id:byte(i))%65521 end return n
end
local function clamp(n,a,b) return math.max(a,math.min(b,n)) end
function Visits.seek(env,standable)
    if not require('EmberRoutesProbe/LeisurePolicy').allowed('STROLL',env.s,{hold=true})
        or env.hours<((env.memory or {}).moveAfter or 0) then return nil,true end
    if env.budget.scan<1 then return nil,false,'LIFE_ZONE_OBSERVING' end
    local revision,why=Zones.revision() if revision==nil then return nil,true,why end
    local state=env.state
    local context=env.eventId and env.eventId..':'..tostring(env.activityRef and env.activityRef.participantEpoch or 1) or false
    local destination=env.destination or Zones.destination
    local position=math.floor(env.point.x)..':'..math.floor(env.point.y)..':'..env.point.z
    if state.revision~=revision or state.parent~=env.entry.revision or state.position~=position or state.context~=context then
        local zones,reason
        if env.destinationZone then zones={env.destinationZone} else zones,reason=Zones.list(env.entry.id) end
        if not zones then return nil,true,reason end
        -- At most 32 detached records, once per changed discovery context.
        table.sort(zones,function(a,b)
            local function distance(row)
                local r=row.area
                local dx=env.point.x-clamp(env.point.x,r.x,r.x+r.w-1)
                local dy=env.point.y-clamp(env.point.y,r.y,r.y+r.h-1)
                return dx*dx+dy*dy+math.abs(env.point.z-r.z)*144
            end
            local da,db=distance(a),distance(b)
            return da==db and a.id<b.id or da<db
        end)
        state.revision,state.parent,state.position=revision,env.entry.revision,position
        state.context=context
        state.zones,state.index,state.offset,state.retryAt=zones,1,0,nil
        state.inside=false
        for _,row in ipairs(zones) do
            if row.enabled and env.point.z==row.area.z and Geometry.contains(row.area,env.point.x,env.point.y)
                and destination(env.entry.id,{id=row.id,revision=row.revision,eventId=env.eventId},env.point) then
                state.inside=true break
            end
        end
    end
    -- Do not keep relocating someone who already reached a usable common area.
    if state.inside or #state.zones==0 then return nil,true end
    if env.now<(state.retryAt or 0) then return nil,true end
    local used=0
    while state.index<=#state.zones and env.budget.scan>0 and used<4 do
        local row=state.zones[state.index] local area=row.area
        local key='life-zone:'..row.id..':'..row.revision..(env.eventId and ':'..env.eventId or '')
        env.budget.scan=env.budget.scan-1 used=used+1
        if not row.enabled or not Zones.covered(env.entry,area)
            or env.now<((env.offer.blocked or {})[key] or 0) then
            state.index=state.index+1 state.offset=0
        else
            -- Spread visitors deterministically over a small window nearest the
            -- approach side. Never scan all tiles or interpret sampling as capacity.
            local w,h=math.min(9,area.w),math.min(9,area.h)
            local x=clamp(math.floor(env.point.x)-4,area.x,area.x+area.w-w)
            local y=clamp(math.floor(env.point.y)-4,area.y,area.y+area.h-h)
            local n=(seed(env.id)+state.offset)%(w*h)
            local point={x=x+n%w+.5,y=y+math.floor(n/w)+.5,z=area.z}
            state.offset=state.offset+1
            if state.offset>=math.min(64,w*h) then state.index=state.index+1 state.offset=0 end
            local ref={id=row.id,revision=row.revision,eventId=env.eventId}
            if env.activityRef then
                ref.controlEpoch=env.activityRef.controlEpoch
                ref.participantEpoch=env.activityRef.participantEpoch
                ref.commandEpoch=env.activityRef.commandEpoch
                ref.membershipRevision=env.activityRef.membershipRevision
            end
            if destination(env.entry.id,ref,point)
                and not require('EmberRoutesProbe/LaborStore').resourceOwner(Visits.tileKey(point))
                and standable(env.entry,point,{env.npc}) then
                return {activity='OBSERVE',point=point,entry=env.entry,pure=true,publicVisit=true,
                    targetKey=key,weight=Config.weights.PUBLIC_LIFE,
                    leisure={format=1,activity='OBSERVE',point=point,hours=env.hours,moving=true,zoneVisit=ref}},true
            end
        end
    end
    if state.index>#state.zones then
        state.index,state.offset,state.retryAt=1,0,env.now+Config.seatRetryMs
        return nil,true,'LIFE_ZONE_UNOBSERVED_OR_UNAVAILABLE'
    end
    return nil,false,'LIFE_ZONE_OBSERVING'
end
return Visits
