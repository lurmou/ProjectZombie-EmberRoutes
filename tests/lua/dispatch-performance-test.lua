-- Installed Kahlua, synthetic world/time and planning cost. No FPS claims.
local root,now,workers,busy,handles,calls,steps={},0,{},{},{},{},0
local allowed,accepting,known,haul=true,true,true,false
local planCost,planFailure=512,nil
local listeners,inventoryListeners={},{}
local actor={getUsername=function() return 'owner' end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='s'}
local recipe={recipe={},id='saw',name='Saw',product='Base.Plank',yield=3,surface=false}
local serial=0
package.loaded['EmberRoutesProbe/Boot']={ready=true,runtimeReady=true,hasJava=function() return true end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={listeners=listeners,inventoryListeners=inventoryListeners,
 data=function() return root end,id=function() serial=serial+1 return 'id-'..serial end,
 describe=function() return {x=1,y=1} end}
package.loaded['EmberRoutesProbe/SettlementLedger']={listeners={},view=function() if allowed then return entry end end,at=function() return {entry} end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return {'crate'} end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) return handles[id] and {handle=handles[id]} end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {accepting=function() return accepting end,status=function() end} end}
package.loaded['EmberRoutesProbe/Work']={busy=function(id) return busy[id] end,hasCargo=function() return false end,record=function() end,
 allowAutomation=function() end,assign=function(_,id) busy[id]=true calls[#calls+1]={kind='haul',id=id,time=now} return 'QUEUED' end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/ProductionRecipe']={read=function() return recipe end,inspect=function() if known then return recipe end return nil,'NPC_RECIPE_UNKNOWN' end}
package.loaded['EmberRoutesProbe/CraftSurfaces']={resolve=function() return {} end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function(_,s) if string.find(s,'DISPATCH_BLOCKED',1,true) then print(s) end end}
package.loaded['EmberRoutesProbe/BusinessJobs']={records=function() return {} end,crafts=function() return {} end,flush=function() end}
package.loaded['EmberRoutesProbe/ProductionChain']={new=function()
 local remaining=planCost
 return {cancel=function() end,step=function(_,budget)
  steps=steps+1 remaining=remaining-(budget or 32)
  if remaining<=0 then if planFailure then return nil,planFailure end return {nodes={}} end
 end}
end}
package.loaded['EmberRoutesProbe/Production']={execute=function(_,_,_,id)
 busy[id]=true calls[#calls+1]={kind='craft',id=id,time=now} return 'QUEUED'
end}
package.loaded['EmberRoutesProbe/LogisticsService']={publicOffer=function() if haul then return {source='a',items={1}} end end}
function isClient() return false end function isServer() return false end
function getTimestampMs() return now end function getSpecificPlayer() return actor end
EmberRoutesProbeJava={workerCount=function() return #workers end,workerIdAt=function(i) return workers[i+1] end}
local Public=require 'EmberRoutesProbe/PublicWork'
local function reset(n)
 root={} workers={} busy={} handles={} calls={} steps=0 now=0 accepting=true known=true haul=false planCost=512 planFailure=nil
 for i=1,n do
  local id='w'..i workers[i]=id busy[id]=i~=1
  handles[id]={getX=function() return 1 end,getY=function() return 1 end,getZ=function() return 0 end,
   getCharacterActions=function() return {isEmpty=function() return true end} end,
   getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end}
 end
 dofile('tests/lua/membership-fixture.lua')(function() if allowed then return entry end end,workers)
 Public.prepareRecovery()
end
local function order()
 local result,id=Public.create(actor,'s','saw',3,nil,Public.requestId()) assert(result=='ORDER_CREATED') return id
end
local function tick() now=now+25 Public.tick() end
local latencies={}
for _,n in ipairs({1,16,32,64}) do
 reset(n) order()
 for _=1,10000 do tick() if #calls>0 then break end end
 assert(#calls==1 and calls[1].kind=='craft','only eligible worker claims')
 latencies[n]=calls[1].time
 print('dispatch simulation workers='..n..' planningOps=512 latencyMs='..latencies[n]..' requestSlices='..steps)
end
assert(latencies[64]<=2000 and latencies[64]<=latencies[1]+500,'in-flight planning must not wait for busy roster rotation')
reset(1) local reasonOrder=order() tick()
root.publicWork.orders[reasonOrder].revision=root.publicWork.orders[reasonOrder].revision+1
root.publicWork.orders[reasonOrder].reason='NPC_RECIPE_UNKNOWN'
for _=1,80 do tick() if #calls>0 then break end end
assert(#calls==1 and calls[1].kind=='craft','another worker diagnostic revision does not cancel useful planning')
reset(16) for _,key in ipairs(workers) do busy[key]=nil end order()
for _=1,80 do tick() if #calls>0 then break end end
assert(#calls==1,'concurrent private prechecks still produce one unique order claim')
local metrics=Public.metrics()
assert(metrics.operations<=metrics.samples*128 and metrics.samples<=128,'sample ring and total per-tick planning operations are bounded')
reset(16) for _,id in ipairs(workers) do busy[id]=nil Public.setPriority(actor,'s',id,'crafting',0) end order()
for _=1,80 do tick() end assert(steps==0,'disabled work creates no precheck')
reset(16) local id=order() for _=1,2 do tick() end
accepting=false local before=steps for _=1,80 do tick() end
assert(steps==before and #calls==0,'save barrier stops planning and claims')
accepting=true known=false for _=1,80 do tick() end assert(#calls==0,'lost recipe invalidates in-flight ticket')
reset(1) id=order() for _=1,2 do tick() end
local r=root.publicWork.orders[id] assert(Public.command(actor,'s',id,r.revision,'stop')=='ORDER_UPDATED')
for _=1,80 do tick() end assert(#calls==0,'paused order cannot use old ticket')
reset(1) planCost=8 haul=true Public.setPriorities(actor,'s','w1',{crafting=1,hauling=2},0) order()
for _=1,80 do tick() if #calls>0 then break end end assert(calls[1].kind=='craft','short priority wait allows fast craft precheck')
reset(1) planCost=100000 haul=true Public.setPriorities(actor,'s','w1',{crafting=1,hauling=2},0) order()
for _=1,80 do tick() if #calls>0 then break end end assert(calls[1].kind=='haul','slow planning cannot hold an idle body indefinitely')
reset(1) planCost=8 planFailure='MATERIALS_UNAVAILABLE' order()
for _=1,240 do tick() end assert(steps<=2,'missing resources do not trigger a blind two-second rescan')
local previous=steps for _,fn in ipairs(inventoryListeners) do fn('unrelated') end
for _=1,8 do tick() end assert(steps==previous,'unrelated container does not wake failed precheck')
for _,fn in ipairs(inventoryListeners) do fn('crate') end
for _=1,24 do tick() end assert(steps>previous,'relevant inventory event wakes failed precheck')
previous=steps for _=1,640 do tick() end assert(steps>previous,'staggered fallback eventually retries without inventory events')
print('PASS dispatch performance/admission/priority/event scenarios; synthetic time, native world mocked')
reset(1) tick()
local registry=package.loaded['EmberRoutesProbe/ContainerRegistry']
local originalData=registry.data local reads=0
registry.data=function() reads=reads+1 return originalData() end
for _=1,100 do Public.tick() end
assert(reads==0,'idle dispatch time gate precedes world/native queries')
registry.data=originalData
