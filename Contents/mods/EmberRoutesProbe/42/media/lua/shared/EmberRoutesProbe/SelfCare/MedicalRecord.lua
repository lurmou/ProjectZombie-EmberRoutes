-- Versioned per-attempt evidence; absence of a material alone never proves treatment.
local V=require 'EmberRoutesProbe/Kernel/Validate'
local M={}
local phases={PREPARED=true,REMOVING=true,READY=true,APPLYING=true,APPLIED=true,STOPPED=true,UNKNOWN=true}
function M.valid(p)
    local m=p.medical
    if m==nil then return p.kind~='MEDICAL' end
    if p.kind~='MEDICAL' or type(m)~='table' or m.version~=1 or m.attemptId~=p.attemptId
        or not V.integer(m.partIndex,0,63) or m.itemId~=p.itemId or not V.itemId(m.itemId)
        or not V.stringId(m.fullType) or not phases[m.phase] or type(m.replace)~='boolean'
        or type(m.applied)~='boolean' or type(m.removed)~='boolean'
        or m.stopped~=nil and type(m.stopped)~='boolean'
        or m.oldType~=nil and not V.stringId(m.oldType)
        or m.effects~='KNOWN' and m.effects~='UNKNOWN' or type(m.outputs)~='table' or #m.outputs>1 then return false end
    local n=0 for key,id in pairs(m.outputs) do
        n=n+1 if key~=1 or not V.itemId(id) or id==m.itemId then return false end
    end
    if n~=#m.outputs or m.applied and (m.phase~='APPLIED' and m.phase~='STOPPED' or m.effects~='KNOWN') then return false end
    local inFlight=m.phase=='REMOVING' or m.phase=='APPLYING' or m.phase=='UNKNOWN'
    if (m.effects=='UNKNOWN')~=inFlight then return false end
    if m.phase=='APPLIED' and not m.applied or m.removed and not m.replace or #m.outputs>0 and not m.removed then return false end
    return true
end
function M.consumed(p) return p.medical and p.medical.applied==true and p.medical.effects=='KNOWN' or false end
return M
