-- Real Dashboard, registry, pages, Store and PageLifecycle; existing ISUI/service host.
ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local checks=0
local function check(value,message) assert(value,message) checks=checks+1 end
local Registry=require 'EmberRoutesProbe/UI/PageRegistry'
local Dashboard=require 'EmberRoutesProbe/SettlementDashboard'
local fixture=ERSettlementPreview('orders',20,1280,900)
local actor=fixture.actor
fixture:close()
local demandRows={{id='DEMAND:cleaning:home',kind='DEMAND',title='Cleaning',readOnly=true,compact=true,
    bucket='waiting',state='waiting',assets={},children={}}}
local demandCallbacks={}
package.loaded['EmberRoutesProbe/DemandMonitorService']={
    status=function() return {rows=demandRows} end,
    watch=function(_,_,callback)
        demandCallbacks[#demandCallbacks+1]=callback callback({rows=demandRows})
        return function() end
    end
}
local personnel=package.loaded['EmberRoutesProbe/PersonnelService']
personnel.enrichWorkers=function(_,_,workers)
    for _,w in ipairs(workers) do w.priorities={crafting=1,hauling=4} end
    return workers
end
local expected={warehouse='warehouse',demands='work',orders='work',policies='work',personnel='personnel',
    activities='settlement',defense='settlement',logistics='work',crafting='work'}
for id,group in pairs(expected) do check(Registry.get(id).group==group and Registry.getGroup(id)==group,'group '..id) end
check(Registry.get('logistics').parentTab=='orders' and Registry.get('crafting').parentTab=='orders','child relation preserved')
local shell=assert(Dashboard.open(actor,'settlement','warehouse'))
local function only(id)
    check(shell.activeTab==id,'active '..id)
    for key,page in pairs(shell.pages) do
        check((page.active==true)==(key==id),'single active leaf '..key)
        check((page.visible==true)==(key==id),'single visible leaf '..key)
    end
end
shell:selectGroup('work') only('demands')
check(shell.tabButtons.demands.visible and not shell.tabButtons.warehouse.visible,'group-local row')
local demand=shell.pages.demands local oldToken=demand.activation
shell:selectTab('orders') only('orders')
check(not demand.active and demand.activation==nil and oldToken~=nil,'deactivate invalidates token')
local oldSnapshot=demand.store.value.snapshot
demandCallbacks[1]({rows={}})
check(demand.store.value.snapshot==oldSnapshot,'stale demand callback rejected')
shell:selectGroup('warehouse') only('warehouse')
shell:selectGroup('work') only('orders')
check(shell.groupMemory.work=='orders','session memory')
-- The fixture is a genuine service snapshot row; add the production stable order identifier.
local orders=shell.pages.orders
orders.store.value.snapshot.rows[1].orderId='order-1'
shell:selectGroup('warehouse')
check(shell:selectTab('orders',{orderId='order-1'}),'stable order navigation succeeds')
check(orders.selected.orderId=='order-1' and orders.store.value.selection==orders.selected.id,'correct order selected')
check(shell:selectTab('demands',{problemId='DEMAND:cleaning:home'}),'problem row association succeeds')
check(demand.selected.id=='DEMAND:cleaning:home','correct problem selected')
check(shell:selectTab('personnel',{npcId='worker'}),'stable member navigation succeeds')
check(shell.pages.personnel.store.value.selected.id=='worker','correct member selected')
only('personnel')
for _,request in ipairs({{'orders',{orderId='missing'}},{'personnel',{npcId='missing'}},
    {'warehouse',{itemId='item'}},{'demands',{zoneId='zone'}},{'orders',{npcId='worker',orderId='order-1'}},
    {'missing',nil}}) do
    check(not shell:selectTab(request[1],request[2]),'failed jump rejected') only('personnel')
end
-- Target vanishes between read-only preflight and activation: restore prior page.
local monitorService=package.loaded['EmberRoutesProbe/OrderMonitorService']
local oldWatch=monitorService.watch
monitorService.watch=function(_,_,callback) callback({rows={}}) return function() end end
check(not shell:selectTab('orders',{orderId='order-1'}),'vanished target rejected after activation')
only('personnel')
check(shell.groupMemory.work=='demands','failed target does not replace group memory')
monitorService.watch=oldWatch
shell:selectTab('logistics') only('logistics')
shell:selectGroup('warehouse') shell:selectGroup('work') only('logistics')
check(shell.tabButtons.orders.visible,'child retains parent button')
shell:nextTab(1) only('orders')
-- Explicit reopen wins over remembered group page; no-tab reopen retains current leaf.
check(Dashboard.open(actor,'settlement','demands')==shell,'reuse explicit route') only('demands')
check(Dashboard.open(actor,'settlement')==shell,'reuse current route') only('demands')
shell:close()
for _,page in pairs(shell.pages) do check(not page.active and page.activation==nil,'close releases leaf') end
local fresh=assert(Dashboard.open(actor,'settlement','orders'))
check(fresh.activeTab=='orders','explicit initial route respected')
fresh:close()
local cold=assert(Dashboard.open(actor,'settlement','demands',{problemId='DEMAND:cleaning:home'}))
check(cold.pages.demands.selected.id=='DEMAND:cleaning:home','cold inherited demand adapter selects actual problem')
cold:close()
print('ui-nav-grouping: '..checks..' PASS; ISUI/services mocked, production navigation/lifecycle')
