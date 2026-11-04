-- Native widgets/services are host doubles; real dossier projection/layout/cache/lifecycle.
ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local Layout=require 'EmberRoutesProbe/UI/Layout'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Cards=require 'EmberRoutesProbe/UI/OrderMonitorCards'
local Slot=require 'EmberRoutesProbe/UI/ItemSlot'
for _,h in ipairs({12,20,32}) do
    for _,w in ipairs({1,140,500,900,1400,4000}) do
        local split=Layout.split({x=5,y=7,width=w,height=500},h,8)
        check(split.index.width<=w and split.main.width<=w,'bounded at every width')
        if split.compact then check(split.index.x==split.main.x and split.main.width==w,'compact toggle full width')
        else
            check(split.index.width>=h*14 and split.index.width<=h*22,'index min/max')
            check(split.main.width>=h*28 and split.main.x+split.main.width==w+5,'main minimum and no overflow')
        end
    end
end
local old=Layout.axis({x=0,y=0,width=100,height=50},{{grow=1},{grow=2}},{gap=10})
check(old[1].width==30 and old[2].width==60,'axis behavior unchanged')
local production={id='production',generation=1,kind='CRAFT',title='Planks',name='Ada',npcId='n1',target=10,produced=4,delivered=2,
    bucket='active',canPause=true,assets={{fullType='Base.Log',kind='inputs',held=true}}}
local delivery={kind='DELIVERY',title='Supplies',name='Ada',npcId='n1',target=8,delivered=3,cargoHeld=5,bucket='active'}
local cleaning={kind='DEMAND',title='Cleaning',demandSummary='54 stains pending',detailContext='Home',bucket='active',
    children={{name='Ada',npcId='n1',bucket='active',stages={{labelKey='wipe'}},stageIndex=1}}}
local p=Cards.detailRows(production,false)
check(p[1].hero and p[1].meters[1].value=='4 / 10' and p[1].meters[2].value=='2 / 10','produced and stored separate')
check(p[2].npcId=='n1' and p[3].text and p[4].isAssetRow,'hero / worker / originals order')
local d=Cards.detailRows(delivery,false)
check(d[1].meters[1].value=='3 / 8' and d[1].meters[1].fraction==3/8,'held cargo never credited')
local function countLine(rows,line,alert)
    local count=0
    for _,r in ipairs(rows) do
        for _,value in ipairs(r.lines or {}) do
            if value==line and (alert==nil or r.alert==alert) then count=count+1 end
        end
    end
    return count
end
local missing=Cards.text('carrierMissing')
for _,expanded in ipairs({false,true}) do
    local unavailable=Cards.detailRows({kind='CRAFT',bucket='active',carrierAvailable=false},expanded)
    check(unavailable[3].alert and countLine(unavailable,missing,true)==1,'missing carrier alerts without another blocker after handler')
    local children=Cards.detailRows({kind='DEMAND',bucket='active',carrierAvailable=true,
        children={{name='A',carrierAvailable=false},{name='B',carrierAvailable=false}}},expanded)
    check(countLine(children,missing,true)==1,'child carrier failures share one alert, folded or expanded')
    check(countLine(Cards.detailRows({kind='CRAFT',carrierAvailable=false,
        children={{carrierAvailable=false}}},expanded),missing,true)==1,'parent and child carrier failures do not duplicate alert')
end
for _,held in ipairs({0,5}) do
    local available=Cards.detailRows({kind='DELIVERY',carrierAvailable=true,cargoHeld=held,target=8,delivered=3},true)
    check(countLine(available,missing)==0,'available carrier never alerts')
    check(countLine(available,Cards.text('detail_carrying',held))==(held>0 and 1 or 0),'only positive cargo appears in notes')
