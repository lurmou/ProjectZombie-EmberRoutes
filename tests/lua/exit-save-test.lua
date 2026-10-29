-- Real persistence/menu adapter; model delayed native pose exit and world swap.
local checks,clock,prepared,exits,ready=0,0,0,0,false
local function check(v,m) checks=checks+1 assert(v,m) end
local root={} local say={}
local actor={isDead=function() return false end,getCurrentSquare=function() return {} end,
    Say=function(_,s) say[#say+1]=s end}
function getSpecificPlayer() return actor end
function getTimestampMs() return clock end
function getText(k) return k end
function isClient() return false end function isServer() return false end
function isQuitCooldown() return false end
function setGameSpeed(n) check(n==1,'normal simulation needed for native get-up') end
KeybindId={MAIN_MENU=1}
function getCore() return {getKey=function() return 1 end} end
local visible=true
function ToggleEscapeMenu() visible=false end
local start
Events={OnGameStart={Add=function(fn) start=fn end}}
local Probe={enabled=true,ready=true,controlledExecution=true,hasJava=function() return true end}
package.loaded['EmberRoutesProbe/Boot']=Probe
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
for _,name in ipairs({'Companion','Actions','PersistenceSamples','TaskDiagnostic'}) do
    package.loaded['EmberRoutesProbe/'..name]={}
end
local failures=0
package.loaded['EmberRoutesProbe/TaskPersistence']={
    prepare=function() prepared=prepared+1 return true end,
    ready=function() return ready end,pending=function() return false end,tick=function() end,
    failed=function() failures=failures+1 end}
MainScreen={instance={inGame=true,isVisible=function() return visible end,exitOption={}},
    onMenuItemMouseDownMainMenu=function() exits=exits+1 end,
    quitToDesktop=function() exits=exits+10 end}
local Persistence=require 'EmberRoutesProbe/Persistence'
start()
MainScreen.instance.exitOption.onMouseDown({internal='EXIT'},0,0)
check(prepared==1 and exits==0 and not visible,'return-to-menu waits and resumes simulation')
MainScreen.onMenuItemMouseDownMainMenu({internal='EXIT'},0,0)
check(prepared==1 and exits==0,'repeated click does not start a second barrier')
Persistence.tick()
check(exits==0,'no native quit before pose exit')
ready=true Persistence.tick() Persistence.tick()
check(exits==1,'original menu exit runs once after body drain')
ready=false visible=true MainScreen:quitToDesktop()
check(prepared==2 and exits==1,'confirmed desktop quit also drains')
root={} ready=true Persistence.tick()
check(exits==1,'old-world quit callback cannot exit successor world')
ready=false MainScreen:quitToDesktop() clock=16000 Persistence.tick()
check(exits==1 and failures==1,'timed-out pose does not proceed to destructive quit/save')
function isClient() return true end
MainScreen:quitToDesktop()
check(exits==11 and prepared==3,'multiplayer retains native quit')
print('PASS '..checks..' exit/save boundary checks; native animation and disk not simulated')
