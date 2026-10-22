local Theme=require "EmberRoutesProbe/UI/Theme"
local Input={}
function Input.active(panel,list)
    return panel.focusedList==list and not panel.helpModal and not panel.search:isFocused()
        and not panel.categories.expanded and not panel.controls.sort.expanded
end
function Input.focus(panel,list)
    if not list then return end
    panel.focusedList=list
    panel.itemList.borderColor=list==panel.itemList and Theme.accent or Theme.border
    panel.sourceList.borderColor=list==panel.sourceList and Theme.accent or Theme.border
    if panel.actor:getJoypadBind()~=-1 then setJoypadFocus(panel.actor:getIndex(),list) end
end
function Input.other(panel,list)
    Input.focus(panel,list==panel.itemList and panel.sourceList or panel.itemList)
end
function Input.activate(panel,list)
    if list==panel.itemList then Input.focus(panel,panel.sourceList) else panel:locateSource() end
end
function Input.key(panel,key,list)
    if key==Keyboard.KEY_LEFT then panel:previous()
    elseif key==Keyboard.KEY_RIGHT then panel:nextPage()
    elseif key==Keyboard.KEY_TAB then Input.other(panel,list)
    elseif key==Keyboard.KEY_RETURN then Input.activate(panel,list) end
end
return Input
