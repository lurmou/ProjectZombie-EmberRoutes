-- FIELD-only decisions. Runtime lifecycle and asset authority stay with their owners.
local W={}
local function cargoPhase(c)
    local held=false
    for _,a in ipairs(c.job.payload.assets) do
	if a.custody=='GROUND' then return 'COLLECT' end
	if a.custody=='HELD' then held=true end
    end
    return held and 'DELIVER' or nil
end
local function settledStep(c)
    local p=c.job.payload local a=p.attempt
    return c.job.effects=='KNOWN' and not p.holding and not p.capacity and not p.toolSupply
	and (not a or a.state=='APPLIED' or a.state=='ABORTED')
end
local function continueOrFinish(c,def)
    if not settledStep(c) then c.reason='FIELD_WORK_UNSETTLED' return 'Failure' end
    if not c.recoveryOnly and def.continue and def.continue(c) then return 'Running' end
    if not settledStep(c) then c.reason=c.reason or 'FIELD_WORK_UNSETTLED' return 'Failure' end
    return 'Success'
end
function W.step(c,def)
    local phase=c.job.payload.phase
    if phase=='PREPARE' then return require('EmberRoutesProbe/FieldSupplies').step(c) end
    if phase=='WORK' then
	local result=def.step(c)
	if result~='Success' then return result end
	if c.job.effects~='KNOWN' or c.job.payload.holding then
	    c.reason='FIELD_WORK_UNSETTLED' return 'Failure'
	end
	local a=c.job.payload.attempt
	if a and a.state~='APPLIED' and a.state~='ABORTED' then
	    c.reason='FIELD_WORK_UNSETTLED' return 'Failure'
	end
	c.node=nil c.path=nil
	local nextPhase=cargoPhase(c)
	if nextPhase then
	    if not c.change(function(j) j.payload.phase=nextPhase end) then return 'Failure' end
	    return 'Running'
	end
	return continueOrFinish(c,def)
    end
    if phase~='COLLECT' and phase~='DELIVER' then
	c.reason='FIELD_PHASE_CHANGED' return 'Failure'
    end
    local result=require('EmberRoutesProbe/FieldCargo').step(c,def)
    if result~='Success' then return result end
    if cargoPhase(c) then c.reason='FIELD_WORK_UNSETTLED' return 'Failure' end
    c.node=nil c.path=nil
    return continueOrFinish(c,def)
end
return W
