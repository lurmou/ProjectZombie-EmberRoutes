-- Actual Java graph, fake-free claims operations; no engine or disk effects.
local Claims=require 'EmberRoutesProbe/Kernel/LaborClaims'
local n=0 local function check(ok,label) n=n+1 assert(ok,label) end
local graph=Claims.new(20)
local a=assert(graph:acquire('a',1,{'item:1','item:2'},{claimId='a:c7'}))
assert(graph:reserve(a,'box',1,2,10))
assert(graph:reserve(a,'box',2,3,10))
local ok,q=graph:quarantine('item:1')
check(ok and q.originalToken==a and q.originalClaimId=='a:c7','isolation retains exact original identity')
check(graph.capacity.box.total==5 and graph.capacity.box.entries.a.amount==3,'isolated capacity remains reserved once')
local rev=graph.revision
ok=graph:restoreQuarantine('item:1',{originalTaskId='other'})
check(not ok and graph.revision==rev and graph.capacity.box.total==5,'conflicting restore writes nothing')
ok=graph:restoreQuarantine('item:1',q)
check(ok and graph.revision==rev and graph.capacity.box.total==5,'identical restore is idempotent')
local rotated=assert(graph:acquire('a',2,{'item:2'},{claimId='a:c7'}))
graph:release(a)
check(graph:valid(rotated,'item:2') and graph.capacity.box.total==5,'old token cannot release renewed owner or capacity')
local fresh=Claims.new()
assert(fresh:restoreQuarantine('item:1',q))
assert(fresh:restoreQuarantine('item:1',q))
check(fresh.capacity.box.total==2,'cold reconstruction counts isolation once')
local recipient=assert(fresh:acquire('recipient',1,{'item:3'}))
ok=fresh:unquarantine('item:1',{capacityAction='RETAIN',targetToken={taskId='recipient'}})
check(not ok and fresh.owners['item:1'] and fresh.capacity.box.total==2,'forged recipient leaves isolation intact')
assert(fresh:unquarantine('item:1',{capacityAction='RETAIN',targetToken=recipient}))
check(not fresh.owners['item:1'] and fresh.capacity.box.total==2
    and fresh.capacity.box.entries.recipient.items[1]==2,'retention transfers capacity without duplicating promise')
fresh:release(recipient)
check(not fresh.capacity.box,'recipient release settles capacity exactly once')
assert(graph:shrink(rotated,{'item:1'}))
check(graph.owners['item:1'].kind=='SYSTEM_QUARANTINE' and not graph.owners['item:1'].originalClaimId
    and graph.capacity.box.total==3,'original-identity shrink retains isolation and releases only its capacity')
graph:release(rotated)
check(not graph.capacity.box,'remaining capacity released')
local token=assert(graph:acquireNew('new',1,{'item:8'}))
check(type(token.claimId)=='string' and token.claimId:find('new:c',1,true)==1,'both acquisition paths supply claim identity')
assert(graph:extend(token,{'item:8','item:9','item:9'}))
check(#token.resources==2 and graph:valid(token,'item:9'),'domain append is idempotent')
local strict=EmberRoutesProbeJava.claimsCommand(graph,'ACQUIRE_NEW',{
    taskId='new',generation=2,resources={'item:10'}})
check(not strict.ok and strict.result=='TASK_ALREADY_HAS_CLAIMS' and not graph.owners['item:10'],'create cannot silently renew an existing task')
local before=graph.revision
ok=graph:replace(token,{'item:9','item:9'})
check(not ok and graph.revision==before and graph:valid(token,'item:8'),'invalid replacement has no partial removal')
local bridge=EmberRoutesProbeJava
EmberRoutesProbeJava={}
ok=pcall(function() graph:release(token) end)
EmberRoutesProbeJava=bridge
check(not ok and graph:valid(token,'item:8'),'missing Java refuses without Lua mutation fallback')
print('PASS '..n..' actual Java claims rotation/isolation/cold-restore/release checks; engine/disk NOT RUN')
