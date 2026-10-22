local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
require "ISUI/ISScrollingListBox"
local Text=require "EmberRoutesProbe/UI/Text"
local Metrics=require "EmberRoutesProbe/WarehouseMetrics"
local Cached={}
---@class EmberRoutesCachedList:ISScrollingListBox
---@field emberPad number
---@field emberFontHeight number
---@field emberStyle table?
---@field emberEmptyLines string[]?
---@field emberEmptyLabel string?
---@field emberColumns table?
---@field emberNames table?
---@field emberMetric string?
---@param list EmberRoutesCachedList
function Cached.draw(list,y,entry)
    if list.emberStyle then return list.emberStyle.draw(list,y,entry) end
    local h=entry.height or list.itemheight
    local visible=y+list:getYScroll()
    if visible+h<0 or visible>=list.height then return y+h end
    if list.selected==entry.index then list:drawRect(0,y,list.width,h,0.35,0.24,0.43,0.53) end
    for index,line in ipairs(entry.item.lines) do
        list:drawText(line,list.emberPad,y+list.emberPad/2+(index-1)*list.emberFontHeight,0.92,0.91,0.84,1,UIFont.Small)
    end
    return y+h
end
function Cached.create(owner,bounds,select,style)
    ---@type EmberRoutesCachedList
    local list=ISScrollingListBox:new(bounds.x,bounds.y,bounds.width,bounds.height)
    list:initialise() Tooltip.attach(list,"updateTooltip") list.font=UIFont.Small
    list.emberPad,list.emberFontHeight=owner.pad,owner.fontHeight
    list.emberStyle=style

    local function clampScroll(self)
        local total=(self.getScrollHeight and self:getScrollHeight()) or (self.items and #self.items*(self.itemheight or 0)) or 0
        local height=self.height or 0
        local maxScroll=math.max(0,total-height)
        if maxScroll<=0 then
            if self.getYScroll and self:getYScroll()~=0 and self.setYScroll then self:setYScroll(0) end
            self.smoothScrollTargetY=nil
            self.smoothScrollY=nil
            return 0
        end
        local cur=self.getYScroll and self:getYScroll() or 0
        local clamped=math.max(-maxScroll,math.min(0,cur))
        if cur~=clamped and self.setYScroll then self:setYScroll(clamped) end
        if self.smoothScrollTargetY then
            self.smoothScrollTargetY=math.max(-maxScroll,math.min(0,self.smoothScrollTargetY))
        end
        return maxScroll
    end

    local nativeWheel=list.onMouseWheel
    list.onMouseWheel=function(self,del)
        local maxScroll=math.max(0,self:getScrollHeight()-self.height)
        if maxScroll<=0 then
            self:setYScroll(0)
            self.smoothScrollTargetY=nil
            self.smoothScrollY=nil
            return true
        end
        local res=nativeWheel(self,del)
        clampScroll(self)
        return res
    end

    local nativeSmooth=list.updateSmoothScrolling
    list.updateSmoothScrolling=function(self)
        local maxScroll=clampScroll(self)
        if maxScroll<=0 then return end
        nativeSmooth(self)
        clampScroll(self)
    end

    local nativePre=list.prerender
    list.prerender=function(self)
        clampScroll(self)
        local key=self.emberMetric or "ui.list"
        local measured=Metrics.begin(key)
        nativePre(self)
        Metrics.finish(key,measured)
        clampScroll(self)
    end

    if style then
        local native=list.render
        list.render=function(self)
            if native then native(self) end
            if #self.items==0 then
                local c=self.emberStyle.emptyColor
                for i,line in ipairs(self.emberEmptyLines or {}) do
                    self:drawText(line,self.emberPad,self.emberPad+(i-1)*self.emberFontHeight,c.r,c.g,c.b,c.a,UIFont.Small)
                end
            end
        end
    end
    list.itemheight=owner.fontHeight+owner.pad list.doDrawItem=Cached.draw
    if select then
        local clicked=function(target,row)
            if target.focusList then target:focusList(list) end
            if row then select(target,row.value) end
        end
        list:setOnMouseDownFunction(owner,clicked) list:setOverrideAButtonFunction(owner,clicked)
    end
    list:setWantKeyEvents(true)
    local function move(direction)
        list.selected=math.max(1,math.min(#list.items,list.selected+direction)) list:ensureVisible(list.selected)
        if select and list.items[list.selected] then select(owner,list.items[list.selected].item.value) end
    end
    list.onKeyPress=function(_,key)
        if owner.isListFocused and not owner:isListFocused(list) then return end
        if key==Keyboard.KEY_UP then move(-1)
        elseif key==Keyboard.KEY_DOWN then move(1)
        elseif key==Keyboard.KEY_ESCAPE then owner:close()
        elseif owner.onListKey then owner:onListKey(key,list) end
    end
    list.isKeyConsumed=function(_,key)
        if owner.isListFocused and not owner:isListFocused(list) then return false end
        return key==Keyboard.KEY_UP or key==Keyboard.KEY_DOWN or key==Keyboard.KEY_ESCAPE
            or (owner.onListKey and (key==Keyboard.KEY_LEFT or key==Keyboard.KEY_RIGHT
            or key==Keyboard.KEY_TAB or key==Keyboard.KEY_RETURN))
    end
    list.onJoypadDirUp=function() move(-1) end list.onJoypadDirDown=function() move(1) end
    list.onJoypadDown=function(_,button)
        if button==Joypad.BButton then owner:close()
        elseif button==Joypad.AButton and owner.onListActivate then owner:onListActivate(list)
        elseif owner.onListJoypad then owner:onListJoypad(button) end
    end
    if owner.onListFocus then
        list.onJoypadDirLeft=function() owner:onListFocus(list,-1) end
        list.onJoypadDirRight=function() owner:onListFocus(list,1) end
    end
    return list
end
function Cached.fill(list,rows,caption)
    Tooltip.clear(list)
    list:clear()
    for _,value in ipairs(rows) do
        local label=caption(value)
        local lines=Text.wrap(label,list.width-list.emberPad*3-16,UIFont.Small)
        if #lines>3 then lines={lines[1],lines[2],lines[3].."..."} end
        list.itemheight=list.emberPad+list.emberFontHeight*math.max(1,#lines)
        list:addItem(label,{value=value,lines=lines},label)
    end
    list.selected=#rows>0 and 1 or 0
end
-- Reuse native entries by stable key; count-only changes do not clear/reflow the list.
---@param list EmberRoutesCachedList
function Cached.reconcile(list,rows,caption,key,preserveAnchor)
    local old=list.items
    local selected=old[list.selected or 0]
    local selectedKey=selected and key(selected.item.value)
    local oldTop=0
    for i,entry in ipairs(old) do if i==(list.selected or 0) then break end oldTop=oldTop+entry.height end
    local entries={}
    for _,entry in ipairs(old) do entries[key(entry.item.value)]=entry end
    local updated,total,selectedIndex,newTop={},0,nil,0
    local structural=#old~=#rows
    local heightChanged=false
    for i,value in ipairs(rows) do
        local id=key(value)
        local entry=entries[id]
        local label
        if not entry or entry.item.value~=value then label=caption(value) end
        if not entry or (label and entry.text~=label) then
            local visual
            if list.emberStyle then visual=list.emberStyle.prepare(list,value,label)
            else
                local lines=Text.wrap(label,list.width-list.emberPad*3-16,UIFont.Small)
                if #lines>3 then lines={lines[1],lines[2],lines[3].."..."} end
                visual={lines=lines,height=list.emberPad+list.emberFontHeight*math.max(1,#lines)}
            end
            if not entry then
                list.itemheight=visual.height
                entry=list:addItem(label,{value=value,lines=visual.lines,visual=visual},label)
            else
                heightChanged=heightChanged or entry.height~=visual.height
                entry.text=label entry.tooltip=label entry.item.lines=visual.lines entry.item.visual=visual entry.height=visual.height
            end
            if list.mouseoverselected==i and list.tooltipUI then list.tooltipUI.description=label end
        end
        entry.item.value=value
        if old[i]~=entry then structural=true end
        entry.itemindex=i entry.index=i updated[i]=entry
        if id==selectedKey then selectedIndex=i newTop=total end
        total=total+entry.height
    end
    if structural then
        Tooltip.clear(list)
        list.items=updated list.count=#updated list.itemheightoverride={}
    end
    list.selected=selectedIndex or (#rows>0 and math.max(1,math.min(list.selected or 1,#rows)) or 0)
    if structural or heightChanged then
        local scroll=list:getYScroll()
        if preserveAnchor and selectedIndex then scroll=scroll+oldTop-newTop end
        list:setScrollHeight(total)
        local clamped=math.max(math.min(0,scroll),math.min(0,list.height-total))
        list:setYScroll(clamped)
        if list.smoothScrollY then list.smoothScrollY=clamped end
        if list.smoothScrollTargetY then list.smoothScrollTargetY=clamped end
    end
    local current=list.items[list.selected]
    return current and current.item.value or false
end
return Cached
