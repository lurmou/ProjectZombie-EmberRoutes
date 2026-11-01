local Cached=require "EmberRoutesProbe/UI/CachedList"
local Table=require "EmberRoutesProbe/UI/WarehouseSourceTable"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Text=require "EmberRoutesProbe/UI/Text"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Details={}
local methods={}
methods.__index=methods
local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end

local function isChinese()
    local q=getText("IGUI_EmberRoutesProbe_Settlement_quantity")
    return q=="数量"
end

local function getCaliberTitles()
    local resolve=getTextOrNull
    local function pick(key) return (type(resolve)=="function" and resolve(key)) or key end
    local s=pick("IGUI_EmberRoutesProbe_Settlement_inStock")
    local r=pick("IGUI_EmberRoutesProbe_Settlement_reserved")
    local t=pick("IGUI_EmberRoutesProbe_Settlement_inTransit")
    return s,r,t
end

local function extractCalibers(row)
    if not row then return 0,0,0 end
    local inStock=row.pending and "..." or (row.count~=nil and row.count or (row.inStock~=nil and row.inStock or 0))
    local reserved=row.reserved~=nil and row.reserved or (row.reserves~=nil and row.reserves or nil)
    local inTransit=row.inTransit~=nil and row.inTransit or (row.transit~=nil and row.transit or (row.in_transit~=nil and row.in_transit or nil))

    if (reserved==nil or inTransit==nil) and row.fullType then
        local calcReserved=0
        local calcTransit=0
        local okJobs,Jobs=pcall(require,"EmberRoutesProbe/BusinessJobs")
        if okJobs and Jobs and Jobs.records then
            local okHaul,hauls=pcall(Jobs.records,'HAUL')
            if okHaul and type(hauls)=="table" then
                for _,itemRecord in pairs(hauls) do
                    if itemRecord and (itemRecord.state=="RUNNING" or itemRecord.state=="EXECUTING" or itemRecord.state=="PAUSED") then
                        if itemRecord.items and type(itemRecord.items)=="table" then
                            for _,itm in ipairs(itemRecord.items) do
                                if type(itm)=="table" and itm.fullType==row.fullType then
                                    calcTransit=calcTransit+1
                                end
                            end
                        end
                        if itemRecord.reservation and type(itemRecord.reservation)=="table" and itemRecord.reservation.fullType==row.fullType then
                            calcReserved=calcReserved+(tonumber(itemRecord.reservation.amount) or 1)
                        end
                    end
                end
            end
            local okCraft,crafts=pcall(Jobs.records,'CRAFT')
            if okCraft and type(crafts)=="table" then
                for _,craftRecord in pairs(crafts) do
                    if craftRecord and not craftRecord.released and (craftRecord.state=="RUNNING" or craftRecord.state=="PAUSED") then
                        if craftRecord.inputTypes and type(craftRecord.inputTypes)=="table" and craftRecord.inputTypes[row.fullType] then
                            calcReserved=calcReserved+(tonumber(craftRecord.inputTypes[row.fullType]) or 1)
                        end
                    end
                end
            end
        end
        if reserved==nil then reserved=calcReserved end
        if inTransit==nil then inTransit=calcTransit end
    end

    return inStock,(reserved or 0),(inTransit or 0)
end

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

local function location(source)
    local floorStr
    if source.z==0 then floorStr=text("floorGround")
    else floorStr=(source.z+1)..text("floorLevel") end
    return floorStr.." · ("..source.x..", "..source.y..")"
end

