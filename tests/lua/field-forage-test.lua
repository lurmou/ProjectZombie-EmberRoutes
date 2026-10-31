package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;" .. package.path
local n=0 local function check(v,m) n=n+1 assert(v,m) end
local function class()
 local c={} c.__index=c
 function c:derive() local d=class() setmetatable(d,{__index=self}) return d end
 function c:new(character) return setmetatable({character=character},self) end
 return c
end
ISBaseTimedAction=class()
function ISBaseTimedAction:perform() self.removed=true end
function ISBaseTimedAction:stop() end
ISPanel=class()
function ISPanel:new() error('NPC forage must not instantiate a UI panel') end
getSearchMode=function() error('NPC forage must not touch player search mode') end
getTexture=function() return {} end
isServer=function() return false end isClient=function() return false end
package.loaded['ISUI/ISPanel']=true
package.loaded['TimedActions/ISBaseTimedAction']=true
package.loaded['Foraging/forageSystem']=true
local function list()
 local t={}
 function t:add(item) self[#self+1]=item end
 function t:get(i) return self[i+1] end
 function t:size() return #self end
 function t:isEmpty() return #self==0 end
 return t
end
ArrayList={new=list}
local ids,spawned=0,0
instanceItem=function(fullType)
 ids=ids+1
 local item={id=ids,fullType=fullType}
 function item:getContainer() return self.container end
 function item:getFullType() return self.fullType end
 return item
end
local inventory=list()
local npc={getInventory=function() return inventory end,isKnownPoison=function() return false end,isTimedActionInstant=function() return false end}
forageSystem={itemDefs={['Mod.Herb']={type='Mod.Herb',minCount=2,maxCount=2,
 spawnFuncs={function(character,container,definition,items) spawned=spawned+1 return items end}}}}
local previous={real='previous manager'}
ISSearchManager={players={[npc]=previous}}
function ISSearchManager.getManager(c) return assert(ISSearchManager.players[c],'manager must exist only inside native call') end
local ecology=0
function ISSearchManager:removeItem(icon) ecology=ecology+1 icon.zoneData.forageIcons[icon.iconID]=nil end
local deposits=0
function forageSystem.addOrDropItems(character,container,items)
 for i=0,items:size()-1 do local item=items:get(i) container:add(item) item.container=container deposits=deposits+1 end
end
function forageSystem.actionComplete(character,id)
 local m=ISSearchManager.getManager(character) local icon=assert(m.forageIcons[id])
 icon:setIsBeingRemoved(true)
 -- Simulate vanilla ISSearchManager.onUpdateIcon triggering before removeIcon
 if m.forageIcons[id] then
  m.forageIcons[id]:reset()
  m.forageIcons[id]:removeIsoMarker()
  m.forageIcons[id]:removeWorldMarker()
 end
 m:removeItem(icon) m:removeIcon(icon)
end
package.loaded['Foraging/ISSearchManager']=true
local game='D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/'
dofile(game..'client/Foraging/ISBaseIcon.lua') package.loaded['Foraging/ISBaseIcon']=true
dofile(game..'shared/Foraging/ISForageAction.lua') package.loaded['Foraging/ISForageAction']=true
local F=require 'EmberRoutesProbe/FieldForage'
local raw={id='icon',itemType='Mod.Herb',count=2}
local zone={forageIcons={icon=raw}}
local square={}
local prepared=assert(F.prepare(npc,raw,zone,square))
check(prepared.icon.itemList:size()==2 and spawned==1,'installed native count/spawn functions create originals once')
check(ISSearchManager.players[npc]==previous,'preparation leaves prior lookup untouched')
local action=prepared.create()
check(action.forageIcon==prepared.icon and ISSearchManager.players[npc]==previous,'native constructor receives composed data and restores lookup')
check(deposits==0 and ecology==0,'constructing an action does not apply work')
prepared.invoke(action.complete,action)
check(deposits==2 and inventory[1]==raw.itemList:get(0),'installed complete transfers the exact native-generated originals')
prepared.invoke(action.perform,action)
check(ecology==1 and zone.forageIcons.icon==nil,'native perform settles ecology once')
check(ISSearchManager.players[npc]==previous,'native completion restores lookup')
local ok=pcall(prepared.invoke,function() error('native callback failed') end)
check(not ok and ISSearchManager.players[npc]==previous,'exception cannot leak the scoped manager')
check(ids==2 and spawned==1,'no second producer or replacement items')
print('PASS '..n..' installed forage action/count/spawn adapter checks; engine world mocked')
