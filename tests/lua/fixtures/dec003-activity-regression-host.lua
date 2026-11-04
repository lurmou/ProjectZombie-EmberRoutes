-- Explicit host bridge injection for existing ACTIVITY regression entrypoints.
-- Assertions and real production chain remain unchanged; not Java verification.
local name=assert(arg[1],'ACTIVITY regression name required')
assert(string.match(name,'^activity%-[%w%-]+%-test$'),'ACTIVITY tests only')
-- Optional frozen HEAD oracle distinguishes pre-existing assertion failures.
if arg[2]=='baseline' then
    package.preload['EmberRoutesProbe/ActivityParticipant']=function()
        return dofile('tests/lua/fixtures/dec003-pre-kernel-activity-participant.lua')
    end
    local Adapters=require 'EmberRoutesProbe/LaborDomainAdapters'
    local current=Adapters.install
    Adapters.install=function(...)
        current(...)
        dofile('tests/lua/fixtures/dec003-pre-kernel-activity-adapter.lua').install(...)
    end
end
local Commit=require 'EmberRoutesProbe/LaborJobCommit'
local install=Commit.install
Commit.install=function(Store,state,allocate,clean)
    local previous=EmberRoutesProbeJava or {}
    local model=dofile('tests/lua/fixtures/dec003-activity-kernel-host.lua')
    model.install(state,allocate,clean)
    for k,v in pairs(previous) do if EmberRoutesProbeJava[k]==nil then EmberRoutesProbeJava[k]=v end end
    return install(Store,state,allocate,clean)
end
dofile('tests/lua/'..name..'.lua')
