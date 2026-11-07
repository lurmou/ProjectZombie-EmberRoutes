-- Validates adapter assertions, not engine state. Never infer stop from a timer.
local Evidence={}
function Evidence.validate(value)
    if type(value)~='table' or value.bodyStopped~=true then return nil,'BODY_NOT_STOPPED' end
    if value.effects~='KNOWN' and value.effects~='UNKNOWN' then return nil,'EFFECTS_REQUIRED' end
    if value.persisted~=true then return nil,'EFFECTS_NOT_PERSISTED' end
    return {bodyStopped=true,effects=value.effects}
end
return Evidence
