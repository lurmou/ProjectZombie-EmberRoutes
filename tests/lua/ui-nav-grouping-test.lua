-- Contract change: distributed pages replace demands/orders. The native host is retained.
ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local R=require 'EmberRoutesProbe/UI/PageRegistry'
local D=require 'EmberRoutesProbe/SettlementDashboard'
local fixture=ERSettlementPreview('warehouse',20,1280,900)
local actor=fixture.actor fixture:close()
check(not R.get('demands') and not R.get('orders'),'retired IDs are not registered')
for id,group in pairs({warehouse='warehouse',personnel='personnel',logistics='personnel',crafting='work',policies='settlement',activities='settlement',defense='settlement'}) do
 check(R.getGroup(id)==group,'group '..id)
end
local shell=assert(D.open(actor,'settlement'))
local function only(id)
 check(shell.activeTab==id,'active '..id)
 for key,page in pairs(shell.pages) do
  check((page.active==true)==(key==id),'single active leaf '..key)
  check((page.visible==true)==(key==id),'single visible leaf '..key)
 end
end
only('warehouse')
shell:selectGroup('work') only('crafting')
check(shell.tabButtons.crafting.visible,'crafting registered as work tab')
shell:selectTab('personnel',{npcId='worker'}) only('personnel')
local page=shell.pages.personnel local token=page.activation
check(page.store.value.selected.id=='worker','stable member selection')
for _,req in ipairs({{'orders',{orderId='old'}},{'demands',{problemId='old'}},{'personnel',{npcId='missing'}},{'warehouse',{itemId='item'}},{'missing'}}) do
 check(not shell:selectTab(req[1],req[2]),'invalid jump rejected') only('personnel')
end
shell:selectTab('logistics') only('logistics')
check(not page.active and page.activation==nil and token,'deactivation invalidates token')
shell:selectGroup('warehouse') shell:selectGroup('personnel') only('logistics')
shell:selectTab('crafting',{returnTab='warehouse',filterProduct='Base.Plank'}) only('crafting')
local crafting=shell.pages.crafting
check(crafting.returnContext and crafting.backButton.visible,'one-step return context')
check(crafting.views.recipes.filterProduct=='Base.Plank' and not crafting.views.recipes.store.value.recipeId,'product filters without selecting')
shell:selectTab('warehouse')
check(not crafting.returnContext and not crafting.backButton.visible,'manual navigation discards context')
check(D.open(actor,'settlement','personnel')==shell,'explicit reopen route') only('personnel')
check(D.open(actor,'settlement')==shell,'reopen preserves active route')
shell:close()
for _,p in pairs(shell.pages) do check(not p.active and p.activation==nil,'close releases page') end
local cold=assert(D.open(actor,'settlement')) check(cold.activeTab=='warehouse','cold default remains warehouse') cold:close()
print('ui-nav-grouping: '..checks..' PASS; ISUI and services mocked')
