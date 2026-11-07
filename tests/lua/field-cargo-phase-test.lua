-- Cargo chooses its real next operation before projection or native dispatch.
local n=0 local function check(v,m) n=n+1 assert(v,m) end
package.loaded['TimedActions/ISInventoryTransferAction']=true
package.loaded['TimedActions/ISGrabItemAction']=true
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={}
package.loaded['EmberRoutesProbe/Work/LaborStore']={}
package.loaded['EmberRoutesProbe/Field/FieldSpatial']={square=function() return nil end}
package.loaded['EmberRoutesProbe/Crafting/CraftSupply']={}
package.loaded['EmberRoutesProbe/Work/WorkTransfer']={}
local C=require 'EmberRoutesProbe/Field/FieldCargo'
local c={job={effects='KNOWN',payload={phase='COLLECT',assets={{id=1,fullType='Base.Log',custody='HELD'}}}},
    npc={getInventory=function() return {getItems=function() return {size=function() return 0 end} end} end}}
c.change=function(fn) fn(c.job) return true end
c.unknown=function(why) c.reason=why c.job.effects='UNKNOWN' return true end
check(C.step(c,{})=='Failure' and c.job.payload.phase=='DELIVER','held-original route publishes delivery before trying native work')
check(c.job.payload.assets[1].custody=='HELD' and c.job.effects=='UNKNOWN','missing original is retained, not displayed or settled as delivered')
c.job.effects='KNOWN' c.job.payload.phase='DELIVER' c.job.payload.assets[1].custody='GROUND'
check(C.step(c,{})=='Failure' and c.job.payload.phase=='COLLECT','ground-original route publishes collection before an unloaded-world wait')
check(c.job.payload.assets[1].custody=='GROUND' and c.reason=='FIELD_OUTPUT_UNLOADED','unloaded source preserves ground responsibility')
print('PASS '..n..' cargo route/projection boundary checks; native world mocked')
