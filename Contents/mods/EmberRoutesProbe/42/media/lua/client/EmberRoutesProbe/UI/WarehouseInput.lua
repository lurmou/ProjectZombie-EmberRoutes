local Theme=require "EmberRoutesProbe/UI/Theme"
local Input={}
function Input.active(panel,list)
    local isTarget=(panel.focusedList==list or ((list==panel.itemList or list==panel.itemGrid) and (panel.focusedList==panel.itemList or panel.focusedList==panel.itemGrid)))
    return isTarget and not panel.helpModal and not panel.search:isFocused()
        and not panel.categories.expanded and not panel.controls.sort.expanded
end
function Input.focus(panel,list)
    if not list then return end
    panel.focusedList=list
    local isItems=(list==panel.itemList or list==panel.itemGrid)
    panel.itemList.borderColor=isItems and Theme.accent or Theme.border
    if panel.itemGrid then
        panel.itemGrid.borderColor=isItems and Theme.accent or Theme.border
    end
    panel.sourceList.borderColor=list==panel.sourceList and Theme.accent or Theme.border
    if panel.actor:getJoypadBind()~=-1 then setJoypadFocus(panel.actor:getIndex(),list) end
end
function Input.other(panel,list)
    local isItems=(list==panel.itemList or list==panel.itemGrid)
    local target=isItems and panel.sourceList or (panel.viewMode=="grid" and (panel.itemGrid or panel.itemList) or panel.itemList)
    Input.focus(panel,target)
end
function Input.activate(panel,list)
    if list==panel.itemList or list==panel.itemGrid then Input.focus(panel,panel.sourceList) else panel:locateSource() end
end
function Input.key(panel,key,list)
    if key==Keyboard.KEY_LEFT then panel:previous()
    elseif key==Keyboard.KEY_RIGHT then panel:nextPage()
    elseif key==Keyboard.KEY_TAB then Input.other(panel,list)
    elseif key==Keyboard.KEY_RETURN then Input.activate(panel,list) end
end
return Input
