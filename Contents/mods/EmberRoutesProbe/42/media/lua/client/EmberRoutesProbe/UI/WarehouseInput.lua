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
    if panel.cartDrawerOpen then panel:toggleCartDrawer(false) end
    local isItems=(list==panel.itemList or list==panel.itemGrid)
    local target=isItems and panel.sourceList or (panel.viewMode=="grid" and (panel.itemGrid or panel.itemList) or panel.itemList)
    Input.focus(panel,target)
end
function Input.activate(panel,list)
    if list==panel.itemList or list==panel.itemGrid then
        if panel.cartDrawerOpen then panel:toggleCartDrawer(false) end
        Input.focus(panel,panel.sourceList)
    else panel:locateSource() end
end
function Input.key(panel,key,list)
    if key==Keyboard.KEY_LEFT then panel:previous()
    elseif key==Keyboard.KEY_RIGHT then panel:nextPage()
    elseif key==Keyboard.KEY_TAB then Input.other(panel,list)
    elseif key==Keyboard.KEY_RETURN then Input.activate(panel,list) end
end
-- B42 extra button callbacks do not descend through nested ISUI panels.
-- Observe only the input edge; inventory reads stay in their own services.
function Input.delivery(panel)
    if type(isMouseButtonDown)~='function' then return end
    local down=isMouseButtonDown(2)
    local previous=panel.deliveryMiddleDown
    panel.deliveryMiddleDown=down
    if not down or previous or not panel.active or panel.disposed or not panel:isVisible() then return end
    if panel.helpModal or panel.owner.publicDialog or panel.owner.priorityDialog
        or panel.categories.expanded or panel.controls.sort.expanded then return end

    local shift=type(isShiftKeyDown)=='function' and isShiftKeyDown() or false

    -- 1. Check if mouse is hovering over right-side source warehouse list
    local sourceList=panel.sourceList
    if sourceList and sourceList.isMouseOver and sourceList:isMouseOver() and not (sourceList.isMouseOverScrollBar and sourceList:isMouseOverScrollBar()) then
        local x,y=sourceList:getMouseX(),sourceList:getMouseY()
        local index=sourceList:rowAt(x,y)
        local item=index and sourceList.items[index]
        local source=item and item.item and (item.item.value or item.item)
        if source and panel.details and panel.details.row then
            panel:selectSource(source)
            if panel.onMiddleClickSource then
                return panel:onMiddleClickSource(source,shift)
            end
        end
    end

    -- 2. Check if mouse is hovering over main item grid or item list
    local list=panel.viewMode=='grid' and panel.itemGrid or panel.itemList
    if not list or not list:isMouseOver() then return end
    if list.isMouseOverScrollBar and list:isMouseOverScrollBar() then return end
    local x,y=list:getMouseX(),list:getMouseY()
    local row
    if list==panel.itemGrid then
        local cell=list:cellAt(x,y) row=cell and cell.row
    else
        local index=list:rowAt(x,y)
        local item=index and list.items[index]
        row=item and item.item and (item.item.value or item.item)
    end
    if row then
        Input.focus(panel,list)
        panel:selectItem(row)
        return panel:onMiddleClickItem(row,shift)
    end
end
return Input
