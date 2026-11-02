-- Craft domain facade; Production owns execution and save continuation.
local Probe=require 'EmberRoutesProbe/Boot'
local Work=require 'EmberRoutesProbe/Work'
local Driver=require 'EmberRoutesProbe/Driver'
local Log=require 'EmberRoutesProbe/Log'
local Production=require 'EmberRoutesProbe/Production'
local Craft={}
function Craft.record(id)
    local r=require('EmberRoutesProbe/ProductionJobs').record(id)
    return r and r.format==4 and r or nil
end
function Craft.prepareRecovery()
    local retirement=require('EmberRoutesProbe/CraftLegacyRecovery')
    for _ in pairs(retirement.records(require('EmberRoutesProbe/ContainerRegistry').data())) do
        require('EmberRoutesProbe/LaborStore').data() break
    end
    require('EmberRoutesProbe/ProductionJobs').prepareRecovery()
    require('EmberRoutesProbe/LaborStore').data()
end
function Craft.restoreCandidate(actor,id,jobId)
    local r=Craft.record(id)
    if not r or r.id~=jobId or r.released or r.uncertain or r.phase=='COMMITTING' then return false end
    return Production.execute(actor,'resume',nil,id,{nonPreemptive=true})=='QUEUED'
end
function Craft.stopAdapter(id,controller,ticket) return Production.stopAdapter(id,controller,ticket) end
function Craft.busy(id) return Production.busy(id) end
function Craft.retains(id) local r=Craft.record(id) return r and not r.released or false end
function Craft.pause(reason,id) return Production.pause(reason,id) end
function Craft.pauseAll(reason) return Production.pauseAll(reason) end
function Craft.reset() return Production.reset() end
function Craft.tick(id) return Production.tick(id) end
function Craft.execute(actor,command,object,npcId,quiet,options)
    local id=npcId or Driver.selected(actor)
    local ok,result=pcall(Production.execute,actor,command,object,id,options)
    if not ok then Log.write('PRODUCTION','COMMAND_ERROR '..tostring(result)) Production.pause('ERROR',id) result='ERROR' end
    if not quiet then actor:Say(getText('IGUI_EmberRoutesProbe_CraftResult',tostring(result))) end
    return result
end
function Craft.afterSave(results) return Production.afterSave(results) end
function Craft.tickPending() return Production.tickPending() end
function Craft.status(id) local r=Craft.record(id) return r and Production.status(r) end
Probe.afterCraftSave=Craft.afterSave
Probe.tickCrafting=Craft.tickPending
Work.registerExecutor('CRAFT_PROBE',Craft)
return Craft
