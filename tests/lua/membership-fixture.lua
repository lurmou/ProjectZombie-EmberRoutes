-- Explicit new-model fixture for unrelated native/consumer tests. Not loaded by production.
return function(getEntry,ids)
    local first=getEntry() local rows={} local service={}
    for _,id in ipairs(ids) do rows[id]={npcId=id,factionId='fixture',context='SETTLEMENT',settlementId=first.id,revision=1} end
    function service.view(id) return rows[id] end
    function service.character() return 'fixture-leader' end
    function service.entry(id,scope)
        local e=getEntry() local row=rows[id]
        if not row or not e or scope and scope~=row.settlementId then return nil,'TARGET_LOST' end
        return e,nil,row.revision
    end
    function service.check(id,purpose,at,expected)
        local r=rows[id] local e=service.entry(id,at and at.scopeId)
        local allowed=r~=nil and e~=nil local reason='NO_MEMBERSHIP'
        if expected and (not r or r.revision~=expected) then allowed=false reason='STALE_MEMBERSHIP'
        elseif purpose=='RECOVERY' or purpose=='SELF_CARE' then allowed=true
        elseif r and r.context~='SETTLEMENT' then allowed=false reason='CONTEXT_'..r.context
        elseif r and r.pending then allowed=false reason='COMMAND_PENDING'
        elseif e and e.areas and at and not require('EmberRoutesProbe/SettlementGeometry').inside(e,at.x,at.y) then allowed=false reason='OUTSIDE_SETTLEMENT' end
        return {allowed=allowed,reason=not allowed and reason or nil,revision=r and r.revision,
            sharedResources=(purpose=='SELF_CARE' or purpose=='RECOVERY') and r and e
                and (r.context=='SETTLEMENT' or r.context=='WAIT') and (not e.areas or not at or require('EmberRoutesProbe/SettlementGeometry').inside(e,at.x,at.y)),
            settlementId=r and r.settlementId,context=r and r.context,entryRevision=e and e.revision}
    end
    package.loaded['EmberRoutesProbe/MembershipService']=service
    return rows
end