end
local carried=Cards.detailRows(delivery,true)
check(carried[#carried].title==Cards.text('detail_more') and
    countLine({carried[#carried]},Cards.text('detail_carrying',5))==1,'carrying is secondary expanded notes')
check(countLine(d,Cards.text('detail_carrying',5))==0 and carried[1].meters[1].value=='3 / 8'
    and carried[1].meters[1].fraction==3/8,'carrying stays outside hero and delivered numerator')
local carriedProduction=Cards.detailRows({kind='CRAFT',cargoHeld=7,produced=4,delivered=2,target=10},true)
check(carriedProduction[1].meters[1].value=='4 / 10' and carriedProduction[1].meters[2].value=='2 / 10',
    'carrying does not change produced, delivered or target')
local emptyCargo=Cards.detailRows({kind='CRAFT',carrierAvailable=true},true)
check(countLine(emptyCargo,missing)==0 and #emptyCargo==2,'available carrier and absent cargo add no facts')
local c=Cards.detailRows(cleaning,false)
check(c[1].meters[1].value=='54 stains pending' and c[1].meters[1].fraction==nil,'cleaning no fabricated denominator')
check(c[1].lines[1]=='Home' and c[2].npcId=='n1','range follows hero, then handler')
for _,row in ipairs({production,delivery,cleaning,{kind='DEMAND',title='unhandled',bucket='waiting'},
    {kind='CRAFT',title='paused',bucket='paused',reason='USER_PAUSED',produced=2,target=10}}) do
    for _,r in ipairs(Cards.detailRows(row,false)) do check(not r.alert,'normal, unhandled and paused have no strong color') end
end
for _,row in ipairs({{kind='DEMAND',title='blocked',blocked=true,demandReason='No water',bucket='attention'},
    {kind='DEMAND',title='unknown',uncertain=true,bucket='attention'},
    {kind='CRAFT',title='materials',reason='MISSING_INPUT',bucket='waiting'}}) do
    local rows=Cards.detailRows(row,false)
    check(rows[2].title==Cards.text('unassigned') and rows[3].alert,'unassigned then independent blocker/unknown')
end
local stage={kind='CRAFT',title='Steps',stages={{labelKey='confirmed',status='COMPLETED'}},bucket='active'}
check(#Cards.detailRows(stage,true)>#Cards.detailRows(stage,false),'technical steps folded by default')
local group=Cards.detailRows({title='Group',children={{npcId='1',name='A'},{npcId='2',name='B'}}},false)
check(group[2].title==Cards.text('handlers',2) and #group[1].meters==0,'group summary has no fake joint percentage')
local cache=Slot.prepare({icon=nil,name='Long item name',countText='× 3',status='RECONCILE'},
    {x=10,y=20,width=240,height=64},Theme.revision)
check(Slot.hit(cache,10,20) and Slot.hit(cache,249,83) and not Slot.hit(cache,250,84),'slot uses exact prepared bounds')
local rects={}
local drawOwner={drawRect=function(_,x,y,w,h) rects[#rects+1]={x,y,w,h} end,drawText=function() end}
Slot.draw(drawOwner,cache)
check(rects[1][1]==cache.x and rects[1][2]==cache.y+cache.height-1 and rects[1][3]==cache.width,'slot drawing shares bounds')
local shell=ERSettlementPreview('orders',20,1280,900)
local page=shell.pages.orders
page.store:setState({snapshot={rows={production}},selection=false})
check(not page.narrow and page.orderList.width<page.details.list.width,'narrow index / broad main')
check(page.buttons.stop.visible and not page.buttons.resume.visible and not page.buttons['return'].visible,'one normal operation')
check(page.filterChips.y<page.orderList.y and page.buttons.create.x==page.orderList.x,'filters and create live in index')
-- Global getter is replaced to detect every draw-time measurement.
local getter=getTextManager
getTextManager=function() error('measurement during draw') end
EmberRoutesProbeJava={getPortraitTexture=function() error('bridge during draw') end}
local borders=0
page.details.list.drawRectBorder=function() borders=borders+1 end
page.orderList.drawRectBorder=function() borders=borders+1 end
for _,entry in ipairs(page.details.list.items) do page.details.list.emberStyle.draw(page.details.list,0,entry) end
for _,entry in ipairs(page.orderList.items) do page.orderList.emberStyle.draw(page.orderList,0,entry) end
page.filterChips:prerender()
check(borders==0,'dossier draws no full-frame rows or nested boxes; no draw-time measurements/bridge')
getTextManager=getter
local scope=page.activationScope local old=scope:wrapCallback(function() error('stale callback') end)
local prior=page.details.list.items[1].item.visual
local indexPrior=page.orderList.items[1].item.visual
Theme.applyPreset('ae2')
check(page.details.list.items[1].item.visual~=prior and page.orderList.items[1].item.visual~=indexPrior and Theme.dossier.gold.r==.81,'theme event rebuilds restrained cache')
page:deactivate() old()
local count=#page.details.list.items
Theme.applyPreset('classic')
check(not scope:isCurrent() and #page.details.list.items==count and not page.activation,'old token and theme listener released')
shell:close()
-- Bounded stable-ID portrait cache with actual service and fake engine binding.
package.loaded['EmberRoutesProbe/PersonnelService']=nil
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return ERPortraitWorld end}
ERPortraitWorld={}
local handle={}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {handle=handle} end,valid=function() return true end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return {} end}
package.loaded['EmberRoutesProbe/Boot']={}
local gets=0 local clock=0
getTimestampMs=function() return clock end
EmberRoutesProbeJava={getPortraitTexture=function() gets=gets+1 return 'texture' end}
local Personnel=require 'EmberRoutesProbe/PersonnelService'
local owner={}
local shot=Personnel.portrait({},'home','npc',false,owner)
check(shot.texture=='texture' and gets==1,'activation fetches a detached snapshot')
clock=2000
check(Personnel.portrait({},'home','npc',false,owner)==shot and gets==1,'success never polled or re-fetched')
local notifications=0 local off=Personnel.watchPortrait(function(id) notifications=notifications+1 end)
Personnel.invalidate('npc')
local nextShot=Personnel.portrait({},'home','npc',false,owner)
check(nextShot~=shot and gets==2 and notifications==1,'explicit invalidation refreshes outside drawing')
off() Personnel.invalidate('npc')
check(notifications==1,'portrait listener released')
Personnel.releasePortrait('npc',owner)
Personnel.portrait({},'home','npc',false,owner)
check(gets==3,'last owner releases cached references')
EmberRoutesProbeJava.getPortraitTexture=function() gets=gets+1 end
Personnel.releasePortrait('npc',owner)
Personnel.portrait({},'home','npc',false,owner)
local failed=gets
Personnel.portrait({},'home','npc',false,owner)
check(gets==failed,'failed portrait retry throttled')
clock=clock+1000 Personnel.portrait({},'home','npc',false,owner)
check(gets==failed+1,'failed portrait retry allowed after cadence')
local unbounded=Cards.detailRows({kind='CRAFT',produced=5,delivered=2},false)[1].meters
check(unbounded[1].value=='5' and unbounded[1].fraction==nil and unbounded[2].value=='2','unknown total preserves real result without percentage')
EmberRoutesProbeJava.getPortraitTexture=function() gets=gets+1 return 'portrait' end
for i=1,17 do Personnel.portrait({},'home','bounded-'..i,false,owner) end
local before=gets
Personnel.portrait({},'home','bounded-1',false,owner)
check(gets==before+1,'portrait cache bounded to sixteen stable IDs')
local Avatar=require 'EmberRoutesProbe/UI/Avatar3DView'
local avatar=Avatar:new(0,0,80,80)
avatar:setPortrait({name='Ada',icon={}})
local scope2=require('EmberRoutesProbe/UI/PageLifecycle').createActivationScope({})
local late=scope2:wrapCallback(function() error('orphan avatar callback') end)
scope2:defer(function() avatar:setPortrait(nil) end)
scope2:dispose() late()
check(avatar.portraitTexture==nil and avatar.fallbackTexture==nil and avatar.fallbackInitials==nil,'avatar snapshot released with token')
getTextManager=function() error('avatar draw measures text') end
EmberRoutesProbeJava.getPortraitTexture=function() error('avatar draw calls Java') end
avatar:prerender()
check(true,'Avatar3DView prerender uses prepared cache only')
getTextManager=getter
print('ui-visual-slice2: '..checks..' PASS; native UI/Java/textures mocked')
