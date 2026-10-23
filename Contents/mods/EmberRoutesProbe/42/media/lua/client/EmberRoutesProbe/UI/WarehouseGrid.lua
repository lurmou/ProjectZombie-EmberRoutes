require "ISUI/ISPanel"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"

---@class EmberRoutesWarehouseGrid:ISPanel
---@field owner EmberRoutesWarehousePage
---@field presentation table
---@field cells table[]
---@field rows table[]
---@field columns integer
---@field selected integer
---@field scrollY number
---@field maxScrollY number
---@field emptyLabel string?
local Grid=ISPanel:derive("EmberRoutesWarehouseGrid")

local function formatCount(count)
    if not count then return "0" end
    if count>=1000000 then return string.format("%.1fM",count/1000000)
    elseif count>=10000 then return string.format("%.1fk",count/1000)
    else return tostring(count) end
end

---@param owner EmberRoutesWarehousePage
---@param bounds {x:number,y:number,width:number,height:number}
---@param select function
---@param presentation table?
---@return EmberRoutesWarehouseGrid
function Grid.new(owner,bounds,select,presentation)
    local o=ISPanel.new(Grid,bounds.x,bounds.y,bounds.width,bounds.height)
    o.owner=owner
    o.select=select
    o.presentation=presentation or Presentation.new()
    o.cells={}
    o.rows={}
    o.columns=1
    o.selected=1
    o.scrollY=0
    o.maxScrollY=0
    o.background=false
    o.fontHeight=owner.fontHeight
    o.pad=owner.pad
    o:initialise()
    o:setWantKeyEvents(true)
    return o
end

