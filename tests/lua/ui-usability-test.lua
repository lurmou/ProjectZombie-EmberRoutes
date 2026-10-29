local count=0 local function check(v,s) count=count+1 assert(v,s) end
local root={} local fakeItems={}
function getText(k) return k end function getItemNameFromFullType(k) return k end function getTimestampMs() return 10000 end
local container={getItems=function() return {size=function() return #fakeItems end,get=function(_,i) return fakeItems[i+1] end} end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,resolve=function() return {container=container} end}
local Names=require 'EmberRoutesProbe/DisplayNames'
local npc={getDescriptor=function() return {getForename=function() return 'Jane' end,getSurname=function() return 'Smith' end} end,getFullName=function() return 'internal-uuid' end}
check(Names.name('internal-uuid',npc)=='Jane Smith','descriptor name replaces internal carrier name')
check(Names.name('internal-uuid',nil)=='Jane Smith','temporarily unavailable carrier retains observed name')
check(root.displayNames==nil,'read-only UI projection never mutates the saved work ledger')
root={} check(Names.name('internal-uuid',nil)~='Jane Smith','names never leak across worlds')
local Display=require 'EmberRoutesProbe/ItemDisplay'
for i=1,400 do fakeItems[i]={getID=function() return i end,getFullType=function() return 'Base.Plank' end} end
local record={id='job',items={400},source='in',destination='out'}
local budget={remaining=256} local types=Display.types(record,nil,budget)
check(budget.remaining==0 and not types['400'],'old item-name discovery obeys global budget')
Display.types(record,nil,{remaining=256})
check(types['400']=='Base.Plank','later projection resumes old-job scan instead of restarting forever')
check(record.itemTypes==nil,'old-job read model does not mutate task facts or originals')
package.loaded['EmberRoutesProbe/CraftingService']={status=function() return {workers={{id='unable'},{id='able'}}} end,
 preview=function(_,_,id,_,_,_,fn) fn(id=='able' and {state='READY'} or {state='BLOCKED',conditions={'NPC_RECIPE_UNKNOWN'}}) return function() end end}
local Preview=require 'EmberRoutesProbe/PublicPreview'
local result Preview.watch({},'scope','recipe',1,nil,function(v) result=v end)
check(result.state=='READY','first NPC lacking recipe never blocks a capable second NPC')
package.loaded['EmberRoutesProbe/CraftingService'].status=function() return {workers={}} end
Preview.watch({},'scope','recipe',1,nil,function(v) result=v end)
check(result.state=='WAITING','no workers is public waiting, not fake material shortage')
print('PASS '..count..' readable identity/item/preview checks; native host mocked')
