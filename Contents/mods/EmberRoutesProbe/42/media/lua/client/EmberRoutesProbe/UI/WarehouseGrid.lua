require "ISUI/ISPanel"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"
local UICache=require "EmberRoutesProbe/UI/UICache"

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
---@field slotSize number
---@field gap number
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
    local self=Grid
    local o=ISPanel.new(self,bounds.x,bounds.y,bounds.width,bounds.height)
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
    o.slotSize=math.max(38,math.floor(owner.fontHeight*2.3))
    o.gap=4
    o.totalGridRows=0
    o:initialise()
    o.viewportBounds={x=1,y=1,width=0,height=0}
    o:setWantKeyEvents(true)
    return o
end

function Grid:setRows(rows,selection)
    self.rows=rows or {}
    self.cells={}
    self.selected=1
    local h,p=self.fontHeight,self.pad
    local slotSize=self.slotSize or math.max(38,math.floor(h*2.3))
    self.slotSize=slotSize
    local gap=self.gap or 4
    local scrollBarW=math.max(10,math.min(14,math.floor(h*0.75)))
    self.scrollBarW=scrollBarW
    local availableW=self.width-p*2-scrollBarW-4
    local cols=math.max(1,math.floor((availableW+gap)/(slotSize+gap)))
    self.columns=cols

    for i,row in ipairs(self.rows) do
        local col=(i-1)%cols
        local rowIdx=math.floor((i-1)/cols)
        local cellX=p+col*(slotSize+gap)
        local cellY=p+rowIdx*(slotSize+gap)
        local icon=self.presentation:icon(row.fullType)
        local countStr=row.pending and "..." or formatCount(row.count)
        local cell={
            index=i,
            row=row,
            x=cellX,
            y=cellY,
            width=slotSize,
            height=slotSize,
            icon=icon,
            countText=countStr,
            countWidth=UICache.measureCount(countStr),
            fullType=row.fullType
        }
        self.cells[i]=cell
        if selection and row.fullType==selection.fullType then
            self.selected=i
        end
    end

    self.totalGridRows=math.ceil(#self.rows/cols)
    local totalH=p*2+self.totalGridRows*(slotSize+gap)
    self.maxScrollY=math.max(0,totalH-self.height)
    self.scrollY=math.max(0,math.min(self.scrollY,self.maxScrollY))
end

function Grid:getScrollbarGeometry()
    local p=self.pad or 6
    local scrollBarW=self.scrollBarW or 12
    local trackX=self.width-p-scrollBarW
    local trackY=p
    local trackW=scrollBarW
    local trackH=math.max(10,self.height-p*2)
    local maxScroll=self.maxScrollY or 0
    local totalH=p*2+(self.totalGridRows or 0)*((self.slotSize or 38)+(self.gap or 4))

    local thumbH=trackH
    local thumbY=trackY
    if maxScroll>0 and totalH>0 then
        thumbH=math.max(22,math.floor((self.height/totalH)*trackH))
        local availableSpace=trackH-thumbH
        thumbY=trackY+math.floor((self.scrollY/maxScroll)*availableSpace)
    end
    return trackX,trackY,trackW,trackH,thumbY,thumbH,maxScroll>0
end

-- O(1) math coordinate hit test
function Grid:cellAt(x,y)
    local trackX=self.width-(self.pad or 6)-(self.scrollBarW or 12)
    if x>=trackX-3 then return nil end
    local myScroll=self.scrollY or 0
    local p=self.pad
    local gap=self.gap or 4
    local slotSize=self.slotSize or 38
    local stride=slotSize+gap

    local localY=y+myScroll-p
    local localX=x-p
    if localX<0 or localY<0 then return nil end

    local col=math.floor(localX/stride)
    local row=math.floor(localY/stride)
    if col<0 or col>=self.columns or row<0 or row>=self.totalGridRows then return nil end
    if (localX%stride)>slotSize or (localY%stride)>slotSize then return nil end

    local idx=row*self.columns+col+1
    return self.cells[idx]
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

    local totalCells=#self.cells
    if totalCells==0 then
        local empty=self.emptyLabel or getText("IGUI_EmberRoutesProbe_Settlement_noItems")
        Theme.text(self,empty,p+4,p+4,Theme.muted)
        return
    end

    local selFullType=self.owner.store.value.selection and self.owner.store.value.selection.fullType or nil

    -- O(1) Windowing / Virtual List range calculation
    local gap=self.gap or 4
    local slotSize=self.slotSize or 38
    local rowStride=slotSize+gap
    local startRow=math.max(0,math.floor(myScroll/rowStride))
    local endRow=math.min(self.totalGridRows-1,math.ceil((myScroll+self.height)/rowStride))

    local hoveredIdx=nil
    if mx and my and mx>=0 and mx<self.width and my>=0 and my<self.height then
        local hoverCell=self:cellAt(mx,my)
        if hoverCell then
            hoveredIdx=hoverCell.index
            self.hoveredCell=hoverCell
        end
    end

    -- STENCIL CLIPPING:
    -- Inset by 1px so cells can NEVER overwrite or bleed into the outer 1px frame border
    local vb=self.viewportBounds
    if vb and self.setStencilRect then
        vb.x=1
        vb.y=1
        vb.width=math.max(0,self.width-2)
        vb.height=math.max(0,self.height-2)
        self:setStencilRect(vb.x,vb.y,vb.width,vb.height)
    end

    -- Render ONLY cells in visible row range
    for r=startRow,endRow do
        local baseIdx=r*self.columns
        for c=0,self.columns-1 do
            local idx=baseIdx+c+1
            if idx>totalCells then break end
            local cell=self.cells[idx]
            local drawY=cell.y-myScroll

            local isHover=(idx==hoveredIdx)
            local isSelected=(idx==self.selected) or (selFullType and cell.row.fullType==selFullType)

            -- Slot Frame: Use singleton colors from UICache to eliminate frame GC allocations
            local slotBg=isSelected and Theme.selected or (isHover and Theme.hover or UICache.Colors.SLOT_DEFAULT_BG)
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

            -- AE2 Delivery Cart Badge (top right)
            local cartItem=self.owner.deliveryCart and self.owner.deliveryCart[cell.row.fullType]
            if cartItem and cartItem.count>0 then
                local badgeStr="+"..formatCount(cartItem.count)
                local bw=UICache.measureCount(badgeStr)+4
                local bh=h-2
                local bx=cell.x+cell.width-bw-1
                local by=drawY+1
                Theme.rect(self,bx,by,bw,bh,Theme.selected)
                Theme.rect(self,bx,by,bw,bh,Theme.accent,true)
                Theme.text(self,badgeStr,bx+2,by-1,Theme.accent)
            end

            -- Quantity count badge (bottom right)
            local countStr=cell.countText
            local tw=cell.countWidth
            local th=h
            local badgeX=cell.x+cell.width-tw-2
            local badgeY=drawY+cell.height-th+1

            Theme.rect(self,badgeX-2,badgeY-1,tw+4,th,UICache.Colors.BADGE_BG)
            local countColor=cell.row.pending and Theme.muted or (isSelected and Theme.gold or Theme.textColor)
            Theme.text(self,countStr,badgeX,badgeY-1,countColor)
        end
    end

    if vb and self.clearStencilRect then
        self:clearStencilRect()
        if self.doRepaintStencil and self.repaintStencilRect then
            self:repaintStencilRect(vb.x,vb.y,vb.width,vb.height)
        end
    end

    -- Render AE2 Vertical Scrollbar
    local trackX,trackY,trackW,trackH,thumbY,thumbH,canScroll=self:getScrollbarGeometry()
    Theme.rect(self,trackX,trackY,trackW,trackH,UICache.Colors.BADGE_BG)
    Theme.rect(self,trackX,trackY,trackW,trackH,Theme.border,true)

    if canScroll then
        local isHoverThumb=(mx>=trackX and mx<=trackX+trackW and my>=thumbY and my<=thumbY+thumbH)
        local isDragging=self.isDraggingThumb
        local thumbBg=isDragging and Theme.selected or (isHoverThumb and Theme.hover or UICache.Colors.SLOT_DEFAULT_BG)
        local thumbBorder=(isDragging or isHoverThumb) and Theme.accent or Theme.border

        Theme.rect(self,trackX+1,thumbY,trackW-2,thumbH,thumbBg)
        Theme.rect(self,trackX+1,thumbY,trackW-2,thumbH,thumbBorder,true)

        if thumbH>=16 then
            local gripY=thumbY+math.floor(thumbH/2)-2
            local gripColor=(isDragging or isHoverThumb) and Theme.accent or Theme.muted
            for g=-2,2,2 do
                Theme.rect(self,trackX+3,gripY+g,trackW-6,1,gripColor)
            end
        end
    end
end

function Grid:drawHoverTooltip()
    if not self.hoveredCell or (self.owner and self.owner.helpModal) then
        self.cachedTipKey=nil
        return
    end

    local c=self.hoveredCell
    if not c or not c.row then return end

    local h,p=self.fontHeight,self.pad
    local myScroll=self.scrollY or 0
    local drawY=c.y-myScroll
    local label=c.row.label or c.row.fullType or "?"
    local count=c.row.pending and "..." or tostring(c.row.count or 0)
    local sources=#(c.row.sources or {})
    local cartItem=self.owner.deliveryCart and self.owner.deliveryCart[c.row.fullType]
    local inCartCount=cartItem and cartItem.count or 0
    local hint=getTextOrNull("IGUI_EmberRoutesProbe_Warehouse_slotHint") or "IGUI_EmberRoutesProbe_Warehouse_slotHint"

    -- Cached tooltip layout to prevent per-frame string wrapping
    local tipKey=tostring(c.row.fullType)..":"..count..":"..tostring(sources)..":"..tostring(inCartCount)
    if self.cachedTipKey~=tipKey then
        self.cachedTipKey=tipKey
        local qtyLine=getText("IGUI_EmberRoutesProbe_Settlement_quantity")..": "..count.." ("..sources.." "..getText("IGUI_EmberRoutesProbe_Settlement_sources")..")"
        if inCartCount>0 then
            qtyLine=qtyLine.."  ·  "..getText("IGUI_EmberRoutesProbe_Settlement_cartTitle")..": +"..tostring(inCartCount)
        end
        local tipLines={
            label,
            qtyLine,
            hint
        }
        local maxW=0
        for _,line in ipairs(tipLines) do
            maxW=math.max(maxW,UICache.measureText(UIFont.Small,line))
        end
        local tipW=math.min(self.width-p*2,maxW+p*2)
        for i,line in ipairs(tipLines) do
            tipLines[i]=require("EmberRoutesProbe/UI/Text").wrapLimited(line,math.max(1,tipW-p*2),UIFont.Small,1)[1] or ""
        end
        self.cachedTipLines=tipLines
        self.cachedTipW=tipW
        self.cachedTipH=#tipLines*h+p
    end

    local tipW=self.cachedTipW or (self.width/2)
    local tipH=self.cachedTipH or (h*3+p)
    local tipX=math.max(p,math.min(self.width-tipW-p,c.x+c.width/2-tipW/2))
    local tipY=drawY-tipH-4
    if tipY<0 then tipY=drawY+c.height+4 end
    tipY=math.max(0,math.min(self.height-tipH,tipY))

    Theme.rect(self,tipX,tipY,tipW,tipH,UICache.Colors.TOOLTIP_BG)
    Theme.rect(self,tipX,tipY,tipW,tipH,Theme.border,true)
    if self.cachedTipLines then
        for lineIdx,line in ipairs(self.cachedTipLines) do
            local color=(lineIdx==1) and Theme.gold or ((lineIdx==2) and Theme.textColor or Theme.muted)
            Theme.text(self,line,tipX+p,tipY+p/2+(lineIdx-1)*h,color)
        end
    end
end

function Grid:render()
    ISPanel.render(self)

    -- 1. Outer frame border always drawn in render pass on top of all scrolled cells/scrollbar
    Theme.rect(self,0,0,self.width,self.height,Theme.border,true)

    -- 2. Draw hover tooltip on the topmost layer above the border
    self:drawHoverTooltip()
end

function Grid:onMouseDoubleClick(x,y)
    local cell=self:cellAt(x,y)
    if cell and cell.row and cell.row.fullType then
        self.selected=cell.index
        if self.select then self.select(self.owner,cell.row) end
        if self.owner and self.owner.owner and self.owner.owner.openPublicOrder then
            self.owner.owner:openPublicOrder({productType=cell.row.fullType})
            return true
        end
    end
    return false
end

function Grid:onMouseDown(x,y)
    self.owner:focusList(self)
    local trackX,trackY,trackW,trackH,thumbY,thumbH,canScroll=self:getScrollbarGeometry()
    if canScroll and x>=trackX-3 and x<=trackX+trackW+3 and y>=trackY and y<=trackY+trackH then
        if y>=thumbY and y<=thumbY+thumbH then
            self.isDraggingThumb=true
            self.dragClickOffsetY=y-thumbY
            return true
        elseif y<thumbY then
            self.scrollY=math.max(0,self.scrollY-self.height)
            return true
        else
            self.scrollY=math.min(self.maxScrollY,self.scrollY+self.height)
            return true
        end
    end
    local cell=self:cellAt(x,y)
    if cell then
        self.selected=cell.index
        if self.select then self.select(self.owner,cell.row) end
        return true
    end
    return true
end

function Grid:onMouseMove(dx,dy)
    if self.isDraggingThumb and (self.maxScrollY or 0)>0 then
        local trackX,trackY,trackW,trackH,_,thumbH=self:getScrollbarGeometry()
        local availableSpace=trackH-thumbH
        if availableSpace>0 then
            local my=self:getMouseY()
            local targetThumbY=my-(self.dragClickOffsetY or (thumbH/2))
            local ratio=math.max(0,math.min(1,(targetThumbY-trackY)/availableSpace))
            self.scrollY=math.floor(ratio*self.maxScrollY)
        end
        return true
    end
    return false
end

function Grid:onMouseUp(x,y)
    if self.isDraggingThumb then
        self.isDraggingThumb=false
        self.dragClickOffsetY=nil
        return true
    end
    return false
end

function Grid:onMouseUpOutside(x,y)
    if self.isDraggingThumb then
        self.isDraggingThumb=false
        self.dragClickOffsetY=nil
        return true
    end
    return false
end

function Grid:onRightMouseDown(x,y)
    self.owner:focusList(self)
    local cell=self:cellAt(x,y)
    if cell and cell.row then
        self.selected=cell.index
        if self.select then self.select(self.owner,cell.row) end
        if self.owner and self.owner.openItemContextMenu then
            self.owner:openItemContextMenu(cell.row,self:getAbsoluteX()+x,self:getAbsoluteY()+y)
        end
        return true
    end
    return false
end

function Grid:onMouseWheel(del)
    local stride=(self.slotSize or 38)+(self.gap or 4)
    self.scrollY=math.max(0,math.min(self.maxScrollY,self.scrollY+del*stride))
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
