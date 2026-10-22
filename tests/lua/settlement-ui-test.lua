if not ISCollapsableWindow then dofile('tests/lua/storage-panel-test.lua') end
local Base=ISCollapsableWindow
ISPanel=Base package.loaded['ISUI/ISPanel']=true
function Base:unfocus() self.focused=false end
ISTextEntryBox=Base:derive('TestTextEntry')
function ISTextEntryBox:new(value,x,y,w,h)
    local entry=Base.new(self,x,y,w,h) entry.value=value return entry
end
function ISTextEntryBox:getText() return self.value end
function ISTextEntryBox:setPlaceholderText(text) self.placeholderText=text end
function ISTextEntryBox:isFocused() return self.focused==true end
function ISTextEntryBox:setText(value) self.value=value if self.onTextChangeFunction then self.onTextChangeFunction(self.target,self) end end
ISComboBox=Base:derive('TestCombo')
function ISComboBox:new(x,y,w,h,target,callback)
    local combo=Base.new(self,x,y,w,h) combo.options={} combo.selected=0 combo.target=target combo.onChange=callback return combo
end
function ISComboBox:addOption(value) self.options[#self.options+1]=value if self.selected==0 then self.selected=1 end end
function ISComboBox:setToolTipMap(value) self.tooltip=value end
package.loaded['ISUI/ISTextEntryBox']=true package.loaded['ISUI/ISComboBox']=true
ISModalDialog=Base:derive('TestModal')
function ISModalDialog:new(x,y,w,h,message,yesno,target,callback)
    local modal=Base.new(self,x,y,w,h) modal.text=message modal.target=target modal.onclick=callback return modal
end
local speedChanges=0
function ISModalDialog:destroy() speedChanges=speedChanges+1 self:removeFromUIManager() end
function ISModalDialog:setVisible(value) self.visible=value end
package.loaded['ISUI/ISModalDialog']=true
Joypad.YButton,Joypad.LBumper,Joypad.RBumper=4,5,6
Joypad.LStickButton,Joypad.RStickButton=7,8
Keyboard.KEY_LEFT,Keyboard.KEY_RIGHT=6,7
Keyboard.KEY_TAB=8
local sw,sh,fh=1920,1080,16
local oldName=getItemNameFromFullType
function getItemNameFromFullType(id)
    return (ERTestTranslations and ERTestTranslations['TEST_ItemName_'..id]) or oldName(id)
end
function getCore() return {getScreenWidth=function() return sw end,getScreenHeight=function() return sh end} end
function getTextManager() return {getFontHeight=function() return fh end,MeasureStringX=function(_,_,s) return #s*fh*0.5 end} end
local saves,watches,refreshes=0,0,0
local entry={id='settlement-ui-test',name='Test settlement',revision=1,areas={{x=0,y=0,w=20,h=20}}}
local actor={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
    getIndex=function() return 0 end,getPlayerNum=function() return 0 end,getJoypadBind=function() return -1 end}
local entries={[entry.id]=entry}
local ledger={authorized=function(a) return a==actor end,list=function() return {entry} end,
    get=function(id) return entries[id] end,view=function(_,id) return entries[id] end,
    data=function() return {entries=entries} end,commit=function(_,id,name,area)
        if not id and not area then return nil,'INVALID_BOUNDS' end
        saves=saves+1 return entry,'SETTLEMENT_SAVED'
    end}
package.loaded['EmberRoutesProbe/SettlementLedger']=ledger
local rows={}
for i=1,135 do rows[i]={fullType=i==1 and 'Base.Hammer' or 'Mod.Item'..i,node=i==1 and 'tools' or 'other',count=i,
    sources={{id='source-one',x=5,y=6,z=1,count=i}}} end
local snapshot={state='READY',rows=rows,counts={loaded=1,containers=2,unloaded=1,private=0,missing=0,limited=0,items=100},revision=1}
local listener
package.loaded['EmberRoutesProbe/WarehouseIndex']={watch=function(_,fn)
    watches=watches+1 listener=fn fn(snapshot)
    return function() watches=watches-1 end
end,refresh=function() refreshes=refreshes+1 end}
local mouseX,mouseY=2,3
function getMouseX() return mouseX end function getMouseY() return mouseY end
function screenToIsoX(_,x) return x end function screenToIsoY(_,_,y) return y end
function getCell() return {getGridSquare=function() return {} end} end
local highlight=0
function addAreaHighlightForPlayer() highlight=highlight+1 end
local Selector=require 'EmberRoutesProbe/UI/SettlementSelector'
-- Content regression only; settlement-tabs-test exercises the real owning shell.
local Page=require 'EmberRoutesProbe/UI/WarehousePage'
local Dashboard={open=function(a,id)
    local h=fh local p=math.ceil(h*0.6)
    local width,height=math.min(sw*0.90,h*58),math.min(sh*0.96,h*38)
    local owner={actor=a,entry=entries[id],valid=function() return true end}
    local panel=Page:new(owner,{x=0,y=0,width=width-p*2,height=height-24-p*2-h-p-p/2})
    function owner:close() panel:dispose() panel:removeFromUIManager() end
    panel:initialise() panel:addToUIManager() panel:activate() return panel
end}
local n=0 local function check(value,why) n=n+1 assert(value,why) end
local selector=Selector.open(actor,nil)
check(selector.initialised and selector.parentCreated and selector.nameEntry.initialised,'selector native lifecycle and controls')
selector:onMouseDownOutside() mouseX,mouseY=7,8 selector:onMouseMoveOutside() selector:onMouseUpOutside()
check(selector.area.x==2 and selector.area.y==3 and selector.area.w==6 and selector.area.h==6,'drag computes inclusive corners without writing ledger')
local selected=selector.area
mouseX,mouseY=selector.x+selector.nameEntry.x+1,selector.y+selector.nameEntry.y+1
selector:onMouseDownOutside() selector:onMouseMoveOutside() selector:onMouseUpOutside()
check(selector.area==selected and not selector.dragging,'clicking name field cannot replace world selection')
selector:prerender()
check(saves==0 and highlight==1,'preview highlights one rectangle and does not commit')
selector:close() check(saves==0,'cancel does not create settlement')
selector=Selector.open(actor,nil)
selector.cursorX,selector.cursorY=2,2 selector:onJoypadDown(Joypad.AButton)
selector:onJoypadDirRight() selector:onJoypadDirDown() selector:onJoypadDown(Joypad.AButton)
check(selector.area.w==2 and selector.area.h==2,'controller chooses two corners')
selector:apply() check(saves==1 and not selector.added,'apply commits once and disposes selection view')
local panel=Dashboard.open(actor,entry.id)
check(panel.width<sw and panel.height<sh and panel.search.placeholderText~=nil,'compact panel and native search placeholder')
check(panel.itemList.emberColumns.icon>0 and panel.itemList.items[1].item.visual.quantity=='1','item icons and quantity have independent columns')
check(not table.concat(panel.sourceList.items[1].item.visual.lines,''):find('source-one',1,true)
    and panel.sourceList.items[1].tooltip:find('source-one',1,true),'technical source ID belongs to tooltip rather than visible name')
panel:help() local modal=panel.helpModal panel:help()
check(modal.added and panel.helpModal==modal and #modal.text>0,'help opens one native modal rather than an NPC speech bubble')
modal:destroy() modal.onclick(panel) check(panel.helpModal==nil and speedChanges==0,'dismissing read-only help releases its reference without vanilla speed reset')
check(panel.added and panel.parentCreated and watches==1,'dashboard attaches exactly one read subscription')
check(#panel.itemList.items==60 and panel.pages==3,'visible item rows paginated without truncating query')
check(not panel.controls.clear.enable and not panel.previousButton.enable and panel.nextButton.enable and panel.details.locate.enable,
    'button enabled states reflect current search/page/source selection')
panel.itemList:onKeyPress(Keyboard.KEY_TAB)
check(panel.focusedList==panel.sourceList and not panel.itemList:isKeyConsumed(Keyboard.KEY_DOWN),'only focused list consumes navigation')
local located=0
panel.locator.locate=function(_,id) located=located+1 return {x=5,y=6,z=1},'SOURCE_MARKED' end
panel.sourceList:onKeyPress(Keyboard.KEY_RETURN)
check(located==1 and panel.notice:find('5, 6',1,true),'source Enter routes through validated locator service and displays position')
panel.search.focused=true panel.sourceList:onKeyPress(Keyboard.KEY_RETURN)
check(located==1 and not panel.sourceList:isKeyConsumed(Keyboard.KEY_RETURN),'search focus prevents list input from leaking through')
panel.search.focused=false panel.controls.sort.expanded=true
check(not panel.sourceList:isKeyConsumed(Keyboard.KEY_DOWN),'expanded combo owns navigation instead of either list')
panel.controls.sort.expanded=false panel.sourceList:onKeyPress(Keyboard.KEY_TAB)
panel.controls.sort.selected=4 panel:queryChanged()
check(panel.itemList.items[1].item.value.count==135,'quantity dropdown sorts cached read model without a stock refresh')
panel.controls.sort.selected=1 panel:queryChanged()
panel.itemList:onJoypadDown(Joypad.RStickButton)
check(panel.controls.sort.selected==2,'controller can cycle sort without a mouse')
panel.controls.sort.selected=1 panel:queryChanged()
panel:nextPage() check(panel.actualPage==2 and watches==1 and refreshes==0,'paging touches cached view only')
panel.itemList:onKeyPress(Keyboard.KEY_RIGHT)
check(panel.actualPage==3 and #panel.itemList.items==15,'keyboard paging reaches every item')
panel.search:setText('Base.Hammer')
check(#panel.itemList.items==1 and panel.pages==1 and refreshes==0,'text input filters snapshot without world reads')
check(#panel.sourceList.items==1 and panel.sourceList.items[1].item.value.z==1,'source pane preserves floor/position')
check(panel.controls.clear.enable,'search enables its clear action')
panel:clearSearch() check(panel.search:getText()=='' and #panel.itemList.items==60 and not panel.controls.clear.enable,'clear search resets page and cached query')
panel.search:setText('Base.Hammer')
listener({state='UPDATING',rows={},counts={}})
check(#panel.itemList.items==0 and #panel.sourceList.items==0,'invalidated snapshot clears both panes')
check(not panel.details.locate.enable and not panel.refreshButton.enable,'initial pending disables locate and duplicate refresh')
snapshot.rows[67].sources={{id='changed-source',x=5,y=6,z=1,count=67}}
listener(snapshot) panel.search:setText('') panel:nextPage()
panel.itemList.selected=7 panel:selectItem(panel.itemList.items[7].item.value)
panel.itemList:setYScroll(-100)
local listItems=panel.itemList.items
local unchangedEntry,changedEntry=listItems[1],listItems[7]
local unchangedLines=unchangedEntry.item.lines
local selectedType=changedEntry.item.value.fullType
local oldSourceEntry=panel.sourceList.items[1]
local summary=panel.summary
local heroLines=panel.details.nameLines
local cells,noteLines=summary.cells,summary.noteLines
local savedValues={}
for i,cell in ipairs(cells) do savedValues[i]=cell.value end
local loadedX,statusY=cells[1].valueX,summary.statusY
listener({state='UPDATING',rows={},counts={},retain=true,dirtySources={['changed-source']=true}})
check(summary.cells==cells and cells[1].value==savedValues[1] and cells[6].value==savedValues[6],
    'ordinary updates keep last completed summary values rather than replacing the statistics line')
check(summary.status=='UPDATING' and summary.noteLines==noteLines and cells[1].valueX==loadedX and summary.statusY==statusY,
    'independent status badge changes without reflowing summary labels or explanation')
check(panel.actualPage==2 and panel.itemList.selected==7 and panel.itemList:getYScroll()==-100,'inventory invalidation preserves page selection and scroll')
check(panel.itemList.items==listItems and panel.itemList.items[1]==unchangedEntry and unchangedEntry.item.lines==unchangedLines,
    'unrelated native rows and cached text remain untouched')
check(panel.itemList.items[7]==changedEntry and changedEntry.item.value.pending and changedEntry.item.value.count==false,
    'dirty row stays in place with unknown quantity instead of an old usable count')
check(panel.sourceList.items[1]==oldSourceEntry and oldSourceEntry.item.value.pending and oldSourceEntry.item.value.count==false,
    'selected source patches in place and marks unknown quantity')
local updatedCounts={}
for key,value in pairs(snapshot.counts) do updatedCounts[key]=value end
updatedCounts.items=updatedCounts.items+1
local updated={state='READY',rows={},counts=updatedCounts,revision=2}
for i,value in ipairs(snapshot.rows) do updated.rows[i]=value end
updated.rows[67]={fullType=selectedType,node='other',count=68,sources={{id='changed-source',x=5,y=6,z=1,count=68}}}
listener(updated)
check(panel.details.nameLines==heroLines,'quantity-only patch reuses selected-item name layout')
check(summary.cells==cells and cells[6].value==tostring(updatedCounts.items) and cells[1].value==savedValues[1],
    'ready result patches changed summary number in the existing cell')
check(summary.status=='READY' and summary.noteLines==noteLines,'ready status does not rebuild unchanged explanation')
check(panel.itemList.items==listItems and panel.itemList.items[7]==changedEntry and changedEntry.item.value.count==68
    and not changedEntry.item.value.pending,'new quantity patches existing row without list reconstruction')
check(panel.store.value.selection.fullType==selectedType and panel.actualPage==2 and panel.itemList:getYScroll()==-100,
    'fresh result preserves browsing location instead of selecting first row')
check(panel.sourceList.items[1]==oldSourceEntry and oldSourceEntry.item.value.count==68,'fresh selected-source quantity updates without remount')
local Cached=require 'EmberRoutesProbe/UI/CachedList'
local ordered,reordered={},{}
for i,entryValue in ipairs(panel.itemList.items) do ordered[i]=entryValue.item.value reordered[i]=entryValue.item.value end
reordered[7],reordered[8]=reordered[8],reordered[7]
local scrollBefore=panel.itemList:getYScroll() local displacedHeight=panel.itemList.items[8].height
local function rowCaption(row) return row.label..'\n'..getText('IGUI_EmberRoutesProbe_Settlement_quantity')..': '..tostring(row.count)..'\n'..row.fullType end
local function rowKey(row) return row.fullType end
Cached.reconcile(panel.itemList,reordered,rowCaption,rowKey,true)
check(panel.itemList.selected==8 and panel.itemList:getYScroll()==scrollBefore-displacedHeight,
    'stable selected row retains its screen offset when neighboring rows reorder')
Cached.reconcile(panel.itemList,ordered,rowCaption,rowKey,true)
local remove={state='READY',rows={},counts=snapshot.counts,revision=3}
for i,value in ipairs(updated.rows) do if i~=67 then remove.rows[#remove.rows+1]=value end end
listener(remove)
check(panel.store.value.selection.fullType~=selectedType and #panel.itemList.items==60,'genuinely removed type leaves no ghost selection')
listener({state='UPDATING',rows={},counts={},retain=false,dirtySources={['changed-source']=true}})
check(cells[1].value=='--' and cells[6].value=='--','permission reset clears old summary values as unknown')
check(#panel.itemList.items==0 and #panel.sourceList.items==0,'permission reset does not retain old visible inventory')
listener(snapshot)
listener({state='ERROR',reason='WORLD_CHANGED',rows={},counts={}})
check(cells[1].value=='--' and summary.status=='ERROR','error or world change never retains old summary totals')
check(#panel.itemList.items==0 and #panel.sourceList.items==0,'world/error boundary clears retained presentation')
check(panel.refreshButton.enable and panel.itemList.emberEmptyLabel==getText('IGUI_EmberRoutesProbe_Settlement_WORLD_CHANGED'),
    'error explains the reason in the list and allows retry')
listener(snapshot)
panel.controls.sort.selected=4 panel:queryChanged() panel:nextPage() panel:nextPage()
local index=#panel.itemList.items panel.itemList.selected=index panel:selectItem(panel.itemList.items[index].item.value)
local anchorType=panel.store.value.selection.fullType
local moved={state='READY',rows={},counts=snapshot.counts,revision=4}
for i,value in ipairs(snapshot.rows) do
    if value.fullType==anchorType then
        moved.rows[i]={fullType=value.fullType,node=value.node,count=999,sources=value.sources}
    else moved.rows[i]=value end
end
listener(moved)
check(panel.actualPage==1 and panel.store.value.page==1 and panel.store.value.selection.fullType==anchorType,
    'quantity reorder follows selected type and synchronizes actual page state')
panel:nextPage() check(panel.actualPage==2,'next page still works after data moved the selected type across pages')
panel.controls.sort.selected=1 panel:queryChanged() listener(snapshot)
panel:refresh() check(refreshes==1,'manual refresh has explicit service boundary')
panel:help() local closingHelp=panel.helpModal
panel:close() check(watches==0 and not closingHelp.added and speedChanges==0,'closing releases subscription and help without changing game speed')
local Presentation=require 'EmberRoutesProbe/UI/ItemPresentation'
local nativeManager=_G.getScriptManager
local nativeTexture=_G.tryGetTexture
local normalTexture,variantTexture={},{}
tryGetTexture=function(name) if name=='Item_variant' then return variantTexture end end
local iconReads=0
getScriptManager=function() return {FindItem=function(_,id)
    iconReads=iconReads+1
    if id=='Missing.Item' then return nil end
    return {getNormalTexture=function() return normalTexture end,getIconsForTexture=function()
        return {isEmpty=function() return false end,get=function() return 'variant' end}
    end}
end} end
local icons=Presentation.new()
check(icons:icon('Base.Hammer')==variantTexture and icons:icon('Base.Hammer')==variantTexture and iconReads==1,'variant names resolve to texture objects and cache by type')
check(icons:icon('Missing.Item')==nil and icons:icon('Missing.Item')==nil and iconReads==2,'missing script icons are cached without creating real items')
icons:clear() icons:icon('Base.Hammer') check(iconReads==3,'closing presentation can discard its icon cache')
getScriptManager=nativeManager
tryGetTexture=nativeTexture
for _,resolution in ipairs({{1280,720,28},{1920,1080,16},{2560,1440,24},{3840,2160,32}}) do
    sw,sh,fh=resolution[1],resolution[2],resolution[3]
    panel=Dashboard.open(actor,entry.id)
    check(panel.itemList.height>fh and panel.itemList.y+panel.itemList.height<=panel.pageY,
        'items fit viewport above footer at target resolution/font')
    check(panel.sourceList.height>fh and panel.sourceList.y+panel.sourceList.height<=panel.pageY,
        'source details retain a usable scroll viewport at target resolution/font')
    local visual=panel.itemList.items[1].item.visual
    local countX=visual.quantityX
    check(countX>=panel.itemList.emberColumns.quantity and panel.itemList.emberColumns.name<countX,
        'item count stays in its reserved column at target resolution/font')
    local manager=getTextManager
    getTextManager=function() error('render must reuse cached text layout') end
    panel:prerender() panel.itemList:doDrawItem(0,panel.itemList.items[1]) panel.sourceList:doDrawItem(0,panel.sourceList.items[1])
    getTextManager=manager
    if ERTestTranslations then
        panel.summary:setValues({loaded='256/256',unloaded=256,private=256,missing=256,limited=256,items=20000})
        local cellWidth=(panel.width-panel.pad*4)/3
        for i,cell in ipairs(panel.summary.cells) do
            local right=cell.x+cellWidth
            assert(cell.valueX+getTextManager():MeasureStringX(UIFont.Small,cell.value)<=right,'summary number must fit its relative column')
        end
        check(panel.summary.statusY+panel.fontHeight*2<=panel.search.y,'summary status note stays above search controls')
    end
    panel:close()
end
if ERTestRuntime then
    WAREHOUSE_TEST_EXPORT={open=function(w,h,font)
        sw,sh,fh=w,h,font
        return Dashboard.open(actor,entry.id)
    end,selector=function() return Selector.open(actor,nil) end,preview=function(w,h,font)
        snapshot={state='READY',rows={},counts={loaded=2,containers=3,unloaded=1,private=0,missing=0,limited=0,items=20},revision=2}
        for i,id in ipairs({'Base.Hammer','Base.Nails','Base.TinnedBeans','Base.CordlessPhone'}) do
            snapshot.rows[i]={fullType=id,node=i==1 and 'tools' or 'other',count=i*2,
                sources={{id='912afe45-source',customName='Storage A',x=10620,y=9620,z=0,count=i},
                    {id='35de624f-source',customName='Storage B',x=10624,y=9622,z=1,count=i}}}
        end
        sw,sh,fh=w,h,font return Dashboard.open(actor,entry.id)
    end}
end
package.loaded['EmberRoutesProbe/LogisticsStore']={view=function() return {intake=true,tidy=true,workers={}} end}
ISContextMenu={getNew=function()
    return {options={},setOptionChecked=function(_,option,value) option.checkMark=value end,addOption=function(self,label,actor,callback,...)
        local option={label=label,callback=callback,args={...}} self.options[#self.options+1]=option return option
    end}
end}
local Menu=require 'EmberRoutesProbe/SettlementMenu'
entry.factionId='local-faction'
ledger.data=function() return {entries=entries,factionId='local-faction'} end
local options={}
local menu={addOption=function(_,label,a,fn,id)
    local option={label=label,id=id,callback=fn} options[#options+1]=option return option
end,addSubMenu=function(_,option,child) option.child=child end}
Menu.fill(actor,menu)
check(#options==3 and options[3].id==entry.id,'owned warehouse has visible menu entry alongside automatic logistics')
check(not options[2].child and options[2].callback~=nil,'logistics opens the unified page without legacy command submenu')
local oldAreas=entry.areas entry.areas={{x=100,y=100,w=3,h=3}} options={}
Menu.fill(actor,menu)
check(#options==2 and options[2].label:find(getText('IGUI_EmberRoutesProbe_Settlement_OUTSIDE_SETTLEMENT'),1,true),'outside warehouse remains discoverable with explicit reason')
entry.areas=oldAreas
print('PASS '..n..' settlement UI lifecycle/input/layout checks; actual ISUI host NOT RUN')
