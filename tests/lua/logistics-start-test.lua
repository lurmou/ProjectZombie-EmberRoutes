-- F-12 start gate: public start reports DRIVER_UNAVAILABLE while dispatch is
-- closed, instead of an unconditional 'STARTED'. Standalone stubs only --
-- deliberately NOT via tests/lua/multi-worker-test.lua, whose fixture chain
-- is broken (missing tests/lua/work-test.lua, deleted in 59cb9b5) and whose
-- logistics-test.lua start assertions cover the deleted private branch.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end
local entry={id='s'}
local settings={suspended=true,intake=true,tidy=true,workers={}}
local javaOk=true
local allowed=true
local Probe={ready=true,runtimeReady=true,publicDispatch=true,
    hasJava=function() return javaOk end,
    registerReset=function() end}
Probe.isPublicDispatch=function() return Probe.publicDispatch==true end
package.loaded['EmberRoutesProbe/Kernel/Boot']=Probe
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={listeners={},inventoryListeners={},
    describe=function() return nil end,data=function() return {} end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={listeners={},
    view=function() if allowed then return entry end return nil,'ACCESS_DENIED' end,
    get=function() return entry end,data=function() return {factionId='f'} end}
package.loaded['EmberRoutesProbe/Settlement/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/Logistics/LogisticsStore']={
    get=function() return settings end,view=function() return settings end}
package.loaded['EmberRoutesProbe/Work/Work']={record=function() return nil end,
    lastCompleted=function() return nil end,busy=function() return false end,
    automationAllowed=function() return true end,pause=function() end,
    allowAutomation=function() end,resumeFor=function() return 'QUEUED' end,
    assign=function() return 'QUEUED' end,hasCargo=function() return false end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function() return nil end}
package.loaded['EmberRoutesProbe/Work/LaborProducers']={register=function() end,freeCarry=function() return 0 end}
package.loaded['EmberRoutesProbe/Warehouse/SortPolicy']={source=function() return nil end}
package.loaded['EmberRoutesProbe/Logistics/LogisticsPlanner']={new=function() return nil end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={watch=function() end}
function getTimestampMs() return 0 end
function isClient() return false end
function isServer() return false end
local Service=require 'EmberRoutesProbe/Logistics/LogisticsService'
local actor={isDead=function() return false end}
local function resetGate()
    Probe.ready=true Probe.runtimeReady=true javaOk=true Probe.publicDispatch=true
    settings.suspended=true
end
-- 1. Public start with the driver up clears suspension and reports STARTED.
resetGate()
check(Service.start(actor,'s')=='STARTED','public start with driver up reports STARTED')
check(settings.suspended==false,'public start clears suspended')
-- 5. 'STARTED' means un-suspended, not running: no ctx is built, so the
-- service's own projection still says STOPPED (F-12 §2.4, pinned as known
-- semantics -- change this only by changing the contract deliberately).
check(Service.running('s')==false,'public start builds no ctx so running stays false')
check(Service.status('s').reason=='STOPPED','public start leaves status reason STOPPED')
-- 2. ready=false refuses with the private branch's old code.
resetGate() Probe.ready=false
check(Service.start(actor,'s')=='DRIVER_UNAVAILABLE','public start with ready=false reports DRIVER_UNAVAILABLE')
check(settings.suspended==true,'refused start leaves suspended untouched')
-- 3. runtimeReady=false (mod disabled / RESET_REQUIRED) refuses likewise.
resetGate() Probe.runtimeReady=false
check(Service.start(actor,'s')=='DRIVER_UNAVAILABLE','public start with runtimeReady=false reports DRIVER_UNAVAILABLE')
-- 4. hasJava()=false refuses likewise.
resetGate() javaOk=false
check(Service.start(actor,'s')=='DRIVER_UNAVAILABLE','public start with hasJava()=false reports DRIVER_UNAVAILABLE')
-- 6. No private fallback (F-05): with public dispatch not loaded the gate
-- passes but there is nothing that can dispatch, so the driver is reported
-- unavailable rather than a false 'STARTED'.
resetGate() Probe.publicDispatch=false
check(Service.start(actor,'s')=='DRIVER_UNAVAILABLE','start with publicDispatch off reports DRIVER_UNAVAILABLE')
print("PASS "..checks.." logistics start-gate assertions")
