package.path='Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;'..package.path
local manifest={valid=function(r) return r.manifestValid end,claimItemIds=function(r) return r.claims or {} end}
package.loaded['EmberRoutesProbe/Hauling/HaulManifest']=manifest
local haul=require 'EmberRoutesProbe/Hauling/HaulRetirement'
local craft=require 'EmberRoutesProbe/Crafting/CraftRetirement'
assert(not haul.valid({state='PAUSED',format=3,manifestValid=true,claims={}}))
assert(not haul.valid({state='DONE',format=3,manifestValid=true,claims={17}}))
assert(not haul.valid({state='DONE',format=3,manifestValid=true,claims={},activeAttempt={}}))
assert(haul.valid({state='DONE',format=3,manifestValid=true,claims={}}))
assert(not craft.valid({released=false,state='DONE'}))
assert(not craft.valid({released=true,state='DONE',format=4,produced=1,delivered=0,target=1}))
assert(not craft.valid({released=true,state='DONE',format=4,produced=1,delivered=1,target=2}))
assert(craft.valid({released=true,state='DONE',format=4,produced=1,delivered=1,target=2,reason='TARGET_REACHED'}))
assert(craft.valid({released=true,state='CANCELLED'}))
print('PASS domain retirement evidence; game NOT RUN')