function Grid:setRows(rows,selection)
    self.rows=rows or {}
    self.cells={}
    self.selected=1
    local h,p=self.fontHeight,self.pad
    local slotSize=math.max(38,math.floor(h*2.3))
    local gap=4
    local availableW=self.width-p*2
    local cols=math.max(1,math.floor((availableW+gap)/(slotSize+gap)))
    self.columns=cols

    for i,row in ipairs(self.rows) do
        local col=(i-1)%cols
        local rowIdx=math.floor((i-1)/cols)
        local cellX=p+col*(slotSize+gap)
        local cellY=p+rowIdx*(slotSize+gap)
        local icon=self.presentation:icon(row.fullType)
        local cell={
            index=i,
            row=row,
            x=cellX,
            y=cellY,
            width=slotSize,
            height=slotSize,
            icon=icon,
            fullType=row.fullType
        }
        self.cells[i]=cell
        if selection and row.fullType==selection.fullType then
            self.selected=i
        end
    end

    local totalRows=math.ceil(#self.rows/cols)
    local totalH=p*2+totalRows*(slotSize+gap)
    self.maxScrollY=math.max(0,totalH-self.height)
    self.scrollY=math.max(0,math.min(self.scrollY,self.maxScrollY))
end

function Grid:cellAt(x,y)
    local myScroll=self.scrollY or 0
    for _,cell in ipairs(self.cells) do
        local drawY=cell.y-myScroll
        if x>=cell.x and x<cell.x+cell.width and y>=drawY and y<drawY+cell.height then
            return cell
        end
    end
    return nil
end

function Grid:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad
    local myScroll=self.scrollY or 0
    local mx=self:getMouseX()
    local my=self:getMouseY()
    self.hoveredCell=nil

    -- Background frame
    Theme.rect(self,0,0,self.width,self.height,Theme.panel)
    Theme.rect(self,0,0,self.width,self.height,Theme.border,true)

    if #self.cells==0 then
        local empty=self.emptyLabel or getText("IGUI_EmberRoutesProbe_Settlement_noItems")
        Theme.text(self,empty,p+4,p+4,Theme.muted)
        return
    end

    local selFullType=self.owner.store.value.selection and self.owner.store.value.selection.fullType or nil

    for i,cell in ipairs(self.cells) do
        local drawY=cell.y-myScroll
        if drawY+cell.height>=0 and drawY<=self.height then
            local isHover=mx and my and mx>=cell.x and mx<cell.x+cell.width and my>=drawY and my<drawY+cell.height
            local isSelected=(i==self.selected) or (selFullType and cell.row.fullType==selFullType)

            if isHover then self.hoveredCell=cell end

            -- Slot Frame (AE2 style sunken square slot)
            local slotBg=isSelected and Theme.selected or (isHover and Theme.hover or {r=0.08,g=0.09,b=0.11,a=0.90})
            local slotBorder=isSelected and Theme.gold or (isHover and Theme.accent or Theme.border)

            Theme.rect(self,cell.x,drawY,cell.width,cell.height,slotBg)
            Theme.rect(self,cell.x,drawY,cell.width,cell.height,slotBorder,true)

            if isSelected then
                Theme.rect(self,cell.x+1,drawY+1,cell.width-2,cell.height-2,Theme.gold,true)
            end

            -- Item Icon
            local iconPad=4
            local iconSize=cell.width-iconPad*2
            if cell.icon then
                self:drawTextureScaledAspect(cell.icon,cell.x+iconPad,drawY+iconPad,iconSize,iconSize,1,1,1,1)
            else
                Theme.text(self,"?",cell.x+cell.width/2-4,drawY+(cell.height-h)/2,Theme.muted)
            end

            -- Pinned star badge (top left)
            if cell.row.pinned then
                Theme.text(self,"★",cell.x+2,drawY-1,Theme.gold)
            end

            -- AE2 quantity count badge (bottom right)
            local countStr=cell.row.pending and "..." or formatCount(cell.row.count)
            local tw=getTextManager():MeasureStringX(UIFont.Small,countStr)
            local th=h
            local badgeX=cell.x+cell.width-tw-2
            local badgeY=drawY+cell.height-th+1

            Theme.rect(self,badgeX-2,badgeY-1,tw+4,th,{r=0,g=0,b=0,a=0.75})
            local countColor=cell.row.pending and Theme.muted or (isSelected and Theme.gold or Theme.textColor)
            Theme.text(self,countStr,badgeX,badgeY-1,countColor)
        end
    end

    -- Draw hover tooltip on top
    if self.hoveredCell and not self.owner.helpModal then
        local c=self.hoveredCell
        local drawY=c.y-myScroll
        local label=c.row.label or c.row.fullType or "?"
        local count=c.row.pending and "..." or tostring(c.row.count or 0)
        local sources=#(c.row.sources or {})
        local hint=getTextOrNull("IGUI_EmberRoutesProbe_Warehouse_slotHint") or "左键选择 · 双击委托制作"
        local tipLines={
            label,
            getText("IGUI_EmberRoutesProbe_Settlement_quantity")..": "..count.." ("..sources.." "..getText("IGUI_EmberRoutesProbe_Settlement_sources")..")",
            hint
        }
        local maxW=0
        for _,line in ipairs(tipLines) do
            maxW=math.max(maxW,getTextManager():MeasureStringX(UIFont.Small,line))
        end
        local tipW=maxW+p*2
        local tipH=#tipLines*h+p
        local tipX=math.max(p,math.min(self.width-tipW-p,c.x+c.width/2-tipW/2))
        local tipY=drawY-tipH-4
        if tipY<0 then tipY=drawY+c.height+4 end

        Theme.rect(self,tipX,tipY,tipW,tipH,{r=0.08,g=0.10,b=0.13,a=0.95})
        Theme.rect(self,tipX,tipY,tipW,tipH,Theme.border,true)
        Theme.text(self,tipLines[1],tipX+p,tipY+p/2,Theme.gold)
        Theme.text(self,tipLines[2],tipX+p,tipY+p/2+h,Theme.textColor)
        Theme.text(self,tipLines[3],tipX+p,tipY+p/2+h*2,Theme.muted)
    end
end

function Grid:onMouseDown(x,y)
    self.owner:focusList(self)
    local cell=self:cellAt(x,y)
    if cell then
        local now=getTimestampMs()
        local isDouble=self.lastClickCell==cell and (now-(self.lastClickTime or 0))<400
        self.lastClickCell=cell
        self.lastClickTime=now
        self.selected=cell.index
        if self.select then self.select(self.owner,cell.row) end
        if isDouble and self.owner.owner and self.owner.owner.openPublicOrder then
            self.owner.owner:openPublicOrder({productType=cell.row.fullType})
        end
        return true
    end
    return true
end

function Grid:onMouseWheel(del)
    self.scrollY=math.max(0,math.min(self.maxScrollY,self.scrollY+del*40))
    return true
end

function Grid:move(delta)
    if #self.cells==0 then return end
    self.selected=math.max(1,math.min(#self.cells,self.selected+delta))
    local cell=self.cells[self.selected]
    if cell then
        if self.select then self.select(self.owner,cell.row) end
        -- Auto scroll into view
        local myScroll=self.scrollY or 0
        if cell.y<myScroll then self.scrollY=cell.y
        elseif cell.y+cell.height>myScroll+self.height then
            self.scrollY=cell.y+cell.height-self.height
        end
    end
end

function Grid:onKeyPress(key)
    if not self.owner:isListFocused(self) then return end
    if key==Keyboard.KEY_UP then self:move(-self.columns)
    elseif key==Keyboard.KEY_DOWN then self:move(self.columns)
    elseif key==Keyboard.KEY_LEFT then self:move(-1)
    elseif key==Keyboard.KEY_RIGHT then self:move(1)
    elseif key==Keyboard.KEY_ESCAPE then self.owner:close()
    elseif self.owner.onListKey then self.owner:onListKey(key,self) end
end

function Grid:isKeyConsumed(key)
    if not self.owner:isListFocused(self) then return false end
    return key==Keyboard.KEY_UP or key==Keyboard.KEY_DOWN or key==Keyboard.KEY_LEFT
        or key==Keyboard.KEY_RIGHT or key==Keyboard.KEY_ESCAPE
        or (self.owner.onListKey and (key==Keyboard.KEY_TAB or key==Keyboard.KEY_RETURN))
end

function Grid:onJoypadDirUp() self:move(-self.columns) end
function Grid:onJoypadDirDown() self:move(self.columns) end
function Grid:onJoypadDirLeft() self:move(-1) end
function Grid:onJoypadDirRight() self:move(1) end
function Grid:onJoypadDown(button)
    if button==Joypad.BButton then self.owner:close()
    elseif button==Joypad.AButton and self.cells[self.selected] then
        if self.select then self.select(self.owner,self.cells[self.selected].row) end
    elseif button==Joypad.XButton and self.cells[self.selected] then
        if self.owner.owner and self.owner.owner.openPublicOrder then
            self.owner.owner:openPublicOrder({productType=self.cells[self.selected].row.fullType})
        end
    elseif self.owner.onListJoypad then self.owner:onListJoypad(button) end
end

return Grid
