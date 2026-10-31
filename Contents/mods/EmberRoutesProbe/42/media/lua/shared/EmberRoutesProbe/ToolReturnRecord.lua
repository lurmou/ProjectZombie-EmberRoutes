-- Tool return record validator.
-- Represents an independent tool return task under TaskRuntime.
local Validate=require 'EmberRoutesProbe/Validate'
local R={}

local validPhases={APPROACH=true,TRANSFER=true,SETTLED=true}
local validStates={RUNNING=true,DONE=true,CANCELLED=true,FAILED=true}

function R.valid(entry)
    if type(entry)~='table' then return false end
    if entry.format~=1 then return false end
    if not Validate.stringId(entry.id) then return false end
    if not Validate.stringId(entry.npcId) and not Validate.integer(entry.npcId,0) then return false end
    if not Validate.stringId(entry.custodyId) then return false end
    if not Validate.itemId(entry.itemId) then return false end
    if not Validate.stringId(entry.role) then return false end
    if not validPhases[entry.phase] then return false end
    if not validStates[entry.state] then return false end
    if entry.destinationId~=nil and not Validate.stringId(entry.destinationId) then return false end
    if not Validate.integer(entry.sequence,0) then return false end
    return true
end

return R