function Details.new(owner,bounds,presentation)
    local h,p=owner.fontHeight,owner.pad
    local compact=bounds.height<h*10
    local heroBasis=math.floor(h*2.8+p)
    local parts=assert(Layout.axis(bounds,{{basis=heroBasis},{basis=h},{grow=1},{basis=h+p}},
        {direction="column",gap=p/2}))
    local self=setmetatable({owner=owner,bounds=bounds,presentation=presentation,hero=parts[1],heading=parts[2],
        compact=compact,nameLines={},countLabel="",stockLabel="",reservedLabel="",inTransitLabel="",
        stockCount=0,reservedCount=0,inTransitCount=0,
        capStock="",capResv="",capTrn="",capStockW=0,capResvW=0,heroTooltip=nil,
        sourceHeading=text("sources"),quantityLabel=text("quantity"),iconSize=h*2},methods)
    self.list=Cached.create(owner,parts[3],owner.selectSource,Table.style(nil,sourceName,location))
    self.list.emberMetric="ui.sources"
    Theme.list(self.list) Table.columns(self.list,false) owner:addChild(self.list)
    Table.empty(owner,self.list,text("chooseItem"))
    self.quantityX=self.list.x+self.list.width-h-p-getTextManager():MeasureStringX(UIFont.Small,text("quantity"))

    self.heroPanel=ISPanel:new(parts[1].x,parts[1].y,parts[1].width,parts[1].height)
    self.heroPanel:initialise()
    self.heroPanel.background=false
    self.heroPanel.updateTooltip=ISButton.updateTooltip
    Tooltip.attach(self.heroPanel,"prerender")
    owner:addChild(self.heroPanel)
    self.heroPanel.prerender=function(panel)
        ISPanel.prerender(panel)
        self:drawHero(panel)
        if panel.updateTooltip then panel:updateTooltip() end
    end

    -- Pin button at top-right of hero card (measured against both states + padded to avoid right overflow)
    local pinTitleDefault = text("pin") or "收藏"
    local tm = getTextManager()
    local wPin = tm:MeasureStringX(UIFont.Small, text("pin") or "★ 收藏置顶")
    local wUnpin = tm:MeasureStringX(UIFont.Small, text("unpin") or "取消置顶")
    local pinW = math.max(68, math.max(wPin, wUnpin) + p * 2 + 10)
    local pinH = math.floor(h * 1.35)
    local pinX = parts[1].x + parts[1].width - pinW - p / 2
    local pinY = parts[1].y + p / 3
    self.pinButton = ISButton:new(pinX, pinY, pinW, pinH, pinTitleDefault, owner, function()
        if self.row and owner.togglePin then
            owner:togglePin(self.row)
        end
    end)
    self.pinButton:initialise()
    if self.pinButton.setWidth then self.pinButton:setWidth(pinW) else self.pinButton.width = pinW end
    if self.pinButton.setX then self.pinButton:setX(pinX) else self.pinButton.x = pinX end
    self.pinButtonWidth = pinW
    Theme.button(self.pinButton)
    Theme.enable(self.pinButton, false)
    self.pinButton.tooltip = text("pinHint")
    owner:addChild(self.pinButton)

    -- 3 action buttons: Locate, Cart, Create Order
    local botBtns=assert(Layout.axis(parts[4],{{grow=1.0},{grow=1.0},{grow=1.2}},{gap=p/2}))

    self.locate=ISButton:new(botBtns[1].x,botBtns[1].y,botBtns[1].width,botBtns[1].height,text("locate"),owner,owner.locateSource)
    self.locate:initialise() Theme.enable(self.locate,false)
    self.locate.tooltip=text("chooseSource") owner:addChild(self.locate)

    self.cartButton=ISButton:new(botBtns[2].x,botBtns[2].y,botBtns[2].width,botBtns[2].height,getText("IGUI_EmberRoutesProbe_Warehouse_addShort"),owner,function()
        if self.row and owner.addToDeliveryCart then
            local src=self.selectedSource
            local cartKey=src and (self.row.fullType..':'..src.id) or self.row.fullType
            local inCart=owner.deliveryCart and owner.deliveryCart[cartKey]~=nil
            if inCart then owner:removeFromDeliveryCart(cartKey)
            else owner:addToDeliveryCart(self.row,1,src) end
            if self.updateCartButton then self:updateCartButton() end
        end
    end)
    self.cartButton:initialise() Theme.enable(self.cartButton,false)
    self.cartButton.tooltip=getText("IGUI_EmberRoutesProbe_Warehouse_cartTitle") owner:addChild(self.cartButton)

    self.maintainStock=ISButton:new(botBtns[3].x,botBtns[3].y,botBtns[3].width,botBtns[3].height,getText("IGUI_EmberRoutesProbe_Public_createOrder"),owner,function()
        if self.row and self.row.fullType and owner.owner and owner.owner.openPublicOrder then
            owner.owner:openPublicOrder({productType=self.row.fullType})
        end
    end)
    self.maintainStock:initialise() Theme.enable(self.maintainStock,false)
    self.maintainStock.tooltip=text("chooseItem") owner:addChild(self.maintainStock)

    return self
end

