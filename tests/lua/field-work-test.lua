local n=0
local function check(v,msg) n=n+1 assert(v,msg) end
local root={}
local npc={}
function npc:isDead() return false end
function npc:isDraggingCorpse() return false end
function npc:getX() return 1 end function npc:getY() return 1 end function npc:getZ() return 0 end
local actor={isDead=function() return false end}
local now=0
getTimestampMs=function() return now end
ISTimedActionQueue={queues={},clear=function() end}
local registry={data=function() return root end,id=function() return 'random' end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=registry
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}
local macro=require 'EmberRoutesProbe/MembershipPolicy'
local pendingByNpc,contextByNpc={},{}
local entry={id='scope',factionId='f',revision=1,areas={{x=0,y=0,w=10,h=10}}}
package.loaded['EmberRoutesProbe/MembershipService']={
 check=function(id,purpose,observation)
  return macro.evaluate({settlementId='scope',factionId='f',context=contextByNpc[id] or 'SETTLEMENT',revision=(pendingByNpc[id] or contextByNpc[id]) and 2 or 1,
   pendingCommand=pendingByNpc[id]},entry,purpose,observation)
 end,
 entry=function(_,scope) return entry,nil,1 end,
 view=function(id) return {settlementId='scope',context=contextByNpc[id] or 'SETTLEMENT',pending=pendingByNpc[id]} end}

package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return root end}
package.loaded['EmberRoutesProbe/SettlementZones']={revision=function() return 1 end}
package.loaded['EmberRoutesProbe/ActivityAttendance']={blocksOrdinary=function() return false end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={}} end,flush=function() end}
local Jobs=require 'EmberRoutesProbe/TaskJobs'
Jobs.current()
local controls={}
package.loaded['EmberRoutesProbe/Driver']={valid=function() return true end,
 bindId=function(_,id) return {id=id,handle=npc} end,
 acquireControl=function(binding,job,generation) local c={binding=binding,job=job,generation=generation} controls[job]=c return c end,
 releaseControl=function(c) controls[c.job]=nil return true end,
 stopControlled=function() return true end,
 stopEvidence=function() return {available=true,nativeStopped=true,nativeMask=0} end}
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
package.loaded['EmberRoutesProbe/FieldCargo']={step=function(c) c.change(function(j) for _,a in ipairs(j.payload.assets) do a.custody='DELIVERED' end end) return 'Success' end}
local Field=require 'EmberRoutesProbe/FieldWork'
local Store=require 'EmberRoutesProbe/LaborStore'
local Directory=require 'EmberRoutesProbe/TaskDirectory'
local dir=Directory.new()
local contexts={}
local fail=false local continuations=0
local p=Field.provider({category='cleaning',defaultPriority=2,
 discover=function() end,
 continue=function() continuations=continuations+1 return false end,
 claim=function(s) return {kind='STAIN',x=1,y=1,z=0,identity=s.point.identity},{'field-target:'..s.point.identity} end,
 step=function(c)
  contexts[c.job.id]=c
  if fail then c.unknown('native unknown') return 'Failure' end
  if c.job.payload.testDone then return 'Success' end
  return 'Running'
 end})
check(p.defaultPriority==2,'provider composition preserves the existing cleaning priority')
local runtime=Runtime.current()
local function step(k) for _=1,k do now=now+100 runtime:step() end end
local env={actor=actor,entry={id='scope',revision=1},now=0,directory=dir}
local function claim(id,key,identity,npcId)
 local o=dir:upsert(key,1,'cleaning','scope') assert(dir:claim(key,1,npcId,id))
 return p.claim({key=key,point={identity=identity}},npcId,id,env)
