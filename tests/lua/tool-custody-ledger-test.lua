assert(ERLaborTestBridge,'actual Java labor kernel required')
local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local root={format=2,obligations=Ledger.fresh(),nextClaimSeq=0}
local state={root=root,claims=Claims.new(),tokens={},custodyTokens={}}
local sourceItems,storageItems={},{}
local function container(items)
    local c={items=items}
    function c:getItems()
        return {size=function() return #items end,get=function(_,i) return items[i+1] end,
            contains=function(_,item) for _,v in ipairs(items) do if v==item then return true end end return false end}
    end
    return c
end
local source,storage=container(sourceItems),container(storageItems)
local endpoints={source={id='source',container=source},storage={id='storage',container=storage}}
local serial=0
local Registry={data=function() return root end,id=function() serial=serial+1 return 'uuid-'..serial end,
    resolve=function(id) return endpoints[id] end,revalidate=function(e) return e end,
    logistics=function(e) return e==endpoints.storage and 'STORAGE' or 'INPUT' end,inventoryChanged=function() end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']=Registry
local inventoryItems={}
local inventory=container(inventoryItems)
function inventory:getFirstEvalRecurse(predicate) for _,item in ipairs(inventoryItems) do if predicate(item) then return item end end end
local npc={getInventory=function() return inventory end}
local item={id=42,where=source}
function item:getID() return self.id end
function item:getContainer() return self.where end
sourceItems[1]=item
EmberRoutesProbeJava=ERLaborTestBridge
EmberRoutesProbeJava.carrierId=function(body) return body==npc and 'npc' end
local Store={data=function() return root end}
Store.owner=function(id) local owner=state.claims.owners['item:'..tostring(id)] return owner and {taskId=owner.taskId} end
package.loaded['EmberRoutesProbe/Work/LaborStore']=Store
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return {peek=function() return nil end} end}
require('EmberRoutesProbe/Work/LaborJobCommit').install(Store,state,function() error('not used') end,function() end)
local C=require 'EmberRoutesProbe/Field/ToolCustody'
local first=assert(C.claim('npc',42,'TOOL','source'))
assert(not C.canClaim('other',42))
local detached=C.byItem(42) detached.state='HELD'
assert(C.byItem(42).state=='RESERVED','read view cannot mutate authority')
assert(C.releaseUncollected(first.id,npc) and not state.claims.owners['item:42'],'original at source permits no-effect rollback')
assert(root.obligations.byId[first.id].state=='SETTLED')
local second=assert(C.claim('npc',42,'TOOL','source'))
assert(second.id~=first.id,'repeat borrow creates a distinct identity')
local old=root.obligations.byId[first.id]
assert(not Store.commitCustody({action='RETIRE',id=first.id,expectedRevision=old.revision}),
    'settled custody cannot retire without dependency proof')
assert(Store.commitCustody({action='RETIRE',id=first.id,expectedRevision=old.revision},function(r)
    return r.state=='SETTLED' and r.settlement.originalPresent==true
end) and not root.obligations.byId[first.id] and root.obligations.byId[second.id],
    'proven retirement leaves the new active custody intact')
sourceItems[1]=nil inventoryItems[1]=item item.where=inventory
assert(C.markHeld(second.id,npc,item))
assert(not C.releaseUncollected(second.id,npc) and state.claims.owners['item:42'],'held original cannot be cancelled as untouched')
local intent={format=1,jobId='return',destinationId='storage',scopeId='world'}
assert(C.assignReturn(second.id,'return',intent,npc,item))
assert(not C.releaseUncollected(second.id,npc),'pending return is never an unchanged cancellation')
inventoryItems[1]=nil
assert(not C.abortReturn(second.id,'return',npc,item) and C.byItem(42).state=='PENDING_RETURN',
    'missing original cannot prove an aborted return')
inventoryItems[1]=item
assert(C.abortReturn(second.id,'return',npc,item) and C.byItem(42).state=='HELD')
assert(C.assignReturn(second.id,'return',intent,npc,item))
assert(not C.completeReturn(second.id,'return','source',item),'wrong destination rejected')
local count,why=C.retainOnDeath('npc')
assert(count==0 and why=='DEAD_CARRIER_OBLIGATION_RETAINED' and state.claims.owners['item:42'])
inventoryItems[1]=nil storageItems[1]=item item.where=storage
assert(C.completeReturn(second.id,'return','storage',item))
assert(root.obligations.byId[second.id].state=='SETTLED' and not state.claims.owners['item:42'],'physical warehouse receipt releases exact claim')
local carried={id=43,where=inventory}
function carried:getID() return self.id end function carried:getContainer() return self.where end
inventoryItems[1]=carried
local initial=assert(C.claim('npc',43,'TOOL',nil,nil,npc,carried))
assert(C.releaseUncollected(initial.id,npc),'verified initial inventory reservation can be cancelled before assignment')
local missing=assert(C.claim('npc',43,'TOOL',nil,'missing-job',npc,carried))
assert(not C.releaseUncollected(missing.id,npc) and state.claims.owners['item:43'],
    'a referenced missing Job cannot prove no effect')
local token=state.claims.owners['item:43'] state.claims.owners['item:43']=nil
assert(not C.canClaim('other',43) and not C.claim('npc',43,'TOOL',nil,nil,npc,carried),
    'missing runtime claim cannot make an active custody available')
state.claims.owners['item:43']=token
print('PASS tool custody ledger and real Java claim commits; native inventory/disk NOT RUN')
return {root=root,Registry=Registry,Store=Store,Custody=C,state=state}
