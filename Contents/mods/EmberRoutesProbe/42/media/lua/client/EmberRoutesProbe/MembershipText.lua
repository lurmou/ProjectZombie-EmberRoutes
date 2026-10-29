local T={}
function T.reason(code)
    return code and (getTextOrNull('IGUI_EmberRoutesProbe_Membership_'..code) or code) or ''
end
function T.summary(row)
    if not row then return T.reason('NO_MEMBERSHIP') end
    local name=row.settlementName or (row.settlementId and T.reason('TARGET_LOST') or T.reason('UNASSIGNED'))
    local result=name..' | '..T.reason(row.context)
    if row.pending then result=result..' | '..T.reason('PENDING') end
    if row.reason then result=result..' | '..T.reason(row.reason) end
    return result
end
function T.obligations(row)
    local result={}
    for _,o in ipairs(row and row.obligations or {}) do
        local item=o.fullType and getItemNameFromFullType and getItemNameFromFullType(o.fullType)
        result[#result+1]={text=T.reason(o.kind)..(item and ': '..item or '')..(o.count and ' ×'..o.count or '')}
    end
    return result
end
return T
