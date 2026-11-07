-- Own native menu contents/dialogs for one HUD activation, never business state.
require 'ISUI/ISContextMenu'
require 'ISUI/ISTextBox'
local T=require 'EmberRoutesProbe/Settlement/MembershipText'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local M={}
local function label(key) return getText('IGUI_EmberRoutesProbe_Squad_'..key) end
function M.close(panel)
    local menu=panel.contextMenu
    if menu and menu.options[1] and menu.options[1].onSelect==panel.contextCallback then
        menu:hideAndChildren()
    end
    panel.contextMenu=nil panel.contextCallback=nil
    local dialog=panel.callsignDialog panel.callsignDialog=nil
    if dialog then
        dialog.entry:unfocus()
        if dialog.colorPicker then dialog.colorPicker:removeFromUIManager() end
        dialog:destroy()
    end
end
local function context(panel,x,y)
    M.close(panel)
    panel.closeCommands(panel)
    panel:setHover(nil)
    local menu=ISContextMenu.get(0,x,y)
    panel.contextMenu=menu
    return menu
end
local function option(panel,menu,text,callback,disabled)
    local scoped=panel.activationScope:wrapCallback(function() callback() end)
    local item=menu:addOption(text,nil,scoped)
    item.notAvailable=disabled==true
    if not panel.contextCallback then panel.contextCallback=item.onSelect end
    return item
end
function M.rename(panel,id)
    M.close(panel)
    local scope=panel.activationScope
    local current=panel.preferences.value.callsigns[id] or ''
    local dialog=ISTextBox:new(0,0,320,180,label('callsignPrompt'),current,nil,
        scope:wrapCallback(function(_,button)
            local dialog=panel.callsignDialog panel.callsignDialog=nil
            if dialog then
                dialog.entry:unfocus()
                if dialog.colorPicker then dialog.colorPicker:removeFromUIManager() end
            end
            if button.internal~='OK' then return end
            local targets=panel.session:targets({[id]=true})
            if #targets==1 and targets[1].id==id then
                panel.preferences:setCallsign(id,button.parent.entry:getText()) panel:project()
            end
        end),0)
    dialog:initialise() dialog:instantiate()
    dialog.entry:setMaxTextLength(24)
    Theme.button(dialog.yes,true) Theme.button(dialog.no,false)
    panel.callsignDialog=dialog dialog:addToUIManager() dialog.entry:focus()
end
function M.member(panel,id,x,y)
    local targets=panel.session:targets({[id]=true})
    if #targets~=1 or targets[1].id~=id then return end
    local menu=context(panel,x,y)
    for _,kind in ipairs({'FOLLOW','WAIT','RETURN','DISMISS'}) do
        local command=kind
        option(panel,menu,T.reason(command),function()
            panel.session:command(targets,command) panel.session:invalidate(id)
        end)
    end
    for slot=0,2 do
        local rank=slot
        option(panel,menu,T.reason('FOLLOW_SLOT_'..rank),function() panel.session:command(targets,'FOLLOW',rank) end)
    end
    option(panel,menu,label('callsign'),function() M.rename(panel,id) end,not panel.preferences.writable)
    option(panel,menu,label('clearCallsign'),function() panel.preferences:setCallsign(id,'') panel:project() end,
        not panel.preferences.writable or not panel.preferences.value.callsigns[id])
end
function M.settings(panel,x,y)
    local menu=context(panel,x,y)
    for _,field in ipairs({'scale','buttonScale'}) do
        for _,scale in ipairs({0.85,1,1.2,1.4}) do
            local name,value=field,scale
            local item=option(panel,menu,label(name)..' '..tostring(math.floor(value*100))..'%',function()
                panel.preferences:setScale(name,value) panel:relayout()
            end,not panel.preferences.writable)
            item.checkMark=panel.preferences.value[name]==value
        end
    end
    option(panel,menu,label('resetLayout'),function() panel.preferences:resetLayout() panel:relayout() end,
        not panel.preferences.writable)
end
return M
