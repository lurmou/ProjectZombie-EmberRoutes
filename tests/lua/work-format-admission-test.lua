-- Real Registry/JobStore admission; ModData and native cache are host substitutes.
local count=0
local function check(v,m) count=count+1 assert(v,m) end
local function copy(t) if type(t)~='table' then return t end local r={} for k,v in pairs(t) do r[k]=copy(v) end return r end
local function same(a,b)
    if type(a)~='table' or type(b)~='table' then return a==b end
    for k,v in pairs(a) do if not same(v,b[k]) then return false end end
    for k in pairs(b) do if a[k]==nil then return false end end return true
end
local world,bridgePath={},false
ModData={getOrCreate=function(key) check(key=='EmberRoutes/Work/v1','correct root') return world end}
EmberRoutesProbeJava={cachedModData=function() if bridgePath then return world end end}
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/JobStore'
local function rejected(root,reason)
    world=root local before=copy(root) local originalJobs,originalContainers=root.taskJobs,root.containers
    local ok,why=pcall(Registry.data)
    check(not ok and string.find(tostring(why),reason,1,true),'refuse '..reason)
    check(same(root,before) and root.taskJobs==originalJobs and root.containers==originalContainers,'refusal leaves persisted fields and table identities unchanged')
end
for _,native in ipairs({false,true}) do
    bridgePath=native
    rejected({taskJobs={format=99,byId={}}},'WORK_FORMAT_UNSUPPORTED')
    rejected({format=2,containers={}},'WORK_FORMAT_UNSUPPORTED')
    rejected({format=1,containers=false},'CONTAINER_FORMAT_UNSUPPORTED')
    rejected({format=1,taskJobs={format=99,byId={}}},'JOB_FORMAT_UNSUPPORTED')
    rejected({format=1,craftProbes={byNpc={a={id='old'}}}},'LEGACY_TASK_RESET_REQUIRED')
    rejected({format=1,taskJobs={format=1,byId={bad={id='bad'}}}},'JOB_RECORD_INVALID')
    world={} local root=Registry.data()
    check(root==world and root.format==1 and type(root.containers)=='table','empty new root initializes')
    check(root.taskJobs==nil,'read-only job check never publishes an empty job ledger')
    local svc=assert(Jobs.open(root))
    check(svc:create({id='current',npcId='a',providerType='TEST',scopeId='world',revision=1,
	state='PREPARING',effects='KNOWN',obligations={},payload={proof=true}}),'current job created')
    local jobs=root.taskJobs local containers=root.containers
    check(Registry.data()==root and root.taskJobs==jobs and root.containers==containers,'current ledger keeps identities')
    root.taskJobs={format=9,byId={}}
    rejected(root,'JOB_FORMAT_UNSUPPORTED')
end
-- Current production formats remain accepted until their real callers cut over.
local function job(id,provider,payload)
    return {id=id,npcId='worker',providerType=provider,scopeId='world',revision=1,
	state='RUNNING',effects='KNOWN',obligations={business=true},payload=payload}
end
local craft={format=3,id='craft',npcId='worker',requester='player',generation=1,
    state='RUNNING',phase='PLANNING',recipeId='Base.MakeAxe',signature='recipe',product='Base.Axe',
    recipeName='Axe',requested=1,target=1,unitYield=1,produced=0,delivered=0,
    settlementId='world',released=false,materials={},tools={},outputs={}}
local haul1={format=1,id='haul1',npcId='worker',source='from',destination='to',items={12}}
local haul2={format=2,id='haul2',npcId='worker',source='from',destination='to',items={13},
    producer='LOGISTICS',settlementId='world',plannedCount=1,routeRevision=0,attemptSequence=0,
    manifest={{itemId=13,sourceId='from',deliveryPolicy='AUTO_STORAGE',custodyState='UNCOLLECTED'}}}
world={format=1,taskJobs={format=1,byId={craft=job('craft','CRAFT',craft),
    haul1=job('haul1','HAUL',haul1),haul2=job('haul2','HAUL',haul2)}}}
local original=copy(world)
check(Registry.data()==world and same(world.taskJobs,original.taskJobs),'current CRAFT3/HAUL1/HAUL2 admitted without conversion')
local malformed=copy(original) malformed.taskJobs.byId.craft.payload.target=0
rejected(malformed,'JOB_RECORD_INVALID')
local unsafe=copy(original) unsafe.taskJobs.byId.craft.payload.callback=function() end
rejected(unsafe,'JOB_DATA_UNSERIALIZABLE')
local originalCheck=Jobs.check local admissions=0
Jobs.check=function(root) admissions=admissions+1 return originalCheck(root) end
world={format=1}
Registry.data() Registry.data() Registry.data()
check(admissions==1,'repeated same-world reads do not rescan job ledger')
world.taskJobs={format=1,byId={}}
Registry.data()
check(admissions==2,'replaced job ledger is checked before reuse')
Jobs.check=originalCheck
local raw={} check(Jobs.check(raw) and raw.taskJobs==nil,'JobStore check is read-only')
-- New-world event must use its engine root, not the prior world's native cache.
local engineRoot={} local staleRoot=world
ModData.getOrCreate=function() return engineRoot end
local callback
package.loaded['EmberRoutesProbe/Boot']={}
package.loaded['EmberRoutesProbe/MembershipRuntime']={install=function() end}
Events={OnInitGlobalModData={Add=function(fn) callback=fn end},OnNewGame={Add=function() end}}
local Lifecycle=require 'EmberRoutesProbe/MembershipLifecycle'
Lifecycle.install() callback(true)
check(engineRoot.format==1 and engineRoot.npcMembership and world==staleRoot,'new world admitted before membership writes despite stale cache')
local unsupported={format=99} engineRoot=unsupported
check(not pcall(callback,true) and unsupported.npcMembership==nil,'new-world event never bypasses unsupported format rejection')
ModData.getOrCreate=function() return world end
-- Real save coordinator must refuse BEFORE any recovery hook, even if those
-- hooks themselves would mutate ModData or reset runtime state.
local hooks=0
local function recovered() hooks=hooks+1 end
package.loaded['EmberRoutesProbe/Boot']={prepareMembershipRecovery=recovered,resetStock=recovered}
package.loaded['EmberRoutesProbe/TaskRuntime']={}
package.loaded['EmberRoutesProbe/LaborStore']={data=recovered}
package.loaded['EmberRoutesProbe/CraftProbe']={prepareRecovery=recovered}
package.loaded['EmberRoutesProbe/Companion']={}
package.loaded['EmberRoutesProbe/Actions']={}
package.loaded['EmberRoutesProbe/Haul']={}
package.loaded['EmberRoutesProbe/TaskPersistence']=nil
local Save=require 'EmberRoutesProbe/TaskPersistence'
world={format=1,taskJobs={format=77,byId={}}}
local before=copy(world)
check(not pcall(Save.load),'save recovery refuses unsupported format')
check(hooks==0 and same(world,before),'no recovery callback or root mutation before refusal')
print('PASS '..count..' Work format admission checks; real PZ disk save NOT RUN')
