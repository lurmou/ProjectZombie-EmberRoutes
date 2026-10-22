local Cached=require "EmberRoutesProbe/UI/CachedList"
local Table=require "EmberRoutesProbe/UI/WarehouseList"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Text=require "EmberRoutesProbe/UI/Text"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Details={}
local methods={}
methods.__index=methods
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end
local function sourceName(source)
    if source.customName and source.customName~="" then return source.customName end
    for _,kind in ipairs({source.kind or "",source.displayType or ""}) do
        if kind~="" then
            local resolve=_G.getTextOrNull
            local label=type(resolve)=="function" and resolve("IGUI_ContainerTitle_"..kind) or nil
            if label then return label end
        end
    end
    return text("container")
end
local function location(source) return source.x..", "..source.y.." | z="..source.z end
function Details.new(owner,bounds,presentation)
    local h,p=owner.fontHeight,owner.pad
    local compact=bounds.height<h*9
    local parts=assert(Layout.axis(bounds,{{basis=h*(compact and 2 or 3)},{basis=h},{grow=1},{basis=h+p}},
        {direction="column",gap=p/2}))
    local self=setmetatable({owner=owner,bounds=bounds,presentation=presentation,hero=parts[1],heading=parts[2],
        compact=compact,nameLines={},countLabel="",sourceHeading=text("sources"),quantityLabel=text("quantity"),iconSize=h*1.75},methods)
    self.list=Cached.create(owner,parts[3],owner.selectSource,Table.style(nil,sourceName,location))
    self.list.emberMetric="ui.sources"
    Theme.list(self.list) Table.columns(self.list,false) owner:addChild(self.list)
    Table.empty(owner,self.list,text("chooseItem"))
    self.quantityX=self.list.x+self.list.width-h-p-getTextManager():MeasureStringX(UIFont.Small,text("quantity"))
    local r=parts[4]
    self.locate=ISButton:new(r.x,r.y,r.width,r.height,text("locate"),owner,owner.locateSource)
    self.locate:initialise() Theme.enable(self.locate,false)
    self.locate.tooltip=text("chooseSource") owner:addChild(self.locate)
    return self
end
function methods:setItem(row)
    self.row=row
    local owner=self.owner
    local width=self.hero.width-self.iconSize-owner.pad*2
    local label=row and row.label or text("chooseItem")
    if self.nameLabel~=label then
        self.nameLabel=label
        self.nameLines=Text.wrapLimited(label,math.max(1,width),UIFont.Small,self.compact and 1 or 2)
    end
    self.icon=row and self.presentation:icon(row.fullType) or nil
    self.countLabel=row and (text("quantity")..": "..(row.pending and "..." or tostring(row.count))) or ""
    self.sourceHeading=text("sources")..(row and (" ("..#row.sources..")") or "")
    self.selectedSource=Cached.reconcile(self.list,row and row.sources or {},function(source)
        return sourceName(source).."\n"..location(source).."\n"..text("quantity")..": "
            ..(source.pending and "..." or tostring(source.count))
    end,function(source) return source.id end,true)
    Theme.enable(self.locate,self.selectedSource~=false,true)
    self.locate.tooltip=text(self.selectedSource and "locateHint" or "chooseSource")
    Table.empty(owner,self.list,row and text("noSources") or text("chooseItem"))
end
function methods:draw()
    local o,h,p=self.owner,self.owner.fontHeight,self.owner.pad
    local r=self.hero
    Theme.rect(o,r.x,r.y,r.width,r.height,Theme.panel)
    if self.icon then o:drawTextureScaledAspect(self.icon,r.x+p/2,r.y+(r.height-self.iconSize)/2,self.iconSize,self.iconSize,1,1,1,1)
    else Theme.rect(o,r.x+p/2,r.y+(r.height-self.iconSize)/2,self.iconSize,self.iconSize,Theme.border,true) end
    for i,line in ipairs(self.nameLines) do Theme.text(o,line,r.x+self.iconSize+p,r.y+(i-1)*h,Theme.textColor) end
    Theme.text(o,self.countLabel,r.x+self.iconSize+p,r.y+(self.compact and 1 or 2)*h,Theme.muted)
    Theme.text(o,self.sourceHeading,self.heading.x,self.heading.y,Theme.accent)
    Theme.text(o,self.quantityLabel,self.quantityX,self.heading.y,Theme.muted)
end
return Details
