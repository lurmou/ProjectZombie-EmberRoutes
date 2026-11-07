ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local n=0
local function check(v,m) assert(v,m) n=n+1 end
local fixture=ERSettlementPreview('warehouse',20,1280,900)
local actor=fixture.actor fixture:close()
local D=require 'EmberRoutesProbe/UI/SettlementDashboard'
local shell=assert(D.open(actor,'settlement','warehouse'))
local C=package.loaded['EmberRoutesProbe/Crafting/CraftingService']
local queries={}
C.watchCatalog=function(_,_,q,cb)
 queries[#queries+1]=q
 local rows=q.productType=='Base.Plank' and {{id='one',name='First plank recipe',product='Base.Plank',supported=true},{id='two',name='Second plank recipe',product='Base.Plank',supported=true}} or {}
 cb({rows=rows,categories={},page=1,pages=1,total=#rows,loading=false})
 return function() end
end
check(shell:selectTab('crafting',{returnTab='warehouse',filterProduct='Base.Plank'}),'product jump')
local page=shell.pages.crafting local browser=page.views.recipes
local stepper=browser.draft.stepper
local before=browser.store.value.quantity
check(not stepper:onMouseWheel(-1) and browser.store.value.quantity==before,'unfocused quantity does not hijack scrolling')
browser.draft.quantity:setText('0')
check(browser.store.value.quantity==false,'invalid input is rejected rather than silently changed')
browser.draft.quantity:setText('1')
browser:change({quantity=3})
check(browser.draft.quantity:getText()=='3','state-driven quantity updates the shared input without a second projection')
browser:change({quantity=1})
check(#browser.store.value.catalog.rows==2 and not browser.store.value.recipeId and browser.recipe==nil,'multiple recipes filtered without draft')
check(queries[1].productType=='Base.Plank','filter installed before initial catalog watch')
page:returnWarehouse()
check(shell.activeTab=='warehouse' and not page.returnContext,'explicit cancel returns and destroys context')
check(shell:selectTab('crafting',{returnTab='warehouse',filterProduct='Base.Impossible'}),'no recipe jump')
check(#browser.store.value.catalog.rows==0 and not browser.store.value.recipeId,'no recipe does not create draft')
check(browser.grid.empty==getText('IGUI_EmberRoutesProbe_Distributed_noRecipe'),'no recipe explanation')
page:returnWarehouse()
shell:selectTab('crafting',{returnTab='warehouse',filterProduct='Base.Plank'})
browser:command('run','Base.SawLogs','surface')
check(shell.activeTab=='crafting','successful submit keeps crafting context')
check(not shell:selectTab('crafting',{view='orders'}),'retired orders view rejected')
local monitor=package.loaded['EmberRoutesProbe/Warehouse/OrderMonitorService']
local row={id='ORDER:unclaimed',orderId='unclaimed',generation='ORDER:9',kind='ORDER',title='Public fork',state='WAITING',canCancel=true}
local called
monitor.command=function(_,_,id,generation,action) called={id,generation,action} return 'CANCELLED' end
local pending={key=row.id,title=row.title,state='waiting',category='crafting',row=row}
local fixtureOwner=shell.pages.warehouse
local Queue=require('EmberRoutesProbe/UI/WorkQueue')
local q=Queue.new(fixtureOwner,{x=0,y=0,width=400,height=200},function(w) return w.category=='crafting' end)
q:set({works={pending}})
check(#q.info.list.items==1,'unclaimed production lives in category queue')
q.selectedId=row.id q:set({works={pending}})
check(#q.info.list.items>1,'selected queue item exposes responsibility details')
local result=require('EmberRoutesProbe/Work/WorkCommandAdapter').command(actor,'settlement',row,'return')
check(result=='CANCELLED' and called[1]==row.id and called[2]=='ORDER:9' and called[3]=='return','relocated command preserves identity/generation')
local overview=package.loaded['EmberRoutesProbe/Work/WorkOverviewService']
local current={title='True current work',state='working',row={kind='FIELD_WORK',id='FIELD_WORK:real',npcId='worker',jobId='real',generation=1}}
overview.status=function() return {works={current},byNpc={worker=current},alerts={},counts={},problems={}} end
shell:selectTab('personnel')
local personnel=shell.pages.personnel
local selected=personnel.store.value.selected
local priorities=selected.priorities
check(selected.workLine=='True current work · '..getText('IGUI_EmberRoutesProbe_Distributed_working'),'matrix and details share actual current work')
check(personnel.currentWork==current,'details use same presenter work object')
personnel.workFilters.onSelect('idle')
check(#personnel.matrixList.items==0 and personnel.store.value.selected==selected and selected.priorities==priorities,'filter changes visibility only, preserving selection and priorities')
current.state='paused'
personnel:refresh()
check(#personnel.matrixList.items==0,'paused is not idle')
personnel.workFilters.onSelect('all')
check(#personnel.matrixList.items==1,'all includes paused')
shell:close()
print('ui-distributed-flow: '..n..' PASS; production views, mocked ISUI/services')
