-- Tool custody durable record validator.
-- Represents a persistent tool custody held by an NPC across multiple jobs.
local Validate=require 'EmberRoutesProbe/Validate'
local R={}

local validStates={RESERVED=true,HELD=true,PENDING_RETURN=true}

function R.valid(entry)
    if type(entry)~='table' then return false end
    if entry.format~=1 then return false end
    if not Validate.stringId(entry.id) then return false end
    if not Validate.stringId(entry.npcId) and not Validate.integer(entry.npcId,0) then return false end
    if not Validate.itemId(entry.itemId) then return false end
    if not Validate.stringId(entry.role) then return false end
    if not validStates[entry.state] then return false end
    if not Validate.integer(entry.sequence,0) then return false end
    if entry.activeJobId~=nil and not Validate.stringId(entry.activeJobId) then return false end
    if entry.sourceContainerId~=nil and not Validate.stringId(entry.sourceContainerId) then return false end
    if type(entry.claims)~='table' or #entry.claims~=1 or entry.claims[1]~=('item:'..entry.itemId) then
        return false
    end
    return true
end

return R
