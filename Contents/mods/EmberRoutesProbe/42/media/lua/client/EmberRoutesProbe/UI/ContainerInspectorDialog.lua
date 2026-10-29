--[[
    ContainerInspectorDialog.lua - EmberRoutes UI
    Detailed capacity and load monitor for all settlement containers.
]]
require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISScrollingListBox'
require 'ISUI/ISButton'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local StatMeter=require 'EmberRoutesProbe/UI/StatMeter'
local Text=require 'EmberRoutesProbe/UI/Text'

---@class EmberRoutesContainerInspectorDialog:ISCollapsableWindow
local Dialog=ISCollapsableWindow:derive('EmberRoutesContainerInspectorDialog')

local function text(key,...)
    return getText('IGUI_EmberRoutesProbe_Settlement_'..key,...)
end

function Dialog:new(owner,settlementId,containers,counts)
    local w=math.min(520,math.max(380,math.floor(getCore():getScreenWidth()*0.38)))
    local h=math.min(420,math.max(300,math.floor(getCore():getScreenHeight()*0.45)))
    local x=math.floor((getCore():getScreenWidth()-w)/2)
    local y=math.floor((getCore():getScreenHeight()-h)/2)

    local o=ISCollapsableWindow.new(self,x,y,w,h)
    o.owner=owner
    o.settlementId=settlementId
    o.containers=containers or {}
    o.counts=counts or {}
    o.fontHeight=owner.fontHeight or 16
    o.pad=owner.pad or 8
    o.title=text('containerInspectorTitle')
    o.resizable=false
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border
    o:initialise()
    return o
end

function Dialog:initialise()
    ISCollapsableWindow.initialise(self)
end

function Dialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local th=self:titleBarHeight()

    local totalUsed=0
    local totalCap=0
    for _,c in ipairs(self.containers) do
        totalUsed=totalUsed+(c.usedWeight or 0)
        totalCap=totalCap+(c.capacity or 0)
    end
    local pct=totalCap>0 and math.floor((totalUsed/totalCap)*100) or 0
    self.summaryText=string.format(text('containerInspectorTotal'),#self.containers,totalUsed,totalCap,pct)

    local headerH=h*2
    local listY=th+headerH+p/2
    local listH=self.height-listY-h*2-p

    self.list=ISScrollingListBox:new(p,listY,self.width-p*2,listH)
    self.list:initialise()
    self.list.font=UIFont.Small
    self.list.itemheight=math.ceil(h*2.6)
    self.list.backgroundColor=Theme.panel
    self.list.borderColor=Theme.border
    self.list.drawBorder=true
    self.list.doDrawItem=function(list,y,item,alt) return self:drawContainerRow(list,y,item,alt) end

    self.list.onMouseDown=function(list,x,y)
        local index=list:rowAt(x,y)
        local entry=index and list.items[index]
        local c=entry and entry.item
        if not c then return true end
        list.selected=index
        local r=c.layout
        if r and r.locate and x>=r.locate.x and x<=r.locate.x+r.locate.width
                and y>=r.locate.y and y<=r.locate.y+r.locate.height then
            self:locateContainer(c)
        end
        return true
    end
    self:addChild(self.list)

    local closeW=math.max(80,math.floor(self.width*0.25))
    local closeH=math.floor(h*1.5)
    self.closeButton=ISButton:new(self.width-p-closeW,self.height-closeH-p/2,closeW,closeH,
        getTextOrNull('IGUI_EmberRoutesProbe_Warehouse_close') or '关闭',self,function() self:close() end)
    self.closeButton:initialise()
    Theme.button(self.closeButton)
    self:addChild(self.closeButton)

    self:refreshList()
end

function Dialog:refreshList()
    self.list:clear()
    local h,p=self.fontHeight,self.pad
    local itemH=self.list.itemheight
    local locateW=math.max(48,getTextManager():MeasureStringX(UIFont.Small,text('containerLocate'))+p)
    local locateH=math.floor(h*1.35)

    for _,c in ipairs(self.containers) do
        local name=c.customName and c.customName~='' and c.customName
        if not name then
            for _,kind in ipairs({c.kind or '',c.displayType or ''}) do
                if kind~='' then
                    local label=getTextOrNull('IGUI_ContainerTitle_'..kind)
                    if label then name=label break end
                end
            end
        end
        name=name or text('container')

        local floorStr=c.z==0 and text('floorGround') or ((c.z+1)..text('floorLevel'))
        local locStr=floorStr..' ('..c.x..', '..c.y..')'

        local cap=c.capacity or 0
        local used=c.usedWeight or 0
        local ratio=cap>0 and math.max(0,math.min(1,used/cap)) or 0
        local pct=math.floor(ratio*100)
        local weightStr=string.format('%.1f / %.1f kg (%d%%)',used,cap,pct)

        local layout={
            locate={x=self.list.width-locateW-p-16,y=math.floor((itemH-locateH)/2),width=locateW,height=locateH}
        }

        local itemData={
            id=c.id,
            x=c.x,y=c.y,z=c.z,
            name=name,
            locStr=locStr,
            weightStr=weightStr,
            ratio=ratio,
            pct=pct,
            layout=layout
        }
        self.list:addItem(name,itemData)
    end
end

function Dialog:drawContainerRow(list,y,entry,alt)
    local c=entry.item
    if not c then return y+list.itemheight end
    local h,p=self.fontHeight,self.pad
    local itemH=list.itemheight

    if list.selected==entry.index then
        Theme.rect(list,0,y,list.width,itemH,Theme.selected)
    elseif alt then
        Theme.rect(list,0,y,list.width,itemH,Theme.panel)
    end

    local nameY=y+p/3
    local locY=nameY+h

    -- Container name
    Theme.text(list,c.name,p,nameY,Theme.textColor)
    -- Location
    Theme.text(list,c.locStr,p,locY,Theme.muted)

    -- Meter and weight
    local meterW=math.min(120,math.max(60,math.floor(list.width*0.25)))
    local meterH=math.max(6,math.floor(h*0.55))
    local locateX=c.layout.locate.x
    local meterX=locateX-meterW-p
    local meterY=y+math.floor((itemH-meterH)/2)

    StatMeter.draw(list,meterX,meterY,meterW,meterH,c.ratio,{
        mode='load',
        threshold=0.8,
        showPercent=false
    })

    -- Weight text above meter
    local tm=getTextManager()
    local weightW=tm:MeasureStringX(UIFont.Small,c.weightStr)
    Theme.text(list,c.weightStr,meterX+meterW-weightW,nameY,c.pct>85 and Theme.status.ERROR or (c.pct>65 and Theme.gold or Theme.status.READY))

    -- Locate button
    local b=c.layout.locate
    Theme.rect(list,b.x,y+b.y,b.width,b.height,Theme.control)
    Theme.rect(list,b.x,y+b.y,b.width,b.height,Theme.border,true)
    list:drawTextCentre(text('containerLocate'),b.x+b.width/2,y+b.y+(b.height-h)/2,Theme.textColor.r,Theme.textColor.g,Theme.textColor.b,1,UIFont.Small)

    return y+itemH
end

function Dialog:locateContainer(c)
    if not c or not c.id then return end
    if self.owner and self.owner.locator then
        local position,reason=self.owner.locator:locate(c.id)
        if position then
            if HaloTextHelper and HaloTextHelper.addGoodText then
                HaloTextHelper.addGoodText(self.owner.actor,c.name..' · '..c.locStr)
            end
        end
    end
end

function Dialog:prerender()
    ISCollapsableWindow.prerender(self)
    local h,p=self.fontHeight,self.pad
    local th=self:titleBarHeight()
    if self.summaryText then
        Theme.text(self,self.summaryText,p,th+p/2,Theme.gold)
    end
end

function Dialog:close()
    self:removeFromUIManager()
    if self.owner then
        self.owner.containerInspectorDialog=nil
    end
end

return Dialog
