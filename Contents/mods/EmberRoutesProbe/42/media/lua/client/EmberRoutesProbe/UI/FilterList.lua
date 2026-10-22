local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
require "ISUI/ISScrollingListBox"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Editor=require "EmberRoutesProbe/FilterEditor"
local Flow=require "EmberRoutesProbe/UI/Text"
local Rows={}
local function text(key) return getText("IGUI_EmberRoutesProbe_Filter_"..key) end
---@param owner EmberRoutesStorageFilterPanel
---@param bounds {x:number,y:number,width:number,height:number}
---@return EmberRoutesFilterList
function Rows.create(owner,bounds)
    ---@type EmberRoutesFilterList
    local list=ISScrollingListBox:new(bounds.x,bounds.y,bounds.width,bounds.height)
    list:initialise() Tooltip.attach(list,"updateTooltip")
    list.itemheight=owner.rowHeight
    list.font=UIFont.Small
    list:setWantKeyEvents(true)
    list.owner=owner
    list.doDrawItem=Rows.draw

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
        nativePre(self)
        clampScroll(self)
    end

    return list
end
---@param list EmberRoutesFilterList
function Rows.draw(list,y,entry)
        local row=entry.item
        if not row then return y+(entry.height or list.itemheight) end
        local pad=list.owner.pad
        local height=entry.height or list.itemheight
        local visibleY=y+list:getYScroll()
        if visibleY+height<0 or visibleY>=list.height then return y+height end
        if list.selected==entry.index then list:drawRect(0,y,list.width,height,0.35,0.24,0.43,0.53)
        elseif list.mouseoverselected==entry.index then list:drawRect(0,y,list.width,height,0.15,0.7,0.8,0.9) end
        if row.root then
            list:drawRect(0,y,list.width,1,0.7,0.3,0.36,0.4)
            local c=row.color
            list:drawRect(0,y,3,height,0.9,c[1],c[2],c[3])
        end
        local x,box=row.indent,list.owner.fontHeight
        local cy=y+pad/2
        list:drawRectBorder(x,cy,box,box,0.9,0.7,0.76,0.8)
        if row.mark=="[x]" then
            if list.owner.tickTexture then
                list:drawTextureScaledAspect(list.owner.tickTexture,x+2,cy+2,box-4,box-4,1,0.6,0.85,0.65)
            else list:drawRect(x+3,cy+3,box-6,box-6,1,0.6,0.85,0.65) end
        elseif row.mark=="[-]" then
            local inset=math.floor(box*0.25)
            list:drawRect(x+inset,cy+inset,box-inset*2,box-inset*2,1,0.45,0.72,0.88)
        elseif row.mark=="[~]" then
            list:drawRect(x+3,cy+box/2-2,box-6,2,1,0.95,0.8,0.3)
            list:drawRect(x+3,cy+box/2+1,box-6,2,1,0.95,0.8,0.3)


        end
        for index,line in ipairs(row.lines) do
            list:drawText(line,x+box+pad,cy+(index-1)*list.owner.fontHeight,0.92,0.93,0.9,1,UIFont.Small)
        end
        if row.stateCaption then
            list:drawText(row.stateCaption,x+box+pad,cy+#row.lines*list.owner.fontHeight,0.6,0.72,0.8,1,UIFont.Small)
        end
        return y+height
    end
---@param self EmberRoutesStorageFilterPanel
function Rows.refresh(self)
    local selected=self.list.selected
    Tooltip.clear(self.list)
    self.list:clear()
    for _,row in ipairs(Editor.rows(self.model)) do
        local label=row.kind=="group" and text(row.id) or text(row.label or row.kind)
        if row.kind=="type" then
            local resolveName=_G.getItemNameFromFullType
            label=type(resolveName)=="function" and resolveName(row.id) or row.id
            if not label or label=="" then label=row.id end
        end
        row.caption=label
        row.mark=Editor.mark(self.model,row)
        row.root=row.kind=="group" and row.depth==0
        row.color=row.root and Filter.nodes[row.id].color or nil
        row.indent=self.pad+math.min(row.depth or 0,4)*self.pad*2
        row.lines=Flow.wrap(label,self.list.width-row.indent-self.fontHeight-self.pad*3-16,UIFont.Small)
        if #row.lines>2 then row.lines={row.lines[1],row.lines[2].."…"} end
        if row.kind=="type" then
            row.stateCaption=text(row.mark=="[~]" and "inherit" or (row.mark=="[x]" and "allow" or "deny"))
        elseif row.mark=="[-]" then row.stateCaption=text("partial")
        else row.stateCaption=nil end
        self.list.itemheight=self.pad+self.fontHeight*math.max(1,#row.lines+(row.stateCaption and 1 or 0))
        self.list:addItem(label,row,row.kind=="type" and (label.."\n"..row.id) or label)
    end
    self.list.itemheight=self.rowHeight
    self.list.selected=math.max(1,math.min(selected or 1,#self.list.items))
end
return Rows
