-- Real recovery producer + real Store publication; bridge only records intents.
-- This proves ordering/no re-entry, not Java execution or recovery parity.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local root={format=1,containers={},taskJobs={format=1,byId={}},quarantineResources={}}
local function job(id,item)
    return {id=id,npcId=id,providerType='HAUL',scopeId=id,claimId=id..':c'..item,
        revision=1,state='PREPARING',effects='KNOWN',obligations={},
        payload={format=3,sequence=1,source='s',destination='d',claims={'item:'..item},
            manifest={{itemId=item,custodyState='UNCOLLECTED'}}}}
end
root.taskJobs.byId.a=job('a',1)
root.taskJobs.byId.b=job('b',2)
Registry.data=function() return root end
local Recovery=require 'EmberRoutesProbe/Hauling/HaulJobRecovery'
local pending={}
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
Recovery.restore({current=root,rebuilt=Claims.new(),hasConflict=function() return true end,
    ensureEntityClaimId=function() error('unexpected acquire') end,rebuiltHaul={},newTokens={},pendingHaul=pending})
assert(#pending==2 and root.taskJobs.byId.a.revision==1 and root.taskJobs.byId.a.effects=='KNOWN','producer must only enqueue')
-- Exercise Store.data publication/drain with a controlled recovery order.
package.loaded['EmberRoutesProbe/Work/LaborRecovery']={restore=function(context)
    context.pendingHaul[1]=pending[1] context.pendingHaul[2]=pending[2]
end}
package.loaded['EmberRoutesProbe/Work/BuiltinLaborRecovery']={install=function() end}
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local seen={}
EmberRoutesProbeJava={laborCreate=function() error('unexpected create') end,laborCancel=function() error('unexpected cancel') end,
    laborMutate=function(ledger,owner,claims,contracts,cleanup,id,revision,payload,mutation)
        assert(Store.data()==root and Store.claimsInstanceForTests()==claims,'published Store before commit')
        assert(root.taskJobs.byId[id].effects=='KNOWN','no raw recovery publication')
        assert(mutation.state=='RECONCILE_REQUIRED' and mutation.effects=='UNKNOWN')
        seen[#seen+1]=id
        return {ok=false,result='TASK_WRITE_FAILURE',evidence='INJECTED'}
    end}
Store.data()
assert(#seen==2 and seen[1]==pending[1].id and seen[2]==pending[2].id,'ordered drain')
assert(#Store.haulRecoveryDiagnosis()==2,'diagnostic failures retained without retry queue')
print('PASS HAUL enqueue/publication/order/failure diagnosis; Java NOT RUN')