function methods:setItem(row)
    self.row=row
    local owner=self.owner
    local pinW=self.pinButton and self.pinButton.width or 68
    local width=self.hero.width-self.iconSize-pinW-owner.pad*3
    local label=row and row.label or text("chooseItem")
    if self.nameLabel~=label then
        self.nameLabel=label
        self.nameLines=Text.wrapLimited(label,math.max(1,width),UIFont.Small,self.compact and 1 or 2)
    end
    self.icon=row and self.presentation:icon(row.fullType) or nil

    if row then
        local inStock,reserved,inTransit=extractCalibers(row)
        self.stockCount=inStock
        self.reservedCount=reserved
        self.inTransitCount=inTransit
        self.stockLabel="Stock: "..tostring(inStock)
        self.reservedLabel="Reserved: "..tostring(reserved)
        self.inTransitLabel="InTransit: "..tostring(inTransit)
    else
        self.stockCount=0
        self.reservedCount=0
        self.inTransitCount=0
        self.stockLabel=""
        self.reservedLabel=""
        self.inTransitLabel=""
    end
    if row then
        local srcCount = row.sources and #row.sources or 0
        local srcStr = tostring(srcCount).." "..text("sources")
        local tip = (row.label or row.fullType or "")
        if row.fullType and row.fullType~=row.label then
            tip = tip.."\n"..row.fullType
        end
        tip = tip.."\n"..text("quantity")..": "..tostring(self.stockCount).." ("..srcStr..")"
        self.heroTooltip = tip
        if self.heroPanel then self.heroPanel.tooltip = tip end
    else
        self.heroTooltip = nil
        if self.heroPanel then self.heroPanel.tooltip = nil end
    end

    self.sourceHeading=text("sources")..(row and row.sources and (" ("..#row.sources..")") or "")
    self.selectedSource=Cached.reconcile(self.list,row and row.sources or {},function(source)
        return sourceName(source).."\n"..location(source).."\n"..text("quantity")..": "
            ..(source.pending and "..." or tostring(source.count))
    end,function(source) return source.id end,true)
    Theme.enable(self.locate,self.selectedSource~=false,true)
    self.locate.tooltip=text(self.selectedSource and "locateHint" or "chooseSource")

    Theme.enable(self.pinButton,row~=nil,true)
    if row then
        local isPinned=row.pinned or (owner.pinnedItems and owner.pinnedItems[row.fullType])
        local pinTitle=isPinned and (text("unpin") or "已收藏") or (text("pin") or "收藏")
        if self.pinButton.setTitle then self.pinButton:setTitle(pinTitle) else self.pinButton.title=pinTitle end
        Theme.styleButton(self.pinButton,isPinned,isPinned)
    else
        local pinTitleDefault=text("pin") or "收藏"
        if self.pinButton.setTitle then self.pinButton:setTitle(pinTitleDefault) else self.pinButton.title=pinTitleDefault end
        Theme.styleButton(self.pinButton,false,false)
    end
    if self.pinButtonWidth and self.hero then
        if self.pinButton.setWidth then self.pinButton:setWidth(self.pinButtonWidth) else self.pinButton.width = self.pinButtonWidth end
        local clampedX = self.hero.x + self.hero.width - self.pinButtonWidth - (owner.pad or 6) / 2
        if self.pinButton.setX then self.pinButton:setX(clampedX) else self.pinButton.x = clampedX end
    end

    Theme.enable(self.cartButton,row~=nil,true)
    if self.updateCartButton then self:updateCartButton() end

    Theme.enable(self.maintainStock,row~=nil,true)
    Table.empty(owner,self.list,row and text("noSources") or text("chooseItem"))
end

function methods:updateCartButton()
    if not self.cartButton then return end
    local row=self.row
    if not row or not row.fullType then
        Theme.enable(self.cartButton,false)
        return
    end
    Theme.enable(self.cartButton,true)
    local src=self.selectedSource
    local cartKey=src and (row.fullType..':'..src.id) or row.fullType
    local inCart=self.owner.deliveryCart and self.owner.deliveryCart[cartKey]~=nil
    local title=getText(inCart and "IGUI_EmberRoutesProbe_Warehouse_removeShort" or "IGUI_EmberRoutesProbe_Warehouse_addShort")
    if self.cartButton.setTitle then self.cartButton:setTitle(title) else self.cartButton.title=title end
end

function methods:drawHero(panel)
    local h,p=self.owner.fontHeight,self.owner.pad
    Theme.rect(panel,0,0,panel.width,panel.height,Theme.panel)
    Theme.rect(panel,0,0,panel.width,panel.height,Theme.border,true)

    if self.icon then
        panel:drawTextureScaledAspect(self.icon,p/2,(panel.height-self.iconSize)/2,self.iconSize,self.iconSize,1,1,1,1)
    else
        Theme.rect(panel,p/2,(panel.height-self.iconSize)/2,self.iconSize,self.iconSize,Theme.border,true)
    end

    local textX=self.iconSize+p
    local totalLines=#(self.nameLines or {})
    local textH=totalLines*h
    local lineY=math.max(p/4,math.floor((panel.height-textH)/2))
    for _,line in ipairs(self.nameLines) do
        Theme.text(panel,line,textX,lineY,Theme.textColor)
        lineY=lineY+h
    end
end

function methods:draw()
    local o=self.owner
    Theme.text(o,self.sourceHeading,self.heading.x,self.heading.y,Theme.accent)
    Theme.text(o,self.quantityLabel,self.quantityX,self.heading.y,Theme.muted)
end
function methods:setVisible(value)
    for _,control in ipairs({self.list,self.heroPanel,self.locate,self.pinButton,self.cartButton,self.maintainStock}) do
        control:setVisible(value)
    end
end

return Details
