-- In-page delivery review panel. No inventory mutation or order authority.
require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISButton'
require 'ISUI/ISScrollingListBox'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local Text=require 'EmberRoutesProbe/UI/Text'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'

---@class EmberRoutesDeliveryCartDrawer:ISCollapsableWindow
local Drawer=ISCollapsableWindow:derive('EmberRoutesDeliveryCartDrawer')
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Warehouse_'..key,...) end
local function inside(r,x,y) return x>=r.x and x<r.x+r.width and y>=r.y and y<r.y+r.height end

-- One source for row drawing and input, in list-local coordinates.
function Drawer.rowLayout(width,h,p,count)
    local button=math.max(22,math.ceil(h*1.35))
    local gap=math.max(3,math.floor(p/2))
    local icon=math.floor(h*1.7)
    local height=math.ceil(h*2.8)
    local nameX=p+icon+gap
    local countW=math.max(h*2,getTextManager():MeasureStringX(UIFont.Small,tostring(count))+gap*2)
    local minus={x=nameX,y=height-button-gap,width=button,height=button}
    local value={x=minus.x+button+gap,y=minus.y,width=countW,height=button}
    local plus={x=value.x+value.width+gap,y=minus.y,width=button,height=button}
    local remove={x=width-p-button,y=gap,width=button,height=button}
    return {height=height,icon={x=p,y=gap,width=icon,height=icon},
        name={x=nameX,y=gap,width=math.max(1,remove.x-gap-nameX),height=h},
        minus=minus,value=value,plus=plus,remove=remove,
        weight={x=plus.x+button+gap,y=minus.y+(button-h)/2,width=math.max(0,width-p-plus.x-button-gap),height=h}}
end

function Drawer:new(owner,x,y,width,height)
    local o=ISCollapsableWindow.new(self,x,y,width,height)
    o.owner,o.fontHeight,o.pad=owner,owner.fontHeight,owner.pad
    o.title=text('cartTitle')
    o.resizable=false
    o.background=true
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border
    o:initialise()
    return o
end

function Drawer:initialise()
    ISCollapsableWindow.initialise(self)
end

