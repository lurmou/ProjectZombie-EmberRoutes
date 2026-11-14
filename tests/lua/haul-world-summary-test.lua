-- The last completed haul is session-local, and cannot cross world roots.
package.path='Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;'..package.path
local world={}
local dataCalls=0
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return world end}
package.loaded['EmberRoutesProbe/Work/LaborStore']={data=function() dataCalls=dataCalls+1 return world end}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
package.loaded['EmberRoutesProbe/Kernel/JobState']={isTerminal=function() return false end}
package.loaded['EmberRoutesProbe/Hauling/HaulManifest']={claimItemIds=function() return {} end}
package.loaded['EmberRoutesProbe/Hauling/HaulJobRecord']={}
local Haul=require 'EmberRoutesProbe/Hauling/HaulJobs'
assert(Haul.record('worker')==nil and dataCalls==1,'record initializes labor before reading jobs')
Haul.commit=function() return true end
assert(Haul.finish({format=3,id='haul',npcId='worker',producer='LOGISTICS',generation=0,delivered=1,items={1}}))
local recent=assert(Haul.recent('worker'))
recent.id='mutated'
assert(Haul.recent('worker').id=='haul','summary is detached')
world={}
assert(Haul.recent('worker')==nil,'world switch must discard previous summary')
print('PASS haul summary reset and detached read; game NOT RUN')
