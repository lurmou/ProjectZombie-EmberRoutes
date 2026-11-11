require 'ISUI/ISRadialMenu'
require 'ISUI/PlayerData/ISPlayerData'
local Binding=require 'EmberRoutesProbe/Settlement/SquadKeys'
local HUD=require 'EmberRoutesProbe/UI/SquadHUD'
local T=require 'EmberRoutesProbe/Settlement/MembershipText'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local UI={}
local hud,wheel,pendingShow,installed
local function label(key) return getText('IGUI_EmberRoutesProbe_Squad_'..key) end
local function closeWheel()
    local old=wheel wheel=nil
    if old then old.used=true old.menu:undisplay() end
end
local function enabled(actor)
    return actor and not actor:isDead() and SandboxVars and SandboxVars.EmberRoutes
        and SandboxVars.EmberRoutes.CarrierProbe
end
local function inputAvailable()
    return not getCore():isDoingTextEntry() and not UIManager.isModalVisible()
        and UIManager.getSpeedControls() and UIManager.getSpeedControls():getCurrentGameSpeed()>0
end
local function vanillaVisible()
    local menu=getPlayerRadialMenu(0)
    return menu and menu:isReallyVisible()
end
function UI.openWheel(panel,byKey)
    closeWheel()
    if not panel.active or not panel.session:valid() or vanillaVisible() or not inputAvailable() then return end
    panel.session:refresh(Clock.nowMs()) panel:project()
    local targets=panel.session:targets(panel.selected)
    if #targets==0 then return end
    local h=panel.h
    local menu=ISRadialMenu:new(0,0,math.max(40,h*2),math.max(140,h*7),0)
    menu:initialise() menu:instantiate()
    local state={menu=menu,panel=panel,scope=panel.activationScope,targets=targets,byKey=byKey}
    wheel=state
    menu.onMouseDownOutside=function() closeWheel() end
    local function add(kind,slot,text)
        menu:addSlice(text,nil,function()
            -- Native click removes the wheel first; invalidate ownership before submission.
            if state.used or wheel~=state or not state.scope:isCurrent() then return end
            closeWheel()
            if not panel.session:valid() or vanillaVisible() or not inputAvailable() then return end
            panel.session:command(targets,kind,slot)
            panel.session:refresh(Clock.nowMs()) panel:project()
        end)
    end
    add('FOLLOW',nil,T.reason('FOLLOW')..' ('..tostring(#targets)..')')
    add('WAIT',nil,T.reason('WAIT')) add('RETURN',nil,T.reason('RETURN'))
    add('DISMISS',nil,T.reason('DISMISS'))
    if #targets==1 then
        for slot=0,2 do add('FOLLOW',slot,T.reason('FOLLOW_SLOT_'..slot)) end
    end
    menu:center() menu:addToUIManager() menu:setVisible(true)
end
function UI.show(actor)
    if not enabled(actor) then return end
    if hud and (hud.actor~=actor or hud.disposed) then hud:close() hud=nil end
    if not hud then
        hud=HUD:new(actor,UI.openWheel,function() closeWheel() end)
        hud:initialise() hud:instantiate()
    end
    hud:show() return hud
end
function UI.reset()
    pendingShow=false closeWheel()
    if hud then hud:close() hud=nil end
end
function UI.keyStart(key)
    if key==Keyboard.KEY_ESCAPE and wheel then closeWheel() return end
    if key~=getCore():getKey(Binding) or not inputAvailable() or vanillaVisible() then return end
    local panel=UI.show(getSpecificPlayer(0))
    if panel then UI.openWheel(panel,true) end
end
function UI.keyRelease(key)
    if key~=getCore():getKey(Binding) or not wheel or not wheel.byKey then return end
    local state=wheel
    if not state.scope:isCurrent() or not state.panel.session:valid() or not inputAvailable() or vanillaVisible() then
        closeWheel() return
    end
    local menu=state.menu
    local index=menu.javaObject:getSliceIndexFromMouse(getMouseX()-menu:getAbsoluteX(),getMouseY()-menu:getAbsoluteY())
    local command=menu:getSliceCommand(index+1)
    if command and command[1] then command[1](command[2],command[3],command[4],command[5],command[6],command[7])
    else closeWheel() end
end
function UI.tick()
    if pendingShow then
        local actor=getSpecificPlayer(0)
        if actor then pendingShow=false UI.show(actor) end
    end
    if wheel and (not wheel.scope:isCurrent() or not wheel.panel.session:valid() or vanillaVisible()
        or not inputAvailable()) then closeWheel() end
end
function UI.resolutionChanged()
    closeWheel()
    if hud and hud.active then hud:relayout() end
end
function UI.install()
    if installed then return end installed=true
    Events.OnGameStart.Add(function() pendingShow=true end)
    Events.OnNewGame.Add(function() pendingShow=true end)
    Events.OnPreMapLoad.Add(UI.reset)
    Events.OnResolutionChange.Add(UI.resolutionChanged)
    Events.OnKeyStartPressed.Add(UI.keyStart) Events.OnKeyPressed.Add(UI.keyRelease)
    Events.OnTick.Add(UI.tick)
end
return UI
