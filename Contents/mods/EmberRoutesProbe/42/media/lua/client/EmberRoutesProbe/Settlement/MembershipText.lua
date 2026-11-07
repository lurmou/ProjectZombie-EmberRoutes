local T={}
function T.reason(code)
    return code and (getTextOrNull('IGUI_EmberRoutesProbe_Membership_'..code) or code) or ''
end
function T.summary(row)
    if not row then return T.reason('NO_MEMBERSHIP') end
    local name=row.settlementName or (row.settlementId and T.reason('TARGET_LOST') or T.reason('UNASSIGNED'))
    local result=name..' | '..T.reason(row.context)
    result=result..' | '..T.reason('BED')..': '..(row.bedId and T.reason('BED_ASSIGNED') or T.reason('BED_NONE'))
    if row.bedReason and row.bedReason~='BED_NONE' then result=result..' | '..T.reason(row.bedReason) end
    if row.posting then result=result..' | '..T.reason('POSTING')..': '..(row.postingName or T.reason('POSTING_ZONE_INVALID'))..' / '..getText('IGUI_EmberRoutesProbe_Public_'..row.posting.category) end
    if row.postingReason then result=result..' | '..T.reason(row.postingReason) end
    if row.pending then result=result..' | '..T.reason('ACCEPTED_PENDING') end
    if row.reason and row.reason~='COMMAND_PENDING' then result=result..' | '..T.reason('BLOCKED')..': '..T.reason(row.reason)
    elseif not row.pending and row.lastCommand then
        if row.lastCommand.kind=='RETURN' then
            result=result..' | '..T.reason(row.context=='SETTLEMENT' and 'RETURN_COMPLETED' or 'ACCEPTED_PENDING')
        elseif row.lastCommand.kind=='WAIT' and row.context=='WAIT' then result=result..' | '..T.reason('WAIT_COMPLETED') end
    end
    return result
end
function T.obligations(row)
    local result={}
    for _,o in ipairs(row and row.obligations or {}) do
        local item=o.fullType and getItemNameFromFullType and getItemNameFromFullType(o.fullType)
        result[#result+1]={text=T.reason(o.kind)..(item and ': '..item or '')..(o.count and ' x'..o.count or '')}
    end
    return result
end
return T
