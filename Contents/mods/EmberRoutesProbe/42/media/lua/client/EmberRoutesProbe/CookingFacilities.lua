-- Read-only installed-engine facts. No remote activation, naming heuristics or claims.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local F={}
-- ItemContainer.getTemperature returns 0.2 for powered native refrigeration.
local coldTemperature=0.2
function F.cold(endpoint,intent)
    local e,why=Registry.revalidate(endpoint,intent or 'take','local-world')
    if not e then return nil,why end
    local c=e.container
    if not c.isFridge or not c.isFreezer or not c.isPowered or not c.getTemperature then
        return nil,'COLD_READ_UNAVAILABLE'
    end
    if not c:isFridge() and not c:isFreezer() then return {cold=false,reason='NOT_REFRIGERATION'} end
    local temperature=c:getTemperature()
    if type(temperature)~='number' or temperature~=temperature or math.abs(temperature)==math.huge then
        return nil,'COLD_TEMPERATURE_UNKNOWN'
    end
    local powered=c:isPowered()
    return {id=e.id,cold=powered and temperature<=coldTemperature+0.000001,
        powered=powered,temperature=temperature,reason=not powered and 'COLD_UNPOWERED' or nil}
end
function F.stove(endpoint)
    local e,why=Registry.revalidate(endpoint,'put','local-world')
    if not e then return nil,why end
    local o,c=e.object,e.container
    if not instanceof(o,'IsoStove') then return nil,'NOT_STOVE' end
    ---@cast o IsoStove
    if not o.isMicrowave or not o.isBroken or not o.Activated or not c.isPowered
        or not o.getContainer then return nil,'STOVE_READ_UNAVAILABLE' end
    if o:isMicrowave() then return nil,'MICROWAVE_NOT_ADAPTED' end
    if o:getContainer()~=c then return nil,'STOVE_CONTAINER_CHANGED' end
    return {id=e.id,siteKey='cooking:'..e.id,active=o:Activated(),powered=c:isPowered(),broken=o:isBroken()}
end
return F
