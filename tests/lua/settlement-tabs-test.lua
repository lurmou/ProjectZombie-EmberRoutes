-- Real production shell and both pages, installed native tickbox, fake ISUI host.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(value,message) assert(value,message) checks=checks+1 end
local Base={}
function Base:derive(name) local cls={Type=name} cls.__index=cls return setmetatable(cls,{__index=self}) end
function Base:new(x,y,w,h,title,target,callback)
    return setmetatable({x=x,y=y,width=w,height=h,title=title,target=target,onclick=callback,items={},selected=0},{__index=self})
end
function Base:initialise() self.children={} self.initialised=true end
function Base:instantiate()
    if self.native then return end self.native=true self:createChildren()
end
function Base:createChildren() end
function Base:addChild(child) check(child.initialised,'native child initialized once before mount') child.parent=self child:instantiate() self.children[#self.children+1]=child end
function Base:addToUIManager() self:instantiate() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:setVisible(v) self:instantiate() self.visible=v end
function Base:close() self:setVisible(false) end
function Base:bringToTop() self.raised=true end
function Base:clear() self.items={} self.selected=0 end
function Base:titleBarHeight() return 24 end
function Base:setWantKeyEvents() end
function Base:update() end function Base:prerender() end
function Base:setX(x) self.x=x end function Base:setY(y) self.y=y end
function Base:drawTextureScaledAspect(texture) assert(type(texture)~='string','Texture required, got icon name') end
function Base:setHeight(h) self.height=h end function Base:setWidth(w) self.width=w end function Base:getWidth() return self.width end
function Base:getAbsoluteX() return self.x+(self.parent and self.parent:getAbsoluteX() or 0) end
function Base:getAbsoluteY() return self.y+(self.parent and self.parent:getAbsoluteY() or 0) end
function Base:setTitle(value) self.title=value end function Base:setEnable(value) self.enable=value end
function Base:setOnMouseDownFunction(target,fn) self.target=target self.onclick=fn end
function Base:setOverrideAButtonFunction() end
function Base:setYScroll(value) self.scroll=value end function Base:getYScroll() return self.scroll or 0 end
function Base:setScrollHeight(value) self.scrollHeight=value end function Base:ensureVisible() end
function Base:drawText() end function Base:drawRect() end function Base:drawRectBorder() end
function Base:addItem(label,item,tooltip)
    local entry={text=label,item=item,tooltip=tooltip,height=self.itemheight,index=#self.items+1}
    self.items[#self.items+1]=entry return entry
end
ISPanel=Base ISCollapsableWindow=Base ISButton=Base ISScrollingListBox=Base
ISTextEntryBox=Base:derive('TextEntry')
function ISTextEntryBox:new(value,x,y,w,h) local o=Base.new(self,x,y,w,h) o.value=value return o end
function ISTextEntryBox:setPlaceholderText(value) self.placeholderText=value end
function ISTextEntryBox:setText(value) self.value=value if self.onTextChangeFunction then self.onTextChangeFunction(self.target) end end
function ISTextEntryBox:getText() return self.value end function ISTextEntryBox:isFocused() return self.focused end
function ISTextEntryBox:unfocus() self.focused=false end
ISComboBox=Base:derive('Combo')
function ISComboBox:new(...) local o=Base.new(self,...) o.options={} o.selected=1 return o end
function ISComboBox:addOption(value) self.options[#self.options+1]=value end
function ISComboBox:clear() self.options={} self.selected=1 end
function ISComboBox:setToolTipMap() end function ISComboBox:hidePopup() self.popupHidden=true end
ISModalDialog=Base:derive('Modal')
function ISModalDialog:new(x,y,w,h,message,yesno,target,callback)
    local o=Base.new(self,x,y,w,h) o.text=message o.target=target o.onclick=callback return o
end
for _,name in ipairs({'ISPanel','ISCollapsableWindow','ISButton','ISScrollingListBox','ISTextEntryBox','ISComboBox','ISModalDialog'}) do package.loaded['ISUI/'..name]=true end
UIFont={Small=1} Keyboard={KEY_UP=1,KEY_DOWN=2,KEY_ESCAPE=3,KEY_LEFT=4,KEY_RIGHT=5,KEY_TAB=6,KEY_RETURN=7,KEY_PRIOR=8,KEY_NEXT=9}
Joypad={AButton=1,BButton=2,XButton=3,YButton=4,LBumper=5,RBumper=6,LStickButton=7,RStickButton=8}
local sw,sh,fh=1920,1080,20
function getCore() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
function getTextManager() return {getFontHeight=function() return fh end,MeasureStringX=function(_,_,s) return #s*fh/2 end} end
function getTextOrNull(key) return ERTestTranslations and ERTestTranslations[key] end
function getText(key,...)
    local value=getTextOrNull(key) or key
    for i,arg in ipairs({...}) do local replacement=tostring(arg) value=value:gsub('%%'..i,function() return replacement end) end
    return value
end
function getItemNameFromFullType(id) return id end function getTexture() return {} end
local sawTexture={texture=true}
function tryGetTexture(name) if name=='Item_TestSawVariant' then return sawTexture end end
function getScriptManager() return {FindItem=function(_,id)
    if id=='Base.Saw2' then
        return {getNormalTexture=function() return {texture=true} end,getIconsForTexture=function()
            return {isEmpty=function() return false end,get=function() return 'TestSawVariant' end}
        end}
    end
end} end
function getCell() return {} end
function getTimestampMs() return 10000 end
function isClient() return false end function isServer() return false end
local actor={getIndex=function() return 0 end,getJoypadBind=function() return -1 end,Say=function() end}
local currentActor=actor
function getSpecificPlayer() return currentActor end
local root={} local permitted=true
local entry={id='settlement',name='Settlement'}
local entries={settlement=entry,other={id='other',name='Other'}}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return root end,authorized=function() return permitted end,
    view=function(_,id) if permitted then return entries[id] end return nil,'ACCESS_DENIED' end}
local cleared=0
package.loaded['EmberRoutesProbe/WarehouseLocator']={new=function() return {clear=function() cleared=cleared+1 end} end}
package.loaded['EmberRoutesProbe/UI/TooltipAnchor']={attach=function() end,clear=function() end}
package.loaded['EmberRoutesProbe/UI/SettlementSelector']={open=function() end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {handle={getFullName=function() return 'Worker' end}} end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={describe=function() return nil end}
package.loaded['EmberRoutesProbe/LogisticsMenu']={command=function() return 'MODE_CONFIGURED' end}
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/client/ISUI/ISTickBox.lua')
package.loaded['ISUI/ISTickBox']=true
local rows={}
for i=1,135 do rows[i]={fullType=string.format('Base.Item%03d',i),node='other',count=i,sources={{id='source',x=1,y=2,z=0,count=i}}} end
local warehouseSnapshot={state='READY',rows=rows,counts={loaded=1,containers=1,items=135,unloaded=0,private=0,missing=0,limited=0},revision=1}
local worker={id='worker',reason='SCANNING',state='IDLE',taskId='',producer='',delivered=0,total=0,source='',destination=''}
local logisticsSnapshot={running=true,intake=true,tidy=true,workers={worker}}
local wareCount,logCount,stops=0,0,0
local wareCallbacks,logCallbacks={},{}
local craftCount,craftCallbacks,craftCommands=0,{},{}
local monitorCount,monitorCallbacks,monitorCommands=0,{},{}
local monitorRow={id='CRAFT:monitor-job',jobId='monitor-job',npcId='worker',generation=3,kind='CRAFT',name='Worker',title='Saw logs',
 state='PAUSED',phase='CRAFTING',bucket='paused',bodyMode='FOLLOW',target=3,requested=3,produced=0,delivered=0,
 assets={{id=11,kind='tools'}},nodes={},carrierAvailable=true,canResume=true,canCancel=true}
local monitorSnapshot={rows={monitorRow}}
package.loaded['EmberRoutesProbe/OrderMonitorService']={status=function() return monitorSnapshot end,
 watch=function(_,_,fn) monitorCount=monitorCount+1 monitorCallbacks[#monitorCallbacks+1]=fn return function() monitorCount=monitorCount-1 end end,
 command=function(_,_,id,generation,action) monitorCommands[#monitorCommands+1]={id=id,generation=generation,action=action} return 'QUEUED' end}
local craftSnapshot={workers={{id='worker',name='Worker',busy=false}},surfaces={{id='surface',x=1,y=2,z=0}},surfaceId='surface'}
local onWatch
package.loaded['EmberRoutesProbe/WarehouseIndex']={watch=function(_,fn)
    wareCount=wareCount+1 wareCallbacks[#wareCallbacks+1]=fn fn(warehouseSnapshot)
    if onWatch then onWatch() end
    return function() wareCount=wareCount-1 end
end,refresh=function() end}
package.loaded['EmberRoutesProbe/LogisticsService']={status=function() return logisticsSnapshot end,
    watch=function(_,fn) logCount=logCount+1 logCallbacks[#logCallbacks+1]=fn return function() logCount=logCount-1 end end,
    stop=function() stops=stops+1 end}
local recipeRows={
 {id='Base.CarveWoodenFork',name=getText('TEST_ItemName_Base.WoodenFork'),supported=true,surface=true,yield=1,product='Base.WoodenFork',category='Carving',inputs={},outputs={{name='Fork',fullType='Base.WoodenFork',count=1}}},
 {id='Base.CarveWoodenSpoon',name=getText('TEST_ItemName_Base.WoodenSpoon'),supported=true,surface=true,yield=1,product='Base.WoodenSpoon',category='Carving',inputs={},outputs={}},
 {id='Base.SawLogs',name='Saw logs',supported=true,surface=false,yield=3,product='Base.Plank',category='Carpentry',
 inputs={{slot=0,count=1,keep=false,names={'RawLog'},choices={{name='RawLog',fullType='Base.Log'}},more=0},
 {slot=1,count=1,keep=true,names={'Handsaw'},choices={{name='Handsaw',fullType='Base.Saw'},{name='Saw2',fullType='Base.Saw2'}},more=0}},
 outputs={{name='Plank',count=3,fullType='Base.Plank'}}}}
local catalogCount,previewCount=0,0
local catalogCallbacks,previewCallbacks={},{}
package.loaded['EmberRoutesProbe/CraftingService']={status=function() return craftSnapshot end,
 describe=function(id) for _,row in ipairs(recipeRows) do if row.id==id then return row end end end,
 chooseSurface=function() return 'surface' end,
 watchCatalog=function(_,_,q,fn)
   catalogCount=catalogCount+1 catalogCallbacks[#catalogCallbacks+1]=fn
   local found={} for _,row in ipairs(recipeRows) do
    if (not q.category or q.category==row.category) and (q.search=='' or row.name:lower():find(q.search:lower(),1,true)) then found[#found+1]=row end
   end
   fn({rows=found,categories={'Carving','Carpentry'},page=1,pages=1,total=#found,loading=false,revision=1})
   return function() catalogCount=catalogCount-1 end
 end,
 preview=function(_,_,npc,id,n,surface,fn)
   previewCount=previewCount+1 previewCallbacks[#previewCallbacks+1]=fn
   local units=id=='Base.SawLogs' and math.ceil((n or 1)/3) or n or 1
   fn({state='READY',conditions={},counts={[0]={available=units,required=units},[1]={available=1,required=1}}})
   return function() previewCount=previewCount-1 end
 end,
 watch=function(_,_,fn) craftCount=craftCount+1 craftCallbacks[#craftCallbacks+1]=fn return function() craftCount=craftCount-1 end end,
 command=function(_,settlement,npc,command,surface,recipeId,quantity)
  craftCommands[#craftCommands+1]={settlement=settlement,npc=npc,command=command,surface=surface,recipeId=recipeId,quantity=quantity} return 'STARTED'
 end}
local Dashboard=require 'EmberRoutesProbe/SettlementDashboard'
local Logistics=require 'EmberRoutesProbe/LogisticsDashboard'
local shell=Dashboard.open(actor,entry.id)
local page=shell.pages.warehouse
check(shell.activeTab=='warehouse' and not shell.pages.logistics and wareCount==1,'only initial warehouse page is created and subscribed')
check(shell.tabButtons.warehouse.borderColor~=shell.tabButtons.orders.borderColor,'active tab is visibly marked')
check(not shell.tabButtons.logistics and not shell.tabButtons.crafting,'legacy configuration is not exposed as main navigation')
shell:selectTab('orders')
local monitor=shell.pages.orders
check(monitorCount==1 and wareCount==0 and #monitor.orderList.items==1,'new monitor owns only its active subscription')
check(monitor.store.value.selection=='CRAFT:monitor-job' and monitor.buttons.resume.enable,'monitor selects stable job identity while worker follows')
monitor:command('resume')
check(monitorCommands[1].id=='CRAFT:monitor-job' and monitorCommands[1].generation==3,'monitor command carries selected job and revision')
monitor.store:setState({filter='attention'})
check(#monitor.orderList.items==0 and not monitor.buttons.resume.enable,'empty filter clears stale actionable selection')
monitor.store:setState({filter='open'})
shell:selectTab('warehouse')
local oldMonitor=monitor.store.value.snapshot
monitorCallbacks[1]({rows={}})
check(monitorCount==0 and monitor.store.value.snapshot==oldMonitor,'hidden monitor releases interest and rejects late callbacks')
if ERTestTranslations then
    check(shell.tabButtons.warehouse.title==getText('IGUI_EmberRoutesProbe_Settlement_tab_warehouse'),'real language tab label')
    check(not shell.title:find('IGUI_',1,true),'management title translated')
end
check(Dashboard.open(actor,entry.id)==shell and wareCount==1,'same settlement open reuses shell without duplicate watch')
page:nextPage() page.itemList.selected=7 page:selectItem(page.itemList.items[7].item.value) page.itemList:setYScroll(-100)
local selected=page.store.value.selection.fullType
page:help() local help=page.helpModal
page.categories.expanded=true page.controls.sort.expanded=true page.search.focused=true
local previousRows=page.store.value.snapshot
check(Logistics.open(actor,entry.id)==shell,'legacy logistics open targets same shell')
local log=shell.pages.logistics
check(shell.activeTab=='logistics' and wareCount==0 and logCount==1 and stops==0,'switch releases warehouse interest without stopping logistics')
check(not help.added and not page.helpModal and cleared>0 and not page.search.focused,'switch releases help, marker and text focus')
check(page.categories.popupHidden and page.controls.sort.popupHidden,'native combo popups explicitly removed')
wareCallbacks[1](warehouseSnapshot)
check(page.store.value.snapshot==previousRows,'late hidden-page callbacks cannot update state')
local warehouseModule=package.loaded['EmberRoutesProbe/WarehouseIndex']
warehouseSnapshot={state='UPDATING',rows={},counts={}}
shell:selectTab('warehouse')
check(wareCount==1 and logCount==0 and #page.itemList.items==0,'returning pending scan does not expose stale quantities')
warehouseSnapshot={state='READY',rows=rows,counts={loaded=1,containers=1,items=135,unloaded=0,private=0,missing=0,limited=0},revision=2}
wareCallbacks[#wareCallbacks](warehouseSnapshot)
check(page.actualPage==2 and page.store.value.selection.fullType==selected and page.itemList.selected==7,'ready restores page and stable item selection')
check(page.itemList:getYScroll()==-100,'ready restores valid scroll anchor')
page.search:setText('Item067')
shell:selectTab('logistics') shell:selectTab('warehouse')
check(page.search:getText()=='Item067' and #page.itemList.items==1,'query survives tab round trip')
shell:selectTab('crafting') local craft=shell.pages.crafting
local browser=craft.views.recipes
check(craft.selectedView=='recipes' and craftCount==1 and catalogCount==1 and previewCount==1,'only browser owns catalog, preview and status')
check(browser.draft.platform.visible and browser.draft.run.enable,'surface recipe selects an eligible registered default')
local surfaceViewport=browser.draft.list.height
browser:change({recipeId='Base.SawLogs'})
check(not browser.draft.platform.visible and browser.draft.run.enable,'in-hand recipe omits all platform controls')
check(browser.draft.list.height>surfaceViewport and not browser.draft.surfaceHelp.visible,'in-hand layout reclaims facility space and hides registration action')
check(browser.draft.list.items[1].item.value.fullType=='Base.Plank','output uses the actual product icon identity')
local function draftLabels()
 local values={} for _,row in ipairs(browser.draft.list.items) do values[#values+1]=row.text end return table.concat(values,'\n')
end
check(draftLabels():find('RawLog',1,true) and draftLabels():find('Handsaw',1,true),'material and reusable tool slots have names')
local inputRow
for _,row in ipairs(browser.draft.list.items) do if row.item.value.kind=='input' and row.item.value.slot==1 then inputRow=row.item.value end end
browser.draft:activate(inputRow)
check(draftLabels():find('Saw2',1,true),'clicking one input exposes its complete alternative list')
browser.draft.list:setYScroll(-100)
local iconY=0 for _,row in ipairs(browser.draft.list.items) do iconY=browser.draft.list:doDrawItem(iconY,row) end
browser.draft.list:setYScroll(0)
browser:focusList(browser.draft.list) browser.draft.list:onKeyPress(Keyboard.KEY_DOWN)
check(shell.activeTab=='crafting','keyboard navigation does not activate warehouse links')
browser.search.focused=true
check(not browser.grid:isKeyConsumed(Keyboard.KEY_LEFT),'recipe grid does not steal arrow keys while editing search') browser.search.focused=false
local firstPreview=previewCallbacks[#previewCallbacks]
browser.draft.quantity:setText('4')
check(browser.store.value.quantity==4 and browser.draft.summary:find('2',1,true),'quantity changes recompute complete batches')
firstPreview({state='BLOCKED',conditions={'MATERIALS_UNAVAILABLE'},counts={}})
check(browser.store.value.preview.state=='READY','late previous-quantity preview cannot overwrite current draft')
local oldSameKey=previewCallbacks[#previewCallbacks]
browser.draft.quantity:setText('1') browser.draft.quantity:setText('4')
oldSameKey({state='BLOCKED',conditions={'MATERIALS_UNAVAILABLE'},counts={}})
check(browser.store.value.preview.state=='READY','A-B-A quantity changes reject the earlier identical-key request')
local previousSearch=catalogCallbacks[#catalogCallbacks]
browser:change({search='Saw',page=1})
previousSearch({rows={},categories={},page=1,pages=1,total=0,loading=false})
check(#browser.grid.cells==1 and browser.grid.cells[1].row.id=='Base.SawLogs','recipe search filters cards')
browser:change({category='Carving',page=1})
check(#browser.grid.cells==0 and browser.store.value.recipeId=='Base.SawLogs','empty filter does not erase prepared order')
browser:change({search='',category=false,page=1})
local draftId=browser.store.value.recipeId local quantity=browser.store.value.quantity
craft:selectView('orders') local orders=craft.views.orders
check(craftCount==1 and catalogCount==0 and previewCount==0,'orders release hidden catalog and preview')
local displayOrder={id='machine-only-order-id',recipeId='Base.SawLogs',recipeName='Saw logs',state='RUNNING',phase='PLANNING',surfaceRequired=false,requested=1,target=3,produced=0,delivered=0}
local function orderSnapshot() return {workers={{id='worker',name='Worker',busy=displayOrder.state=='RUNNING',order=displayOrder}},surfaces={}} end
orders.store:setState({snapshot=orderSnapshot()})
displayOrder={id='machine-only-order-id',recipeId='Base.SawLogs',recipeName='Saw logs',state='PAUSED',phase='PLANNING',surfaceRequired=false,requested=1,target=3,produced=0,delivered=0,resumable=true}
orders.store:setState({snapshot=orderSnapshot()})
check(orders.workerList.items[1].item.visual.state=='paused' and orders.buttons.resume.enable,'same-phase pause updates independent order controls')
local following=orderSnapshot()
following.workers[1].busy=true following.workers[1].orderBusy=false
orders.store:setState({snapshot=following})
check(orders.buttons.resume.enable and orders.buttons.resume.visible~=false and orders.buttons.stop.visible==false,
    'following with paused production exposes resume instead of production pause')
check(orders.buttons['return'].enable,'paused production can request return while another body task is active')
check(orders.detailCard.visual.title[1]=='Saw logs','order title does not append a misleading repetition count')
craft:selectView('recipes') browser=craft.views.recipes
check(browser.store.value.recipeId==draftId and browser.store.value.quantity==quantity and catalogCount==1 and previewCount==1,'returning from orders preserves search, recipe and quantity')
browser:command('run')
check(craft.selectedView=='orders' and craftCommands[#craftCommands].recipeId=='Base.SawLogs' and craftCommands[#craftCommands].quantity==4,'new order carries explicit recipe/quantity then opens orders')
craft:selectView('recipes') browser=craft.views.recipes
browser.draft.quantity:setText('0')
check(not browser.draft.run.enable,'invalid target cannot submit an order')
browser.draft.quantity:setText('1')
local oldCatalog=catalogCallbacks[#catalogCallbacks] local oldPreview=previewCallbacks[#previewCallbacks]
shell:selectTab('warehouse')
oldCatalog({rows={},categories={},page=1,pages=1,loading=false}) oldPreview({state='BLOCKED',conditions={},counts={}})
check(craftCount==0 and catalogCount==0 and previewCount==0 and browser.store.value.preview.state=='READY','hidden browser releases every query and ignores late results')
for i=1,9 do shell:nextTab(1) check(wareCount+logCount+craftCount+monitorCount==1,'exactly one page subscription through repeated switches') end
shell:onKeyPress(Keyboard.KEY_NEXT)
check(shell.activeTab=='warehouse','keyboard PageDown cycles only the new primary tabs')
shell:selectTab('logistics')
log.workerList:onJoypadDirLeft()
check(shell.activeTab=='orders','controller edge returns from legacy configuration to monitor')
shell:selectTab('warehouse')
page:focusList(page.itemList) page.itemList:onJoypadDirRight()
check(shell.activeTab=='warehouse' and page.focusedList==page.sourceList,'controller inner edge keeps intra-page navigation')
page.sourceList:onJoypadDirRight()
check(shell.activeTab=='orders','controller other outer edge opens order monitor')
local oldLogState=log.store.value.snapshot
shell:selectTab('warehouse')
logCallbacks[#logCallbacks](logisticsSnapshot)
check(log.store.value.snapshot==oldLogState and stops==0,'hidden logistics ignores callbacks and keeps business running')
shell:close() shell:close()
check(wareCount==0 and logCount==0 and craftCount==0 and not shell.added and stops==0,'idempotent close releases all UI watches only')
-- watch callback can close while watch is still obtaining its release handle.
onWatch=function() root={} end
local failed,reason=Dashboard.open(actor,entry.id)
-- Initial receive precedes world change; the next validity check closes normally.
check(failed~=nil,'shell was valid at initial receive') failed:update()
check(failed.disposed and wareCount==0,'world change closes and releases active interest')
onWatch=nil
-- Close synchronously from inside initial receive, before watch returns.
local originalProject=EmberRoutesWarehousePage.project
local closedDuringWatch
EmberRoutesWarehousePage.project=function(self,...)
    originalProject(self,...)
    closedDuringWatch=self.owner self.owner:close()
end
failed,reason=Dashboard.open(actor,entry.id)
check(not failed and reason=='UI_SUBSCRIBER_ERROR' and wareCount==0 and not closedDuringWatch.added,'synchronous initial callback close releases returned handle without remounting window')
EmberRoutesWarehousePage.project=originalProject
shell=Logistics.open(actor,entry.id)
logCallbacks[#logCallbacks]({reason='WORLD_RESET',workers={}})
check(shell.disposed and logCount==0,'world reset service event closes shell')
shell=Dashboard.open(actor,entry.id)
local changed=Dashboard.open(actor,'other')
check(shell.disposed and changed~=shell and wareCount==1,'different settlement disposes previous shell') changed:close()
shell=Dashboard.open(actor,entry.id) permitted=false shell:update()
check(shell.disposed and wareCount==0,'access loss closes active shell') permitted=true
shell=Dashboard.open(actor,entry.id) currentActor={} shell:update()
check(shell.disposed and wareCount==0,'player replacement closes active shell') currentActor=actor
for _,size in ipairs({{1280,720,28},{1920,1080,20},{2560,1440,24},{3840,2160,32}}) do
    sw,sh,fh=size[1],size[2],size[3]
    shell=Dashboard.open(actor,entry.id) page=shell.pages.warehouse
    check(shell.width<sw and shell.height<sh and page.itemList.height>fh,'warehouse list retains usable viewport at screen/font size')
    check(page.sourceList.y+page.sourceList.height<=page.pageY,'warehouse list does not overlap pager')
    shell:selectTab('logistics') log=shell.pages.logistics
    check(log.workerList.height>fh*2 and log.buttons.retry.y>=log.workerList.y+log.workerList.height,'logistics actions retain independent viewport')
    check(log.modes[1].boxSize==fh and log.modes[2].boxSize==fh,'native tickboxes remain font-sized')
    shell:selectTab('crafting') craft=shell.pages.crafting
    browser=craft.views.recipes
    check(browser.draft.list.height>fh and browser.draft.run.y>=browser.draft.list.y+browser.draft.list.height,'draft actions remain below scrollable material viewport')
    craft:selectView('orders') orders=craft.views.orders
    check(orders.workerList.height>fh*2,'order viewport remains usable')
    shell:selectTab('orders')
    local monitor=shell.pages.orders
    check(monitor.orderList.height>fh*2 and monitor.details.list.width>0,'monitor retains a usable viewport across supported screen/font sizes')
    if monitor.narrow then
        monitor.buttons.details.onclick()
        check(monitor.store.value.detailMode and monitor.orderList.visible==false and monitor.details.list.visible,
            'narrow monitor switches from list to details without squeezing columns')
        monitor.buttons.details.onclick()
        check(monitor.orderList.visible and monitor.details.list.visible==false,'narrow monitor returns to original job list')
    end
    shell:selectTab('crafting')
    local manager=getTextManager
    getTextManager=function() error('drawing must not remeasure text') end
    shell:prerender() log:prerender() craft:prerender()
    for _,list in ipairs({page.itemList,page.sourceList,log.workerList,log.details.list,orders.workerList,orders.details}) do
        local y=0 for _,row in ipairs(list.items) do y=list:doDrawItem(y,row) end
    end
    getTextManager=manager shell:close()
end
shell=Dashboard.open(actor,entry.id,'crafting') browser=shell.pages.crafting.views.recipes
browser:change({recipeId='Base.SawLogs',quantity=1})
browser:change({preview={state='READY',conditions={},counts={[0]={available=0,required=1},[1]={available=1,required=1}},
 chain={nodes={{recipeId='precursor',recipeName='Precursor',product='Base.Log',requested=1,surface=false},
 {recipeId='Base.SawLogs',recipeName='Saw logs',product='Base.Plank',requested=3,surface=true}}}}})
local precursorRow
for _,row in ipairs(browser.draft.list.items) do if row.item.value.kind=='input' and row.item.value.slot==0 then precursorRow=row end end
check(precursorRow.item.value.precursor and not precursorRow.item.value.missing and precursorRow.item.visual.sub:find('0 / 1',1,true),'planned supply keeps zero actual stock and uses a distinct precursor state')
check(browser.draft.run.enable and #browser.draft.list.items>=7,'complete chain permits ordering and displays its route')
local chainRows={}
for _,row in ipairs(browser.draft.list.items) do
    if row.item.value.kind=='chain_step' then chainRows[#chainRows+1]=row.item.value end
end
check(#chainRows==2 and chainRows[1].surfaceBadge==getText('IGUI_EmberRoutesProbe_Crafting_badgeHand')
 and chainRows[2].surfaceBadge==getText('IGUI_EmberRoutesProbe_Crafting_badgeSurface'),
 'boolean chain surface requirements render hand and platform badges without aborting preview')
browser:change({preview={state='BLOCKED',conditions={'NPC_RECIPE_UNKNOWN'},counts={},
 blocker={recipeId='precursor',recipeName='Precursor',surfaceId='precursor-surface'}}})
browser.draft.teach.onclick()
check(craftCommands[#craftCommands].recipeId=='precursor' and craftCommands[#craftCommands].surface=='precursor-surface'
 and browser.store.value.recipeId=='Base.SawLogs','teaching a missing precursor targets it without changing the selected final recipe')
-- Exercise the actual public dialogs, rather than only the old hidden pages.
local publicCalls={} local publicRevision=2 local request=0
package.loaded['EmberRoutesProbe/ContainerRegistry'].id=function() request=request+1 return 'request-'..request end
package.loaded['EmberRoutesProbe/CraftSurfaces']={list=function() return {{id='surface',x=1,y=2,z=0}} end}
package.loaded['EmberRoutesProbe/PublicWork']={
 available=function() return true end,
 rule=function() return {minimum=50,batch=12} end,
 create=function(_,scope,recipe,n,surface,token)
  publicCalls[#publicCalls+1]={scope=scope,recipe=recipe,n=n,surface=surface,token=token} return 'ORDER_CREATED'
 end,
 saveRule=function() return 'RULE_SAVED' end,
 priorities=function() return {crafting=1,hauling=4,revision=publicRevision} end,
 setPriorities=function(_,scope,id,values,revision)
  check(id=='worker' and values.crafting==1 and values.hauling==4 and revision==2,'priority save carries stable NPC and expected revision')
  publicRevision=3 return 'PRIORITY_SAVED'
 end}
shell:selectTab('orders')
monitor=shell.pages.orders monitor.buttons.crafting.onclick()
local dialog=shell.publicDialog
check(dialog and not dialog.npcId and catalogCount==1,'public dialog has no NPC assignment and owns one catalogue subscription')
check(dialog.minimum:getText()=='50' and dialog.batch:getText()=='12','dialog loads existing stock threshold and fixed batch')
local token=dialog.requestId dialog.quantity:setText('7')
check(dialog.requestId~=token,'quantity change renews idempotent draft token')
dialog:submitOrder()
check(#publicCalls==1 and publicCalls[1].n==7 and publicCalls[1].scope==entry.id,'public submit uses only demand and scope')
check(not shell.publicDialog and catalogCount==0,'successful submission closes dialog and releases catalogue')
monitor.buttons.logistics.onclick()
local priority=shell.priorityDialog
check(priority and priority.fields.crafting.selected==2 and priority.fields.hauling.selected==5,'priority editor restores per-NPC 0–4 values')
priority.save.onclick()
check(priority.revision==3,'priority editor refreshes optimistic revision after save')
shell:selectTab('warehouse')
check(not shell.priorityDialog,'switching tabs disposes priority popup')
shell:close()
check(wareCount==0 and logCount==0 and stops==0,'all test windows release watches and never stop business')
print('PASS '..checks..' unified shell/page lifecycle/layout checks; native host mocked, game renderer NOT RUN')
-- Optional visual QA export: real pages and prepared draw data, synthetic business snapshots.
function ERSettlementPreview(tab,height)
    sw,sh,fh=1280,960,height
    local shell=Dashboard.open(actor,entry.id,(tab=='publicOrder' or tab=='priorities') and 'orders' or tab)
    shell.x=0 shell.y=0
    if tab=='publicOrder' then
        shell:openPublicOrder({recipeId='Base.SawLogs',recipeName='Saw logs'})
        local dialog=shell.publicDialog dialog.x=0 dialog.y=0 return dialog
    elseif tab=='priorities' then
        shell:openPriorities() local dialog=shell.priorityDialog dialog.x=0 dialog.y=0 return dialog
    end
    if tab=='crafting' then
        local browser=shell.pages.crafting.views.recipes
        browser:change({recipeId='Base.SawLogs',quantity=1})
        browser:change({preview={state='READY',conditions={},counts={[0]={available=0,required=1},[1]={available=1,required=1}},
            chain={nodes={{recipeId='precursor',recipeName='Precursor',product='Base.Log',requested=1,surface=false},
            {recipeId='Base.SawLogs',recipeName='Saw logs',product='Base.Plank',requested=3,surface=true}}}}})
    elseif tab=='logistics' then
        package.loaded['EmberRoutesProbe/ContainerRegistry'].describe=function(id)
            if id=='a' then return {containerType='crate',x=3571,y=10897,z=0} end
            if id=='b' then return {containerType='crate',x=3575,y=10898,z=0} end
        end
        local page=shell.pages.logistics
        page.store:setState({snapshot={running=true,intake=true,tidy=true,workers={{id='worker',reason='WORKING',state='RUNNING',
            taskId='machine-only',producer='LOGISTICS',sourceMode='INTAKE',phase='DELIVER',delivered=2,total=6,source='a',destination='b'}}}})
    elseif tab=='warehouse' then
        local page=shell.pages.warehouse local samples={}
        for i,id in ipairs({'Base.Hammer','Base.Nails','Base.TinnedBeans','Base.CordlessPhone'}) do
            page.itemNames[id]=ERTestTranslations and ERTestTranslations['TEST_ItemName_'..id] or id
            samples[i]={fullType=id,node='other',count=i*8,sources={{id='sample',x=3575,y=10898,z=0,count=i*8}}}
        end
        page:receive({state='READY',revision=2,rows=samples,counts={loaded=3,containers=4,items=80,unloaded=1,private=0,missing=0,limited=0}})
    end
    return shell
end
