-- Filter existing candidates only. Never creates a target, changes a score,
-- grants eligibility, or substitutes the NPC's current position for a worksite.
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local P={}
function P.zone(posting,entry)
    local zone,why=Zones.get(posting.zoneId)
    if not zone then return nil,why end
    if not zone.enabled or zone.settlementId~=entry.id or not Zones.coveredZone(entry,zone) then
        return nil,'POSTING_ZONE_INVALID'
    end
    return zone
end
function P.allows(posting,zone,candidate)
    if candidate.category~=posting.category then return false,'POSTING_FILTERED' end
    if not zone then return false,'POSTING_ZONE_INVALID' end
    local point=candidate.point
    if not point and candidate.object and candidate.object.getSquare then
        local square=candidate.object:getSquare()
        if square then point={x=square:getX(),y=square:getY(),z=square:getZ()} end
    end
    if not point and candidate.intent then
        local root=Registry.data()
        point=root.containers and root.containers[candidate.intent.source]
        -- Multi-source delivery must keep every existing pickup inside the posting.
        for _,source in pairs(candidate.intent.itemSources or {}) do
            local at=root.containers and root.containers[source]
            if not at or not Zones.contains(zone,at.x,at.y,at.z) then return false,'POSTING_FILTERED' end
        end
    end
    if not point and candidate.order and candidate.order.surfaceId then
        point=(Registry.data().craftSurfaces or {})[candidate.order.surfaceId]
    end
    if not point then return false,'POSTING_TARGET_UNAVAILABLE' end
    return Zones.contains(zone,point.x,point.y,point.z),'POSTING_FILTERED'
end
return P
