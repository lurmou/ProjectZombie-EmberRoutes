package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Query=require "EmberRoutesProbe/WarehouseQuery"
local PinyinHelper=require "EmberRoutesProbe/PinyinHelper"
local LiquidRegistry=require "EmberRoutesProbe/LiquidRegistry"
local n=0 local function check(v,why) n=n+1 assert(v,why) end

-- 1. Baseline sorting and cache checks
local rows={
    {fullType="B",label="Same",searchKey="same b",node="tools",count=2},
    {fullType="A",label="Same",searchKey="same a",node="tools",count=2},
    {fullType="C",label="Alpha",searchKey="alpha c",node="other",count=0},
    {fullType="D",label="Zulu",searchKey="zulu d",node="other",count=false,pending=true}}
local q=Query.new()
local function ids(mode) local r=q:page(rows,"",false,1,mode) local s="" for _,v in ipairs(r) do s=s..v.fullType end return s end
check(ids("nameAsc")=="CABD" and ids("nameDesc")=="DABC","name sorting has deterministic type-ID ties")
check(ids("quantityAsc")=="CABD" and ids("quantityDesc")=="ABCD","zero is known and unknown sorts last in either quantity direction")
check(rows[1].fullType=="B" and rows[4].count==false,"sorting cannot mutate source snapshot or make unknown quantities usable")
q:page(rows,"same",false,1,"nameAsc") local matching=q.matching
q:page(rows,"SAME",false,2,"nameAsc") check(q.matching==matching,"case-equivalent search and page changes reuse cached filtered order")
local big={}
for i=1,2048 do local id=string.format("Mod.%04d",i) big[i]={fullType=id,label=id,searchKey=string.lower(id),node="tools",count=i} end
local page,p,pages,total=q:page(big,"",false,1,"quantityDesc",big[1].fullType)
check(p==35 and pages==35 and total==2048 and page[#page].fullType==big[1].fullType,"selected type anchors its page after a reorder")
local changed={} for i,v in ipairs(big) do changed[i]=v end
changed[1]={fullType=big[1].fullType,label=big[1].label,searchKey=big[1].searchKey,node="tools",count=9999}
page,p=q:page(changed,"",false,35,"quantityDesc",big[1].fullType)
check(p==1 and page[1].fullType==big[1].fullType,"stock change can follow selected identity across pages")
check(#q:page(big,"missing",false,1,"nameAsc")==0,"empty searches produce a stable empty result")

-- 2. Pinyin initial search checks
local function makeStr(codepoints, utf8bytes)
    local ok, str = pcall(string.char, unpack(codepoints))
    if ok and str and #str == #codepoints then return str end
    return utf8bytes
end

local sMuZhiCanCha = makeStr({26408, 21046, 39184, 21449}, "\230\156\168\229\136\182\233\164\144\229\143\137") -- 木制餐叉
local sDingZi = makeStr({38025, 23376}, "\233\146\137\229\173\144") -- 钉子
local sTieChui = makeStr({38081, 38180}, "\233\147\129\233\148\164") -- 铁锤
local sFuTou = makeStr({26023, 22836}, "\230\150\167\229\164\180") -- 斧头

-- Test PinyinHelper directly
check(PinyinHelper.match(sMuZhiCanCha,"mfc"),"PinyinHelper matches mfc to 木制餐叉")
check(PinyinHelper.match(sMuZhiCanCha,"mzcc"),"PinyinHelper matches mzcc to 木制餐叉")
check(PinyinHelper.match(sMuZhiCanCha,"mzc"),"PinyinHelper matches mzc to 木制餐叉")
check(PinyinHelper.match(sDingZi,"dz"),"PinyinHelper matches dz to 钉子")
check(PinyinHelper.match(sTieChui,"tc"),"PinyinHelper matches tc to 铁锤")
check(PinyinHelper.match(sFuTou,"ft"),"PinyinHelper matches ft to 斧头")
check(PinyinHelper.match("Base.Hammer","hammer"),"PinyinHelper passes ASCII directly")

local pinyinRows={
    {fullType="Base.WoodenFork",label=sMuZhiCanCha,searchKey=sMuZhiCanCha.." base.woodenfork",node="tools",count=10},
    {fullType="Base.Nails",label=sDingZi,searchKey=sDingZi.." base.nails",node="tools",count=100},
    {fullType="Base.Hammer",label=sTieChui,searchKey=sTieChui.." base.hammer",node="tools",count=5},
    {fullType="Base.Axe",label=sFuTou,searchKey=sFuTou.." base.axe",node="tools",count=1},
}

-- Test WarehouseQuery with Pinyin initials
local pyQuery=Query.new()
local forkResult=pyQuery:page(pinyinRows,"mfc",false,1,"default")
check(#forkResult==1 and forkResult[1].fullType=="Base.WoodenFork","Query mfc retrieves 木制餐叉")

local nailResult=pyQuery:page(pinyinRows,"dz",false,1,"default")
check(#nailResult==1 and nailResult[1].fullType=="Base.Nails","Query dz retrieves 钉子")

local hammerResult=pyQuery:page(pinyinRows,"tc",false,1,"default")
check(#hammerResult==1 and hammerResult[1].fullType=="Base.Hammer","Query tc retrieves 铁锤")

local englishResult=pyQuery:page(pinyinRows,"hammer",false,1,"default")
check(#englishResult==1 and englishResult[1].fullType=="Base.Hammer","Query english pass-through retrieves Hammer")

-- 3. LiquidRegistry checks
-- A. Allowed fixed furniture
local mockRainBarrel={
    category="RainCollectorBarrel",
    waterAmount=80.0,
    tainted=true,
    hasWater=true,
}
local mockSink={
    category="Sink",
    waterAmount=20.0,
    tainted=false,
    hasWater=true,
}
local mockToilet={
    category="Toilet",
    waterAmount=15.0,
    tainted=false,
    hasWater=true,
}

-- B. Strictly disallowed mobile items
local mockBucketGround={
    isWorldItem=true,
    category="RainCollectorBarrel", -- fake category on mobile item
    waterAmount=10.0,
}
local mockLooseWaterBucket={
    getItem=function() return {getName=function() return "Water Bucket" end} end,
    waterAmount=10.0,
}
local mockGroundBottle={
    isItem=true,
    name="Water Bottle",
    waterAmount=1.0,
}

check(LiquidRegistry.isAllowedObject(mockRainBarrel)==true,"RainCollectorBarrel is allowed fixed furniture")
check(LiquidRegistry.isAllowedObject(mockSink)==true,"Sink is allowed fixed furniture")
check(LiquidRegistry.isAllowedObject(mockToilet)==true,"Toilet is allowed fixed furniture")
check(LiquidRegistry.isAllowedObject(mockBucketGround)==false,"Ground bucket is strictly rejected")
check(LiquidRegistry.isAllowedObject(mockLooseWaterBucket)==false,"Loose water bucket is strictly rejected")
check(LiquidRegistry.isAllowedObject(mockGroundBottle)==false,"Ground bottle is strictly rejected")

-- C. Municipal water before shut-off (Infinite water for Sink and Toilet)
_G.SandboxVars=_G.SandboxVars or {}
_G.SandboxVars.WaterShutModifier=-1 -- never shut off
check(LiquidRegistry.isWaterShutOff()==false,"Water is not shut off when modifier is -1")

local sinkMeasureBefore=LiquidRegistry.measure(mockSink)
check(sinkMeasureBefore.isInfinite==true and sinkMeasureBefore.amount==math.huge,"Sink has infinite water before shutoff")
check(sinkMeasureBefore.displayAmount=="无限 (∞)","Sink displayAmount is 无限 (∞) before shutoff")
check(sinkMeasureBefore.isTainted==false,"Piped water from sink is clean")

local toiletMeasureBefore=LiquidRegistry.measure(mockToilet)
check(toiletMeasureBefore.isInfinite==true and toiletMeasureBefore.amount==math.huge,"Toilet has infinite water before shutoff")
check(toiletMeasureBefore.displayAmount=="无限 (∞)","Toilet displayAmount is 无限 (∞) before shutoff")

local barrelMeasure=LiquidRegistry.measure(mockRainBarrel)
check(barrelMeasure.isInfinite==false and barrelMeasure.amount==80.0,"Rain barrel is always finite (80L)")
check(barrelMeasure.isTainted==true,"Rain barrel water is tainted")

-- D. Municipal water after shut-off (Finite residual water)
_G.SandboxVars.WaterShutModifier=0
_G.getGameTime=function() return {getNights=function() return 5 end,getWorldAgeHours=function() return 120 end} end
check(LiquidRegistry.isWaterShutOff()==true,"Water is shut off when days >= modifier")

local sinkMeasureAfter=LiquidRegistry.measure(mockSink)
check(sinkMeasureAfter.isInfinite==false and sinkMeasureAfter.amount==20.0,"Sink has finite residual water (20L) after shutoff")
check(sinkMeasureAfter.displayAmount=="20.0","Sink shows exact residual liters after shutoff")

local toiletMeasureAfter=LiquidRegistry.measure(mockToilet)
check(toiletMeasureAfter.isInfinite==false and toiletMeasureAfter.amount==15.0,"Toilet has finite residual water (15L) after shutoff")

-- E. Square scanning and summary
local testSquare={
    objects={mockSink,mockToilet,mockRainBarrel,mockBucketGround,mockGroundBottle}
}
local scanned=LiquidRegistry.scanSquare(testSquare)
check(#scanned==3,"Square scanning only collects the 3 fixed furniture objects, ignoring 2 mobile items")
local sum=LiquidRegistry.summary(scanned)
check(sum.totalFinite==115.0,"Summary aggregates correct total finite water (20+15+80=115L)")
check(sum.cleanAmount==35.0,"Clean finite water is 35L (Sink 20L + Toilet 15L)")
check(sum.taintedAmount==80.0,"Tainted finite water is 80L (Barrel)")

-- 4. WarehouseDetails 3 calibers verification
if not _G.getText then
    _G.getText = function(k) return (ERTestTranslations and ERTestTranslations[k]) or k end
end
if not _G.getTextManager then
    _G.getTextManager = function() return { MeasureStringX = function(_, _, s) return #s * 10 end, getFontHeight = function() return 16 end } end
end
if not _G.ISButton then
    local Base={}
    function Base:derive(name) local cls=setmetatable({Type=name},{__index=self}) cls.__index=cls return cls end
    function Base:new(x,y,w,h,title) return setmetatable({x=x,y=y,width=w,height=h,title=title,children={},selected=1,items={}},self) end
    Base.__index=Base
    function Base:initialise() self.initialised=true end
    function Base:createChildren() end
    function Base:addChild(child) self.children[#self.children+1]=child end
    function Base:setEnable(value) self.enable=value end
    function Base:setTitle(value) self.title=value end
    function Base:clear() self.items={} end
    function Base:addItem(text,item,tooltip) self.items[#self.items+1]={text=text,item=item,tooltip=tooltip} end
    function Base:setWantKeyEvents(v) end
    function Base:addOption(opt) end
    function Base:setOnMouseDownFunction(target,fn) self.target,self.onclick=target,fn end
    function Base:setOverrideAButtonFunction(target,fn) self.target,self.aButton=target,fn end
    function Base:ensureVisible() end
    function Base:setScrollHeight(v) end
    function Base:getYScroll() return 0 end
    function Base:setYScroll(v) end
    _G.ISButton=Base
    _G.ISScrollingListBox=Base
    _G.ISPanel=Base
    _G.ISComboBox=Base
    _G.UIFont={Small=1}
    for _,name in ipairs({"ISButton","ISScrollingListBox","ISPanel","ISComboBox"}) do package.loaded['ISUI/'..name]=true end
end
local Details=require "EmberRoutesProbe/UI/WarehouseDetails"
local mockOwner={
    fontHeight=16,
    pad=10,
    selectSource=function() end,
    locateSource=function() end,
    addChild=function() end,
}
local mockPresentation={icon=function() return nil end}
local detailsPanel=Details.new(mockOwner,{x=0,y=0,width=400,height=500},mockPresentation)
local testItemRow={
    fullType="Base.Nails",
    label=sDingZi,
    count=120,
    reserved=30,
    inTransit=15,
    sources={},
}
detailsPanel:setItem(testItemRow)
check(detailsPanel.stockCount==120,"Physical stock caliber is 120")
check(detailsPanel.reservedCount==30,"Work order reserved caliber is 30")
check(detailsPanel.inTransitCount==15,"In-transit caliber is 15")
check(detailsPanel.stockCount~=120+30+15,"Calibers are NOT added together")
check(detailsPanel.stockCount~=120-30,"Reserved is NOT mechanically deducted from stock")
check(string.find(detailsPanel.stockLabel,"120")~=nil,"Stock label contains accurate in-stock count")
check(string.find(detailsPanel.reservedLabel,"30")~=nil,"Reserved label contains accurate reserved count")
check(string.find(detailsPanel.inTransitLabel,"15")~=nil,"In-transit label contains accurate in-transit count")

if ERTestNanoTime then
    for i=1,30 do Query.new():page(big,"",false,1,"quantityDesc") end
    local start=ERTestNanoTime()
    for i=1,30 do Query.new():page(big,"",false,1,"quantityDesc") end
    local build=(ERTestNanoTime()-start)/30000000
    q:page(big,"",false,1,"quantityDesc") start=ERTestNanoTime()
    for i=1,300 do q:page(big,"",false,i%35+1,"quantityDesc") end
    local cached=(ERTestNanoTime()-start)/300000000
    print(string.format("BASELINE Kahlua pure-query types=2048 coldAvgMs=%.4f cachedPageAvgMs=%.4f; fixture CPU only, not engine/GPU",build,cached))
end
print("PASS "..n.." warehouse query sorting/cache/anchor checks")
