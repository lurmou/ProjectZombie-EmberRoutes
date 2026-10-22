package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local n=0 local function check(v,why) n=n+1 assert(v,why) end
local tables,uuid={},0
ModData={getOrCreate=function(key) tables[key]=tables[key] or {} return tables[key] end}
function getRandomUUID() uuid=uuid+1 return 'locate-'..uuid end
function isClient() return false end function isServer() return false end
local actor={getX=function() return 5.5 end,getY=function() return 5.5 end,getZ=function() return 0 end,
    getIndex=function() return 0 end,isDead=function() return false end}
function getSpecificPlayer() return actor end
local object={data={}} local objects={values={object}}
function objects:size() return #self.values end function objects:get(i) return self.values[i+1] end
function objects:contains(value) for _,v in ipairs(self.values) do if v==value then return true end end return false end
local square={getX=function() return 5 end,getY=function() return 5 end,getZ=function() return 0 end,getObjects=function() return objects end}
local inventory={getType=function() return 'crate' end}
function object:getSquare() return square end function object:getContainer() return inventory end function object:getModData() return self.data end
local loaded=true local cell={getGridSquare=function(_,x,y,z) if loaded and x==5 and y==5 and z==0 then return square end end}
local currentCell=cell function getCell() return currentCell end
local now,marks=0,0 function getTimestampMs() return now end
function addAreaHighlightForPlayer() marks=marks+1 end
Events=Events or {} local callbacks={}
Events.OnRenderTick={Add=function(fn) callbacks[fn]=true end,Remove=function(fn) callbacks[fn]=nil end}
package.loaded['EmberRoutesProbe/Log']=package.loaded['EmberRoutesProbe/Log'] or {write=function() end}
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Filter=require 'EmberRoutesProbe/StorageFilter'
local Locator=require 'EmberRoutesProbe/WarehouseLocator'
local filter=Filter.new() filter.groups.other=true
check(Registry.configure(actor,object,filter)=='FILTER_CONFIGURED','fixture uses the real registration and access rules')
local id=object.data.EmberRoutesContainer.id
local entry=assert(Ledger.commit(actor,nil,'Locator test',{x=0,y=0,w=10,h=10}))
local locator=Locator.new(actor,entry.id)
local nativeResolve=Registry.resolve local resolves=0
Registry.resolve=function(...) resolves=resolves+1 return nativeResolve(...) end
local function count() local size=0 for _ in pairs(callbacks) do size=size+1 end return size end
check(locator:locate(id) and count()==1,'valid current registered source installs one temporary render lease')
for i=1,10 do now=i*40 locator:render() end
check(marks==10 and resolves==1,'unchanged marker draws cached coordinates without repeated physical lookup each frame')
now=500 locator:render() check(resolves==2,'physical identity and permission recheck is bounded to 500ms')
now=5000 locator:render() check(count()==0 and not locator.endpoint,'expiry removes its render callback')
now=6000 locator:locate(id) local another=Locator.new(actor,entry.id) another:locate(id)
check(count()==1 and not locator.endpoint,'a new panel replaces the old marker rather than accumulating listeners')
filter.private=true object.data.EmberRoutesContainer.filter=filter now=6500 another:render()
check(count()==0,'revoking access clears an active marker at its next verification')
local position,reason=another:locate(id)
check(not position and reason=='CONTAINER_PRIVATE','click cannot locate a now-private source from a stale UI row')
filter.private=false loaded=false position,reason=another:locate(id)
check(not position and reason=='CONTAINER_UNLOADED' and count()==0,'unloaded area never receives a guessed marker')
loaded=true objects.values={} position,reason=another:locate(id)
check(not position and reason=='CONTAINER_REMOVED','removed or replaced container is rejected')
objects.values={object} Registry.data().containers[id].x=50 position,reason=another:locate(id)
check(not position and reason=='SOURCE_OUTSIDE','latest locator must still belong to the settlement')
Registry.data().containers[id].x=5 another:locate(id) currentCell={}
another:render() check(count()==0,'world-cell switch immediately releases old-world marker')
currentCell=cell tables={} position,reason=another:locate(id)
check(not position and reason=='WORLD_CHANGED','stale world-ledger identity cannot reuse a stable-looking ID')
Registry.resolve=nativeResolve
print('PASS '..n..' source locator checks with real registry/ledger; world highlight renderer NOT RUN')