end
check(claim('j1','o1','target1','npc1')=='QUEUED','queued by runtime')
step(8)
check(runtime:status('npc1').state=='ACTIVE','field owns one active session')
check(Store.resourceOwner('field-target:target1').taskId=='j1','shared target claim')
check(claim('j2','o2','target1','npc2')=='FIELD_RESOURCE_RESERVED','conflict rejected without a durable duplicate')
step(5)
check(not contexts.j2,'second worker cannot execute claimed target')
check(runtime:stop('npc1','SELF_CARE'),'stop request') step(8)
local j=Jobs.current():get('j1')
check(j.state=='SUSPENDED' and j.effects=='KNOWN','known stop persisted')
check(Store.resourceOwner('field-target:target1').taskId=='j1','pause retains responsibility')
local pausedRevision=j.revision
package.loaded['EmberRoutesProbe/Boot'].careBlocksWork=function() return true end
Field.advance({actor=actor,now=now+1000,directory=dir})
check(Jobs.current():get('j1').revision==pausedRevision,'retry pacing does not invalidate the durable self-care resume relation')
package.loaded['EmberRoutesProbe/Boot'].careBlocksWork=nil
check(Field.wake(actor,'npc1','j1','care'),'resume same job') step(8)
local c=contexts.j1
check(c.change(function(v) v.payload.testDone=true end),'publish actual effect') step(12)
check(Jobs.current():get('j1').state=='DONE','terminal only after stop')
check(not Store.resourceOwner('field-target:target1'),'settled target released')
Field.advance({actor=actor,now=now+1000,directory=dir})
check(not Jobs.current():get('j1'),'settled record retired')
check(dir:upsert('o1',2,'cleaning','scope').jobId==nil,'directory released')
-- Unknown effects may release a proven stationary body, never release its target.
fail=true
check(claim('j2','o2','target1','npc2')=='QUEUED','released resource may be claimed anew')
step(2)
Field.advance({actor=actor,now=now+10000,directory=dir}) step(15)
local unknown=Jobs.current():get('j2')
check(unknown.state=='RECONCILE_REQUIRED' and unknown.effects=='UNKNOWN','unknown is isolated')
check(Store.resourceOwner('field-target:target1').taskId=='j2','unknown keeps shared claims')
check(not Field.wake(actor,'npc2','j2'),'unknown cannot replay')
-- Re-open save envelope rejects nonserializable facts and retains field claims.
local reopened=assert(require('EmberRoutesProbe/JobStore').open(root))
check(reopened:get('j2').payload.target.identity=='target1','field survives store reload')
-- Changing settlement waits on custody, but cannot prohibit that custody's recovery.
fail=false
for index,mode in ipairs({'TRANSFER','RETURN'}) do
 local jobId,npcId,target='recover-'..mode,'worker-'..mode,'target-'..mode
 check(claim(jobId,'offer-'..mode,target,npcId)=='QUEUED','worker starts through normal body arbitration')
 step(4)
 check(contexts[jobId].change(function(j)
  j.payload.assets={{id=100+index,fullType='Base.Log',custody='HELD'}} j.payload.claims[#j.payload.claims+1]='item:'..(100+index)
 end),'record existing produced original')
 if mode=='TRANSFER' then pendingByNpc[npcId]={kind='TRANSFER',settlementId='new-scope'} else contextByNpc[npcId]='RETURN' end
 check(runtime:stop(npcId,'MEMBERSHIP_COMMAND'),'accepted command stops ordinary labour')
 step(8)
 check(Jobs.current():get(jobId).state=='SUSPENDED','custody survives stop before membership completes')
 local beforeContinuation=continuations
 Field.advance({actor=actor,now=now+20000+index*1000,directory=dir}) step(20)
 local recovered=Jobs.current():get(jobId)
 check(recovered and recovered.state=='DONE' and recovered.payload.assets[1].custody=='DELIVERED', 'pending transfer or return permits only existing cargo delivery')
 check(continuations==beforeContinuation,'recovery cannot continue a fresh field batch')
 local clear=true for _ in pairs(recovered.obligations) do clear=false end
 check(clear and not Store.resourceOwner('field-target:'..target),'membership can proceed after actual old custody settles')
end
-- Provider limit counts eligible offers, not deferred offers rejected later by the selector.
local points={}
for i=1,4 do points[i]={kind='STAIN',x=i,y=0,z=0,identity='target'..i} end
package.loaded['EmberRoutesProbe/FieldDiscovery']={targets=function() return points end,allowed=function() return true end}
package.loaded['EmberRoutesProbe/FieldOperations']={supplies=function() return {} end}
local provider=require('EmberRoutesProbe/FieldProviders').get('cleaning')
local discovery={npc=npc,npcId='other',entry={id='scope',revision=1},now=now+1000,directory=Directory.new(),candidates={},
    candidateReady=function(key) return string.find(key,'target4',1,true)~=nil end}
provider.discover(discovery)
check(#discovery.candidates==1 and discovery.candidates[1].point.identity=='target4', 'cooling first three cannot hide eligible fourth target')
print('PASS '..n..' field work lifecycle checks; native bodies mocked')
