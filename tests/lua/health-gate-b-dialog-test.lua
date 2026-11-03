-- Existing settlement UI native host, without its obsolete legacy-page assertions.
-- Needs the same installed ISTickBox file as settlement-tabs-test / KahluaLaborTest.
ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local owner=ERSettlementPreview('orders',20,1280,960)
ERMonitorPreviewOnly=nil
local actor=owner.actor
-- Native text-entry capability used by the real shared StepperInput.
function ISTextEntryBox:setOnlyNumbers(value) self.onlyNumbers=value end
local spec={id='Base.SawLogs',name='Saw logs',product='Base.Plank',yield=3,surface=false,inputs={},outputs={}}
package.loaded['EmberRoutesProbe/ProductionRecipe']={read=function() return spec end,describe=function() return spec end}
package.loaded['EmberRoutesProbe/CookingOrders']={describe=function() end}
package.loaded['EmberRoutesProbe/CraftingCatalog']={describe=function() return spec end}
local callbacks={} local watches=0
package.loaded['EmberRoutesProbe/PublicPreview']={watch=function(_,_,_,_,_,fn)
    callbacks[#callbacks+1]=fn
    fn({state='READY',counts={}})
    return function() end
end}
local Crafting=require 'EmberRoutesProbe/CraftingService'
Crafting.watchCatalog=function(_,_,_,fn)
    watches=watches+1 fn({rows={spec},page=1,pages=1})
    return function() watches=watches-1 end
end
local Public=require 'EmberRoutesProbe/PublicWork'
local serial,calls=0,0
Public.requestId=function() serial=serial+1 return 'dialog-intent-'..serial end
local Dialog=require 'EmberRoutesProbe/UI/PublicOrderDialog'
local dialog
Public.create=function()
    calls=calls+1
    dialog:submitOrder() -- Synchronous re-entry must see submitting=true.
    return 'ORDER_CREATED','order-1'
end
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
dialog=Dialog.open(owner,{recipeId=spec.id})
local first=dialog.requestId
check(type(first)=='string','a valid visible order has one intent')
dialog:query() dialog:describe()
check(dialog.requestId==first,'pure catalogue/preview refresh does not regenerate intent')
dialog:submitOrder() dialog:submitOrder()
check(calls==1 and owner.publicDialog==dialog and not dialog.actionButton.enable and dialog.notice,
    'double/reentrant submit creates once, disables submit and keeps result visible')
local late=callbacks[#callbacks]
dialog:close()
check(watches==0,'close releases catalogue ownership')
late({state='WAITING',counts={}})
check(dialog.previewData.state=='READY','expired activation rejects late preview')
dialog=Dialog.open(owner,{recipeId=spec.id})
check(dialog.requestId==first and dialog.notice and not dialog.actionButton.enable,'reopen restores submitted intent and result')
dialog:submitOrder()
check(calls==1,'reopen unchanged cannot submit a second order')
dialog.quantity:setText('2')
check(dialog.requestId~=first and dialog.actionButton.enable,'changed content permits a new intent')
local changed=dialog.requestId
dialog:close()
-- Player ModData survives a UI module reload. This is not a game/disk reload.
package.loaded['EmberRoutesProbe/UI/PublicOrderDialog']=nil
Dialog=require 'EmberRoutesProbe/UI/PublicOrderDialog'
dialog=Dialog.open(owner,{recipeId=spec.id})
check(dialog.quantity:getText()=='2' and dialog.requestId==changed,'module reload restores current quantity and token')
dialog:submitOrder()
check(calls==2 and not dialog.actionButton.enable,'new intent submits once')
dialog:close() owner:close()
print('PASS '..checks..' Gate B real dialog lifecycle checks; ISUI host mocked; native renderer/disk NOT RUN')
