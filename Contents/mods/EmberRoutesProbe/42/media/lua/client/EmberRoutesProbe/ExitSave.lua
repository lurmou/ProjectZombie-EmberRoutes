-- Adapt the installed vanilla pause-menu entrypoints; the existing persistence
-- coordinator retains all body, effect, timeout and world-generation checks.
local E={}
local installed
function E.install(persistence)
    local function bind()
        local screen=_G.MainScreen
        if not screen then return end
        if not installed then
            local gameSpeed,quitCooldown=_G.setGameSpeed,_G.isQuitCooldown
            local menu,desktop=screen.onMenuItemMouseDownMainMenu,screen.quitToDesktop
            if type(menu)~='function' or type(desktop)~='function'
                or type(gameSpeed)~='function' or type(quitCooldown)~='function' then return end
            local function resume()
                local instance=screen.instance
                if instance and instance:isVisible() then
                    -- Vanilla restores UI, sound and joypad focus on this path.
                    ToggleEscapeMenu(getCore():getKey(KeybindId.MAIN_MENU))
                end
                gameSpeed(1)
            end
            screen.onMenuItemMouseDownMainMenu=function(item,x,y)
                local instance=screen.instance
                if item.internal=='EXIT' and instance and instance.inGame and not quitCooldown()
                    and persistence.requestExit(function() menu(item,x,y) end) then
                    resume() return
                end
                return menu(item,x,y)
            end
            screen.quitToDesktop=function(self)
                if screen.instance and screen.instance.inGame
                    and persistence.requestExit(function() desktop(self) end) then
                    resume() return
                end
                return desktop(self)
            end
            installed=true
        end
        -- Vanilla labels capture their callback when the menu is constructed.
        if screen.instance and screen.instance.exitOption then
            screen.instance.exitOption.onMouseDown=screen.onMenuItemMouseDownMainMenu
        end
    end
    if Events and Events.OnGameStart then Events.OnGameStart.Add(bind) end
end
return E
