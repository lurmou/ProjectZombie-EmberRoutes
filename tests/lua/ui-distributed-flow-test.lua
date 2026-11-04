ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local n=0
local function check(v,m) assert(v,m) n=n+1 end
local fixture=ERSettlementPreview('warehouse',20,1280,900)
local actor=fixture.actor fixture:close()
local D=require 'EmberRoutesProbe/SettlementDashboard'
local shell=assert(D.open(actor,'settlement','warehouse'))
local C=package.loaded['EmberRoutesProbe/CraftingService']
local queries={}
C.watchCatalog=function(_,_,q,cb)
 queries[#queries+1]=q
 local rows=q.productType=='Base.Plank' and {{id='one',name='First plank recipe',product='Base.Plank',supported=true},{id='two',name='Second plank recipe',product='Base.Plank',supported=true}} or {}
 cb({rows=rows,categories={},page=1,pages=1,total=#rows,loading=false})
 return function() end
end
check(shell:selectTab('crafting',{returnTab='warehouse',filterProduct='Base.Plank'}),'product jump')
local page=shell.pages.crafting local browser=page.views.recipes
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
check(shell.activeTab=='warehouse' and not page.returnContext,'successful submit returns to warehouse')
local monitor=package.loaded['EmberRoutesProbe/OrderMonitorService']
local row={id='ORDER:unclaimed',orderId='unclaimed',generation='ORDER:9',kind='ORDER',title='Public fork',state='WAITING',canCancel=true}
monitor.status=function() return {rows={row}} end
local called
monitor.command=function(_,_,id,generation,action) called={id,generation,action} return 'CANCELLED' end
shell:selectTab('crafting',{view='orders'})
local orders=page.views.orders
check(#orders.unclaimed.list.items==1,'unclaimed public order has a real section')
orders.unclaimedSelection=row orders:project(orders.store.value,{selection=true})
check(orders.buttons['return'].enable,'selected public order can cancel')
orders:command('return')
check(called[1]==row.id and called[2]=='ORDER:9' and called[3]=='return','cancel preserves service generation')
local overview=package.loaded['EmberRoutesProbe/WorkOverviewService']
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
