-- Explicit host-only admission adaptation for unchanged FIELD regression files.
-- Models the bridge; does NOT verify Java or engine behaviour.
local allowed={['field-work-test']=true,['field-tool-supply-test']=true,['field-continuous-batch-test']=true}
local name=assert(arg[1],'FIELD regression name required') assert(allowed[name],'FIELD only')
local Commit=require 'EmberRoutesProbe/LaborJobCommit'
local install=Commit.install
Commit.install=function(Store,state,allocate,clean)
    local previous=EmberRoutesProbeJava or {}
    local model=dofile('tests/lua/fixtures/dec003-field-kernel-host.lua')
    model.install(state,allocate,clean)
    for k,v in pairs(previous) do if EmberRoutesProbeJava[k]==nil then EmberRoutesProbeJava[k]=v end end
    return install(Store,state,allocate,clean)
end
dofile('tests/lua/'..name..'.lua')
