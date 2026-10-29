-- Durable fixed-batch identity only; no native handles, claims or body control.
local Record=require 'EmberRoutesProbe/CookingRecord'
local B={}
function B.prepare(job,selection)
    if not Record.valid(job) or job.payload.source~='REQUEST' or job.effects~='KNOWN' or job.payload.sequence~=0
        or job.payload.fixed or #job.payload.assets>0 or #job.payload.claims>0
        or type(selection)~='table' or type(selection.entries)~='table'
        or #selection.entries==0 or #selection.entries>16 then return nil,'COOKING_BATCH_INVALID' end
    local profile=selection.profile local facts=profile and profile.facts
    if not facts or facts.id~=job.payload.profileId or type(profile.roots)~='table' then return nil,'COOKING_PROFILE_CHANGED' end
    local rows,counts={},{}
    for _,row in ipairs(profile.roots) do rows[row.slot]=row counts[row.slot]=0 end
    local j=Record.copy(job)
    j.payload.fixed={recipeId=facts.id,signature=facts.signature,inputs={}}
    for _,entry in ipairs(selection.entries) do
        local row=rows[entry.slot] local item=entry.item
        if not row or not item or item:getID()~=entry.id then return nil,'INPUT_CHANGED' end
        counts[entry.slot]=counts[entry.slot]+1
        local source=entry.endpoint and entry.endpoint.id
        j.payload.fixed.inputs[#j.payload.fixed.inputs+1]={id=entry.id,slot=entry.slot,sourceId=source,keep=row.keep}
        j.payload.assets[#j.payload.assets+1]={id=entry.id,fullType=item:getFullType(),
            custody=source and 'SOURCE' or 'HELD',role=row.keep and 'TOOL' or 'INPUT'}
        j.payload.claims[#j.payload.claims+1]='item:'..entry.id
    end
    for slot,row in pairs(rows) do if counts[slot]~=row.count then return nil,'INPUT_BINDING_INVALID' end end
    if not Record.valid(j) then return nil,'COOKING_BATCH_INVALID' end
    return j
end
return B