function Drawer:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local th=self:titleBarHeight()
    local buttonH=math.ceil(h*1.55)
    local blocks=assert(Layout.axis({x=0,y=th,width=self.width,height=self.height-th},
        {{basis=h*2+p/2},{grow=1},{basis=h*4+p},{basis=buttonH}},
        {direction='column',padding=p,gap=p/2}))
    self.header,self.summary=blocks[1],blocks[3]



    local b=blocks[2]
    self.list=ISScrollingListBox:new(b.x,b.y,b.width,b.height)
    self.list:initialise() self.list.font=UIFont.Small
    self.list.itemheight=math.ceil(h*2.8)
    self.list.backgroundColor=Theme.panel self.list.borderColor=Theme.border self.list.drawBorder=true
    self.list.doDrawItem=function(list,y,item,alt) return self:drawItemRow(list,y,item,alt) end
    self.list.onMouseDown=function(list,x,y)
        local index=list:rowAt(x,y)
        local entry=index and list.items[index]
        local row=entry and entry.item
        if not row then return true end
        local scroll=list.getYScroll and list:getYScroll() or 0
        local rowY=(index-1)*list.itemheight+scroll
        local localY=y-rowY
        list.selected=index
        local r=row.layout
        local shift=type(isShiftKeyDown)=='function' and isShiftKeyDown() or false
        local delta=shift and math.max(1,row.step or 5) or 1
        if inside(r.minus,x,localY) then
            self.owner:addToDeliveryCart(row,-delta,row.source)
        elseif inside(r.plus,x,localY) then
            self.owner:addToDeliveryCart({fullType=row.fullType,label=row.label,count=row.maxCount},delta,row.source)
        elseif inside(r.remove,x,localY) then
            self.owner:removeFromDeliveryCart(row.cartKey or row.fullType)
        end
        return true
    end
    local nativeMove=self.list.onMouseMove
    self.list.onMouseMove=function(list,dx,dy)
        if nativeMove then nativeMove(list,dx,dy) end
        local i=list:rowAt(list:getMouseX(),list:getMouseY())
        local row=i and list.items[i] and list.items[i].item
        list.tooltip=row and row.label or nil
        return true
    end
    local nativePrerender=self.list.prerender
    self.list.prerender=function(list)
        if nativePrerender then nativePrerender(list) end
        if self.isEmpty then
            local start=math.max(p,(list.height-#self.emptyLines*h)/2)
            for i,line in ipairs(self.emptyLines) do Theme.text(list,line,p,start+(i-1)*h,Theme.muted) end
        end
    end
    Tooltip.attach(self.list,'prerender') self:addChild(self.list)

    local buttons=assert(Layout.axis(blocks[4],{{grow=1},{grow=2}},{gap=p/2}))
    local a=buttons[1]
    self.clearBtn=ISButton:new(a.x,a.y,a.width,a.height,text('clearCart'),self,function() self.owner:clearDeliveryCart() end)
    self.clearBtn:initialise() Theme.button(self.clearBtn) self:addChild(self.clearBtn)
    a=buttons[2]
    self.callBtn=ISButton:new(a.x,a.y,a.width,a.height,text('callDelivery'),self,function() self.owner:dispatchDeliveryCart() end)
    self.callBtn:initialise() Theme.button(self.callBtn,true) self:addChild(self.callBtn)
    self:refresh()
end

function Drawer:refresh()
    if not self.list then return end
    local list,h,p=self.list,self.fontHeight,self.pad
    local scroll=list.getYScroll and list:getYScroll() or 0
    local selected=list.items[list.selected or 0]
    local selectedKey=selected and selected.item and (selected.item.cartKey or selected.item.fullType)
    local ordered={}
    for _,item in pairs(self.owner.deliveryCart or {}) do ordered[#ordered+1]=item end
    table.sort(ordered,function(a,b) return tostring(a.label or a.fullType)<tostring(b.label or b.fullType) end)
    list:clear()
    local rowWidth=list.width-math.max(14,math.ceil(h*0.8))
    for i,item in ipairs(ordered) do
        local row={} for key,value in pairs(item) do row[key]=value end
        row.layout=Drawer.rowLayout(rowWidth,h,p,row.count)
        local displayName=row.label or row.fullType
        if row.sourceLabel and row.sourceLabel~='' then
            displayName=displayName..' ['..row.sourceLabel..']'
        end
        row.name=Text.wrapLimited(displayName,row.layout.name.width,UIFont.Small,1)[1]
        row.weightLabel=Text.wrapLimited(string.format('%.1f kg',(row.weight or 0)*row.count),row.layout.weight.width,UIFont.Small,1)[1]
        list:addItem(displayName,row)
        if (row.cartKey or row.fullType)==selectedKey then list.selected=i end
    end
    local extent=#ordered*list.itemheight
    if list.setScrollHeight then list:setScrollHeight(extent) end
    if list.setYScroll then list:setYScroll(math.max(math.min(0,scroll),math.min(0,list.height-extent))) end
    list.smoothScrollTargetY=nil list.smoothScrollY=nil
    self.isEmpty=#ordered==0
    self.countLabel=text('cartCountSummary',tostring(#ordered),tostring(self.owner.deliveryCartTotalUnits or 0))
    self.weightLabel=text('cartWeightSummary',string.format('%.1f',self.owner.deliveryCartWeight or 0))
    local actor=self.owner.actor
    local weight=actor and actor.getInventoryWeight and actor:getInventoryWeight()
        or actor and actor:getInventory():getCapacityWeight() or 0
    local free=math.max(0,(actor and actor:getMaxWeight() or 0)-weight)
    self.spaceLabel=text('cartSpaceSummary',string.format('%.1f',free))
    self.overCapacity=(self.owner.deliveryCartWeight or 0)>free
    local message=self.owner.deliveryFeedback
    if self.overCapacity and not self.owner.deliveryFeedbackError then message=text('cartCapacityWaitHint') end
    self.messageColor=self.owner.deliveryFeedbackError and Theme.status.ERROR or self.overCapacity and Theme.gold or Theme.muted
    self.messageLines=Text.wrapLimited(message or text('cartReviewHint'),self.summary.width,UIFont.Small,2)
    self.emptyLines=Text.wrapLimited(text('cartEmptyHint'),list.width-p*2,UIFont.Small,3)
    Theme.enable(self.callBtn,not self.isEmpty) Theme.enable(self.clearBtn,not self.isEmpty)
end

local function button(list,r,y,label,color,h)
    Theme.rect(list,r.x,y+r.y,r.width,r.height,Theme.control)
    Theme.rect(list,r.x,y+r.y,r.width,r.height,Theme.border,true)
    list:drawTextCentre(label,r.x+r.width/2,y+r.y+(r.height-h)/2,color.r,color.g,color.b,1,UIFont.Small)
end

function Drawer:drawItemRow(list,y,entry,alt)
    local row=entry.item if not row then return y+list.itemheight end
    local r=row.layout local h=self.fontHeight
    if list.selected==entry.index then Theme.rect(list,0,y,list.width,list.itemheight,Theme.selected)
    elseif alt then Theme.rect(list,0,y,list.width,list.itemheight,Theme.panel) end
    if row.icon then list:drawTextureScaledAspect(row.icon,r.icon.x,y+r.icon.y,r.icon.width,r.icon.height,1,1,1,1) end
    Theme.text(list,row.name,r.name.x,y+r.name.y,Theme.textColor)
    button(list,r.minus,y,'-',Theme.textColor,h)
    button(list,r.plus,y,'+',row.count>=row.maxCount and Theme.muted or Theme.textColor,h)
    button(list,r.remove,y,'x',Theme.muted,h)
    list:drawTextCentre(tostring(row.count),r.value.x+r.value.width/2,y+r.value.y+(r.value.height-h)/2,
        Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,1,UIFont.Small)
    Theme.text(list,row.weightLabel,r.weight.x,y+r.weight.y,Theme.muted)
    return y+list.itemheight
end

function Drawer:prerender()
    ISCollapsableWindow.prerender(self)
    local h,p=self.fontHeight,self.pad
    Theme.text(self,self.countLabel or '',self.header.x,self.header.y+p/2,Theme.gold)
    Theme.text(self,self.weightLabel or '',self.summary.x,self.summary.y,Theme.textColor)
    Theme.text(self,self.spaceLabel or '',self.summary.x,self.summary.y+h,Theme.muted)
    for i,line in ipairs(self.messageLines or {}) do
        Theme.text(self,line,self.summary.x,self.summary.y+(i+1)*h,self.messageColor)
    end
end

function Drawer:close()
    self:removeFromUIManager()
    self:setVisible(false)
    if self.owner then
        self.owner.cartDrawerOpen=false
    end
end

function Drawer:dispose()
    Tooltip.clear(self.list)
    self:close()
end

return Drawer
