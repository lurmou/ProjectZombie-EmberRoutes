assert(ERLaborTestBridge,'actual Java labor kernel required')
local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
local Jobs=require 'EmberRoutesProbe/Kernel/JobStore'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local root={format=2,nextClaimSeq=0,obligations=Ledger.fresh()}
local jobs=assert(Jobs.open(root))
local state={root=root,claims=Claims.new(),tokens={},cookingTokens={},personalTokens={},activityTokens={},fieldTokens={}}
local serial=0
local Registry={data=function() return root end,id=function() serial=serial+1 return 'u'..serial end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
local Store={data=function() return root end}
Store.getToken=function(id) return state.claims.tokensByTaskId[id] end
package.loaded['EmberRoutesProbe/Work/LaborStore']=Store
EmberRoutesProbeJava=ERLaborTestBridge
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function(r,id)
    r.nextClaimSeq=r.nextClaimSeq+1 return id..':c'..r.nextClaimSeq
end,function(id) state.tokens[id]=nil end)
require('EmberRoutesProbe/Work/LaborDomainAdapters').install(Store,state,
    function(_,job) return job.claimId end,function(id) state.tokens[id]=nil end,function() return true end)
local P=require 'EmberRoutesProbe/Crafting/ProductionJobs'
local Obl=require 'EmberRoutesProbe/Crafting/ProductionObligations'
local r={id='craft',npcId='npc',requester='player',settlementId='scope',recipeId='saw',recipeName='Saw',
    signature='saw:1',product='Base.Plank',requested=1,target=1,unitYield=1,produced=0,delivered=0,
    generation=0,state='RUNNING',phase='CRAFTING',released=false,benchId='bench',
    materials={{id=1,slot=0,source='stock'}},tools={{id=2,slot=1,source='stock'}},outputs={}}
local token,why=P.create(r) assert(token,tostring(why))
local seen local unwatch=jobs:watch(function(_,key)
    if key==r.id then local t=state.claims.tokensByTaskId[key] seen=t and t.generation==jobs:peek(key).payload.sequence end
end)
r.generation=1 assert(P.commit(r) and seen) unwatch()
local material=r.materials[1].obligationId local tool=r.tools[1].obligationId
assert(root.obligations.byId[material] and root.obligations.byId[tool])
assert(Jobs.check(root),'cold admission validates initial obligations')
local attempt=assert(P.beginEffect(r,token))
r.materials[1].consumed=true r.outputs={{id=3,fullType='Base.Plank',delivered=false}}
r.produced=1 r.unitMade=true r.phase='CONFIRMED'
assert(P.observe(r,attempt,true))
assert(root.obligations.byId[material].state=='SETTLED' and not state.claims.owners['item:1'])
local output=r.outputs[1].obligationId assert(root.obligations.byId[output] and state.claims.owners['item:3'])
r.outputs[1].delivered=true
assert(not P.commit(r),'claim cannot be dropped merely from delivered flag')
r.outputs[1].delivered=false
assert(Obl.returned(r,3,'destination','put-output'))
r.outputs[1].delivered=true r.delivered=1 assert(P.commit(r))
assert(root.obligations.byId[output].state=='SETTLED' and not state.claims.owners['item:3'])
assert(Obl.returned(r,2,'stock','put-tool')) assert(P.commit(r))
local allowed,_,changed=Obl.preparePickup(r,2) assert(allowed and changed and P.commit(r))
local newTool=r.tools[1].obligationId
assert(newTool~=tool and not root.obligations.byId[tool] and root.obligations.byId[newTool].state=='ACTIVE')
assert(Obl.returned(r,2,'stock','put-again') and P.commit(r)) tool=newTool
r.released=true r.state='DONE' r.phase='DONE' assert(P.commit(r))
assert(root.obligations.byId[tool].state=='SETTLED' and not state.claims.owners['item:2'])
local u={id='unknown',npcId='npc2',requester='player',settlementId='scope',recipeId='saw',recipeName='Saw',
    signature='saw:1',product='Base.Plank',requested=1,target=1,unitYield=1,produced=0,delivered=0,
    generation=0,state='RUNNING',phase='CRAFTING',released=false,benchId='bench2',
    materials={{id=4,slot=0,source='stock'}},tools={{id=5,slot=1,source='stock'}},outputs={}}
local uncertainToken=assert(P.create(u)) local uncertainAttempt=assert(P.beginEffect(u,uncertainToken))
u.materials[1].consumed=true u.outputs={{id=6,fullType='Base.Plank',delivered=false}}
assert(P.observe(u,uncertainAttempt,false,'partial'))
assert(state.claims.owners['item:4'] and state.claims.owners['item:6'])
assert(root.obligations.byId[u.materials[1].obligationId].state=='ACTIVE'
    and root.obligations.byId[u.outputs[1].obligationId].state=='RECONCILE_REQUIRED')
assert(Jobs.check(root),'unknown craft retains material and observed output through cold admission')
print('PASS craft consumption, output and tool settlement via actual Java; native host mocked')
