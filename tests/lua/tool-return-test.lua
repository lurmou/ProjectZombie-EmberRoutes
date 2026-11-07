-- Tool Return lifecycle, independent return service, membership obligations,
-- preemption, and death/save recovery unit tests for Stage 2.
local n=0
local function check(v,msg) n=n+1 assert(v,msg) end

local root={}
local serial=0
local registry={
    data=function() return root end,
    id=function() serial=serial+1 return 'id-'..serial end,
    resolve=function() end,
    revalidate=function() return true end,
    logistics=function() return 'STORAGE' end,
    accepts=function() return true end,
    inventoryChanged=function() end
}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']=registry
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Kernel/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}
package.loaded['EmberRoutesProbe/Work/Work']={record=function() end}
package.loaded['TimedActions/ISCleanBlood']=true
package.loaded['TimedActions/ISChopTreeAction']=true
package.loaded['TimedActions/ISGrabCorpseAction']=true
package.loaded['TimedActions/ISDropCorpseAction']=true
package.loaded['TimedActions/ISUnequipAction']=true
package.loaded['TimedActions/ISEquipWeaponAction']=true
package.loaded['TimedActions/ISInventoryTransferAction']=true
package.loaded['TimedActions/ISGrabItemAction']=true
package.loaded['Farming/TimedActions/ISWaterPlantAction']=true
package.loaded['Farming/TimedActions/ISHarvestPlantAction']=true
package.loaded['Farming/TimedActions/ISShovelAction']=true
package.loaded['Farming/TimedActions/ISCurePlantAction']=true
package.loaded['Farming/TimedActions/ISSeedActionNew']=true
package.loaded['Farming/TimedActions/ISPlowAction']=true
package.loaded['Farming/ISUI/ISFarmingMenu']=true
package.loaded['Foraging/ISForageAction']=true
package.loaded['Foraging/ISSearchManager']=true
package.loaded['Foraging/ISForageIcon']=true
local currentNpcMap={}
EmberRoutesProbeJava={
    carrierFor=function(id,actor) return currentNpcMap[tostring(id)] or mockNpc end,
    controlledCarrier=function(actor) return currentNpcMap['1'] or mockNpc end,
    carrierId=function(npc) return npc and npc.id or '3' end,
    carrierPresent=function() return true end,
    bindingValid=function() return true end
}
ISInventoryTransferAction={
    new=function(s,char,item,src,dst,time)
        return {character=char,item=item,src=src,dst=dst,time=time,
            isValid=function() return true end,transferItem=function() return true end}
    end
}

ModData={getOrCreate=function(k) return {} end}
getTimestampMs=function() return 1000 end

local submittedSpec=nil
local delayStart=false
local terminalHandle=nil
local actionAdded=nil
local bodyActions={}
local fakeBody={
    move=function() return true end,
    stop=function() return true end,
    clear=function() return true end,
    add=function(a,b)
        actionAdded=b or a
        table.insert(bodyActions,actionAdded)
        return true
    end
}
local fakeRuntime={
    current=function()
        return {
            accepting=function() return true end,
            owns=function(s,id) return false end,
            submit=function(s,spec)
                submittedSpec=spec
                if not delayStart then spec.start(fakeBody) end
                return {ticket=1}
            end,
            status=function() return {pending=delayStart} end,
            inspect=function() return terminalHandle end,
            stopJob=function() return true end
        }
    end
}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']=fakeRuntime

local Store=require 'EmberRoutesProbe/Work/LaborStore'
local CustodyRecord=require 'EmberRoutesProbe/Field/ToolCustodyRecord'
local ReturnRecord=require 'EmberRoutesProbe/Field/ToolReturnRecord'

-- =========================================================================
-- 1. Schema Validation (ToolCustodyRecord & ToolReturnRecord)
-- =========================================================================
local validCustody={
    format=1,
    id='custody:1:501',
    npcId='1',
    itemId=501,
    role='CLEAN_TOOL',
    state='HELD',
    sequence=1,
    activeJobId='job-1',
    returnJobId='return-1',
    sourceContainerId='crate-1',
    claims={'item:501'}
}
check(CustodyRecord.valid(validCustody),'custody record with returnJobId passes schema')
validCustody.state='DEAD_CARRIER'
check(CustodyRecord.valid(validCustody),'custody record with DEAD_CARRIER passes schema')
validCustody.state='RECONCILE_REQUIRED'
check(CustodyRecord.valid(validCustody),'custody record with RECONCILE_REQUIRED passes schema')
validCustody.state='HELD'
validCustody.returnIntent={format=1,jobId='return-1',destinationId='crate-1',scopeId='home'}
check(CustodyRecord.valid(validCustody),'optional durable return intent validates exact destination')
validCustody.returnIntent.destinationId={}
check(not CustodyRecord.valid(validCustody),'invalid persistent destination is rejected')
validCustody.returnIntent=nil

local validReturn={
    format=1,
    id='return-1',
    npcId='1',
    custodyId='custody:1:501',
    itemId=501,
    role='CLEAN_TOOL',
    phase='APPROACH',
    destinationId='crate-1',
    state='RUNNING',
    sequence=1
}
check(ReturnRecord.valid(validReturn),'valid ToolReturnRecord passes schema')
local badReturn={format=1,id='ret-1',npcId='1',custodyId='c1',itemId=501,role='TOOL',phase='FLYING',state='RUNNING',sequence=1}
check(not ReturnRecord.valid(badReturn),'invalid phase rejected by ReturnRecord schema')

-- =========================================================================
-- 2. LaborStore Tool Return Lifecycle Methods
-- =========================================================================
-- Claim custody for NPC 1 on item 501
local custody,err=Store.claimCustody('1',501,'CLEAN_TOOL','crate-1','field-job-1')
check(custody~=nil and not err,'custody claimed')
custody.state='HELD'
check(Store.validToolUse('1','field-job-1',501),'valid tool use for field-job-1')

-- 2A. assignToolReturn
local ok,assigned=Store.assignToolReturn(custody.id,'return-job-1')
check(ok and assigned~=nil,'assignToolReturn succeeds')
check(custody.state=='PENDING_RETURN','custody state becomes PENDING_RETURN')
check(custody.returnJobId=='return-job-1','returnJobId recorded')
check(custody.activeJobId==nil,'activeJobId cleared during return')
-- While PENDING_RETURN, cannot be used by any field job
check(not Store.validToolUse('1','field-job-1',501),'cannot use tool while in PENDING_RETURN')

-- 2B. abortToolReturn
check(Store.abortToolReturn(custody.id,'return-job-1'),'abortToolReturn succeeds')
check(custody.state=='HELD','aborted return reverts custody state to HELD')
check(custody.returnJobId==nil,'returnJobId cleared on abort')
-- Re-assign tool use for job
Store.assignToolUse(custody.id,'field-job-1')
check(Store.validToolUse('1','field-job-1',501),'can use tool again after abort')

-- 2C. completeCustodyReturn with physical check
Store.assignToolReturn(custody.id,'return-job-1')

-- Destination container mock
local destItems={
    items={},
    size=function(s) return #s.items end,
    get=function(s,i) return s.items[i+1] end,
    contains=function(s,it)
        for _,x in ipairs(s.items) do if x==it then return true end end
        return false
    end
}
local crateSquare={
    getX=function() return 10 end,
    getY=function() return 10 end,
    getZ=function() return 0 end
}
local destContainer={
    getItems=function() return destItems end,
    hasRoomFor=function() return true end
}
local destEndpoint={
    id='crate-1',
    container=destContainer,
    object={getSquare=function() return crateSquare end}
}
registry.resolve=function(id)
    if id=='crate-1' then return destEndpoint end
    return nil
end

local fakeItem={
    id=501,
    container=nil,
    getID=function(s) return s.id end,
    getContainer=function(s) return s.container end
}

-- Attempt return when item is NOT in destination
local completeOk,completeErr=Store.completeCustodyReturn(custody.id,'return-job-1','crate-1',fakeItem)
check(not completeOk and completeErr=='ITEM_NOT_IN_DESTINATION','return rejected when item not in destination')

-- Now item is physically moved into destination container
fakeItem.container=destContainer
table.insert(destItems.items,fakeItem)

completeOk,completeErr=Store.completeCustodyReturn(custody.id,'return-job-1','crate-1',fakeItem)
check(completeOk,'completeCustodyReturn succeeds when physically in destination')
check(Store.custodyByItem(501)==nil,'custody record removed on successful return')
check(Store.canClaimTool('2',501),'claim released, other NPC can now claim tool 501')

-- =========================================================================
-- 3. Multi-Tool Atomic Rollback (Step 0)
-- =========================================================================
-- Setup two tools: 601 (free) and 602 (already claimed by NPC 2)
local npc2Custody=Store.claimCustody('2',602,'AXE',nil,'other-job')
check(npc2Custody~=nil,'npc2 holds tool 602')

local FieldProviders=require 'EmberRoutesProbe/Field/FieldProviders'
local cleaningDef=FieldProviders.get('cleaning')
-- Mock supply discovery returning 2 tools: 601 (available) and 602 (conflict)
local mockSupplies={
    requirements={
        {role='TOOL_MOP',item={getID=function() return 601 end},endpoint={id='c1'}},
        {role='TOOL_SOAP',item={getID=function() return 602 end},endpoint={id='c2'}}
    }
}
package.loaded['EmberRoutesProbe/Field/ToolDiscovery']={
    findSupplies=function() return mockSupplies end
}

local mockNpc={
    id='3',
    getDescriptor=function() return {getID=function() return '3' end} end,
    getInventory=function() return {getFirstEvalRecurse=function() return nil end} end,
    getPrimaryHandItem=function() return nil end,
    getSecondaryHandItem=function() return nil end
}
currentNpcMap['3']=mockNpc

local res=cleaningDef.claim({key='stain-1',point={x=5,y=5,z=0,kind='STAIN'}},'3','job-3',{actor=fakeActor,entry={id='home'}})
check(res~='QUEUED' and res~='STARTED','claim failed due to 602 conflict')
-- Check that 601 was NOT left as an orphan custody for NPC 3!
check(Store.custodyByItem(601)==nil,'first tool custody 601 safely rolled back upon multi-tool failure')

-- =========================================================================
-- 4. ToolReturnProvider 30s Idle Dispatch
-- =========================================================================
local Provider=require 'EmberRoutesProbe/Field/ToolReturnProvider'
Provider.reconcile()

-- Claim a tool for NPC 1
local tool701=Store.claimCustody('1',701,'MOP','crate-1',nil)
tool701.state='HELD'

local candidates={}
local envDiscover={
    npcId='1',
    now=1000,
    entry={id='home'},
    candidates=candidates,
    candidateReady=function() return true end,
    upsertOffer=function(k,rev,cat,scope) return {key=k},rev end
}

-- At t=1000, first discovery records idle timestamp
Provider.discover(envDiscover)
Provider.reconcile()
check(#candidates==0,'no candidate offered immediately on first idle observation')

-- At t=20000 (20s later), still under 30s threshold
envDiscover.now=20000
Provider.discover(envDiscover)
check(#candidates==0,'no candidate offered at 20 seconds idle')

-- At t=35000 (34s after initial idle), threshold passed!
envDiscover.now=35000
Provider.discover(envDiscover)
check(#candidates==1,'candidate offered after 30 seconds idle')
check(candidates[1].category=='toolReturn','candidate category is toolReturn')
check(candidates[1].priority==4,'candidate priority is 4')
check(candidates[1].custodyId==tool701.id,'candidate references correct custody')

-- =========================================================================
-- 5. ToolReturnService Execution & Single Body Control
-- =========================================================================
local Service=require 'EmberRoutesProbe/Field/ToolReturnService'
Service.reconcile()

local invItems={}
local npcInv={
    getItems=function() return {size=function() return #invItems end,get=function(_,i) return invItems[i+1] end,
        contains=function(_,item) for _,v in ipairs(invItems) do if v==item then return true end end return false end} end,
    getFirstEvalRecurse=function(_,fn)
        for _,it in ipairs(invItems) do if fn(it) then return it end end
        return nil
    end
}
local mopItem={
    id=701,
    container=npcInv,
    getID=function(s) return s.id end,
    getContainer=function(s) return s.container end
}
table.insert(invItems,mopItem)

local fakeNpc={
    id='1',
    isDead=function() return false end,
    getInventory=function() return npcInv end,
    getCurrentSquare=function() return {canReachTo=function() return true end} end,
    getX=function() return 10 end,
    getY=function() return 10 end,
    getZ=function() return 0 end
}
currentNpcMap['1']=fakeNpc

local fakeActor={isDead=function() return false end}

-- Start return via service
local startOk,retJobId=Service.startFor(fakeActor,'1',tool701.id,'ret-job-1','home')
check(startOk,'ToolReturnService.startFor succeeds')
check(Service.canInterrupt('1'),'return task is interruptible before transfer commitment')

-- Tick 1: transitions APPROACH -> TRANSFER
submittedSpec.tick()
check(submittedSpec.finished()==false,'not finished yet')

-- Tick 2: dispatches transfer action via body.add (NOT direct queue!)
submittedSpec.tick()
check(actionAdded~=nil,'action dispatched through body.add')
check(not Service.canInterrupt('1'),'canInterrupt is false once transfer action committed')
check(actionAdded:isValid(),'queued transfer is valid while custody and destination remain authorized')
registry.accepts=function() return false end
check(not actionAdded:isValid() and not actionAdded:transferItem(mopItem),'destination filter is revalidated at native effect boundary')
registry.accepts=function() return true end

-- Move item to destination storage
destItems.items={}
mopItem.container=destContainer
table.insert(destItems.items,mopItem)

-- Tick 3: verifies arrival and completes
submittedSpec.tick()
check(submittedSpec.finished()==true,'task finished after physical arrival confirmed')
check(Store.custodyByItem(701)~=nil,'custody retained until physical stop receipt')
ISTimedActionQueue={queues={}}
local stoppedNative=false
local stopCalls=0
local function stopAdapter(spec,npc)
    local controller={
        inspect=function() return {state='STOPPING',npcId=spec.npcId,jobId=spec.jobId} end,
        bodySnapshot=function() return {available=true,nativeStopped=stoppedNative} end,
        stopBody=function() stopCalls=stopCalls+1 return true end
    }
    return spec.stopAdapter(controller,function() return {} end)
end
local doneAdapter=stopAdapter(submittedSpec,fakeNpc)
check(doneAdapter.requestStop('COMPLETED'),'completion requests actual body stop')
check(not doneAdapter.observeStop().bodyStopped,'moving body is not confirmed stopped')
stoppedNative=true
check(doneAdapter.persistEffects(doneAdapter.observeStop()),'completion persists after actual stop')
check(Store.custodyByItem(701)==nil,'custody cleared only after stop')

-- =========================================================================
-- 6. Safe Interrupt & Preemption by Higher-Priority Work (Step 5)
-- =========================================================================
Service.reconcile()
-- Claim tool 801 for NPC 1
local tool801=Store.claimCustody('1',801,'MOP','crate-1',nil)
tool801.state='HELD'
local mop801={
    id=801,
    container=npcInv,
    getID=function(s) return s.id end,
    getContainer=function(s) return s.container end
}
invItems={mop801}

Service.startFor(fakeActor,'1',tool801.id,'ret-job-801','home')
check(tool801.state=='PENDING_RETURN','custody is in PENDING_RETURN')
check(Service.canInterrupt('1'),'interruptible during approach')

-- Preempt by high-priority work
local intOk=Service.interrupt('1','PREEMPTED_BY_CLEANING')
check(intOk,'interrupt succeeded')
check(tool801.state=='PENDING_RETURN','interrupt retains custody until stopped')
local interrupted=stopAdapter(submittedSpec,fakeNpc)
stoppedNative=false
check(interrupted.requestStop('PREEMPTED_BY_CLEANING'),'interruption requests native stop')
check(stopCalls==2,'both completion and interruption reach controller stop')
check(not interrupted.observeStop().bodyStopped,'interruption waits for native stop')
stoppedNative=true
ISTimedActionQueue.queues[fakeNpc]={queue={{}},current={}}
check(not interrupted.observeStop().bodyStopped,'queued native action prevents release')
ISTimedActionQueue.queues[fakeNpc]={queue={},current=nil}
check(interrupted.persistEffects(interrupted.observeStop()),'custody is settled after queue and body stop')
check(submittedSpec.persistFailure({bodyStopped=true}),'stop persistence is idempotent on execution-error path')
check(tool801.state=='HELD','aborted return restored custody to HELD')
check(tool801.returnJobId==nil,'returnJobId cleared')
check(Store.validToolUse('1','clean-job-new',801)==false,'not assigned yet')
Store.assignToolUse(tool801.id,'clean-job-new')
check(Store.validToolUse('1','clean-job-new',801),'tool immediately usable by new job without warehouse visit')

-- Pending requests can cancel without a body; active ones must wait for stop.
local tool802=Store.claimCustody('1',802,'MOP','crate-1',nil)
tool802.state='HELD'
local mop802={getID=function() return 802 end,getContainer=function() return npcInv end}
invItems={mop801,mop802}
delayStart=true
check(Service.startFor(fakeActor,'1',tool802.id,'ret-job-802','home'),'pending return submitted')
check(Service.interrupt('1','CANCEL_PENDING'),'pending return cancelled')
check(tool802.state=='HELD' and tool802.returnJobId==nil,'unstarted request restores held custody')
check(Service.liveTask('1')==nil,'pending cancellation has no orphan live task')
local tool804=Store.claimCustody('1',804,'MOP','crate-1',nil)
tool804.state='HELD'
local mop804={getID=function() return 804 end,getContainer=function() return npcInv end}
invItems={mop801,mop804}
check(Service.startFor(fakeActor,'1',tool804.id,'ret-job-804','home'),'pending save-cancel candidate submitted')
terminalHandle={state='PENDING'}
Service.reconcile()
check(tool804.state=='PENDING_RETURN','pending status alone cannot release custody')
terminalHandle={state='CANCELLED'}
Service.reconcile()
check(tool804.state=='HELD' and Service.liveTask('1')==nil,'terminal unstarted request cleans up after save cancellation')
terminalHandle=nil
delayStart=false

-- Missing originals keep durable reconciliation responsibility after physical stop.
local tool803=Store.claimCustody('1',803,'MOP','crate-1',nil)
tool803.state='HELD'
local mop803={container=npcInv,getID=function() return 803 end,getContainer=function(self) return self.container end}
invItems={mop801,mop803}
check(Service.startFor(fakeActor,'1',tool803.id,'ret-job-803','home'),'return with later missing original submitted')
mop803.container=nil
local missing=stopAdapter(submittedSpec,fakeNpc)
check(missing.requestStop('SAVE'),'missing original does not prevent physical stop')
local missingFact=missing.observeStop()
check(missingFact.bodyStopped and missingFact.effects=='UNKNOWN','missing original remains unknown')
check(missing.persistEffects(missingFact),'unknown custody retained after stop')
check(tool803.state=='RECONCILE_REQUIRED' and not Store.canClaimTool('2',803),'unknown original stays claimed for reconciliation')

-- =========================================================================
-- 7. Membership Obligations & Recovery (Step 4)
-- =========================================================================
local MembershipRuntime=require 'EmberRoutesProbe/Settlement/MembershipRuntime'
local MembershipService=require 'EmberRoutesProbe/Settlement/MembershipService'

-- obligations() includes TOOL_CUSTODY
local obList=MembershipRuntime.obligations('1')
local foundCustody=false
for _,ob in ipairs(obList) do
    if ob.kind=='TOOL_CUSTODY' and ob.itemId==801 then foundCustody=true break end
end
check(foundCustody,'MembershipRuntime.obligations includes TOOL_CUSTODY')

-- advance() blocks leaving settlement with tool custody
local pendingFollow={kind='FOLLOW',requestId='req-f',expectedRevision=1,followSlot=0}
local rowMember={revision=1,factionId='f',settlementId='home',context='SETTLEMENT'}
local blockedAdvance=MembershipService.advance('1',fakeActor,obList,false)
-- S.advance with active obligations blocks
check(not blockedAdvance,'MembershipService.advance blocks when obligations present')

-- =========================================================================
-- 8. Death & Save Recovery Handling (Step 6)
-- =========================================================================
-- Existing death contract releases claims without moving physical originals.
local deadCount=Store.settleNpcDeath('1')
check(deadCount>=1,'settled deceased NPC custody claims')
check(Store.custodyByItem(801)==nil,'death settles custody under current contract')
check(Store.canClaimTool('2',801),'death releases claim without moving the physical tool')

-- World reload recovery test
local entry901={
    format=1,
    id='custody:9:901',
    npcId='9',
    itemId=901,
    role='AXE',
    state='PENDING_RETURN',
    sequence=1,
    returnJobId='old-ret-job',
    claims={'item:901'}
}
local reloadRoot={
    taskJobs={format=1,byId={}},
    toolCustody={
        byId={['custody:9:901']=entry901},
        byNpc={['9']={['custody:9:901']=entry901}},
        byItem={[901]=entry901}
    }
}
registry.data=function() return reloadRoot end
local reloadedLedger=Store.data()
local reloadedCustody=reloadRoot.toolCustody.byId['custody:9:901']
check(reloadedCustody.state=='PENDING_RETURN','loading cannot assume pending transfer never happened')
check(reloadedCustody.returnJobId=='old-ret-job','loading preserves the unresolved return identity')
check(not Store.canClaimTool('9',901),'unverified pending return cannot authorize new labour')

-- Save between physical PUT and custody settlement: restore via a stop-only session.
Service.reconcile()
local recoveringNpc={id='9',isDead=fakeNpc.isDead,getInventory=fakeNpc.getInventory,
    getCurrentSquare=fakeNpc.getCurrentSquare,getX=fakeNpc.getX,getY=fakeNpc.getY,getZ=fakeNpc.getZ}
currentNpcMap['9']=recoveringNpc
local arrivedCustody=Store.claimCustody('9',902,'AXE','crate-1',nil)
arrivedCustody.state='HELD'
check(Store.assignToolReturn(arrivedCustody.id,'saved-return-902',
    {format=1,jobId='saved-return-902',destinationId='crate-1',scopeId='home'}),'record exact return destination')
local arrivedItem={getID=function() return 902 end,getContainer=function() return destContainer end}
destItems.items={arrivedItem} invItems={}
local beforeActions=#bodyActions
check(Service.startFor(fakeActor,'9',arrivedCustody.id,'saved-return-902','home',{trackResult=true}),'recovery accepts original already in saved destination')
submittedSpec.tick()
check(#bodyActions==beforeActions,'recovery never repeats transfer action')
check(Store.custodyByItem(902)~=nil,'arrival alone cannot clear custody before stop')
local restored=stopAdapter(submittedSpec,recoveringNpc)
check(restored.requestStop('LOAD_RECOVERY'),'recovery requests actual stop')
check(restored.persistEffects(restored.observeStop()),'known arrival settles after native/Lua stop')
check(Store.custodyByItem(902)==nil and Service.returnResult('saved-return-902').knownStopped,'recovered original and known stop are available for directory settlement')
Service.forgetResult('saved-return-902')

-- A Provider-owned return cancelled while still carrying must release its old Offer.
Service.reconcile() Provider.reconcile()
local tc=Store.claimCustody('1',1001,'MOP','crate-1',nil) tc.state='HELD'
local tool={getID=function() return 1001 end,getContainer=function() return npcInv end}
invItems={tool}
local dir=require('EmberRoutesProbe/Kernel/TaskDirectory').new()
local key='toolReturn:'..tc.id
dir:upsert(key,1,'toolReturn','home') assert(dir:claim(key,1,'1','return-directory'))
check(Provider.claim({key=key,custodyId=tc.id},'1','return-directory',{actor=fakeActor,entry={id='home'},directory=dir})=='STARTED','provider owns accepted directory allocation')
check(Service.interrupt('1','PREEMPTED'),'provider return interrupted')
local cancelled=stopAdapter(submittedSpec,fakeNpc)
check(cancelled.requestStop('PREEMPTED') and cancelled.persistEffects(cancelled.observeStop()),'cancelled attempt has actual stop and held-original evidence')
Provider.advance({actor=fakeActor,now=1000,directory=dir})
check(dir:upsert(key,2,'toolReturn','home').jobId==nil,'known cancellation releases old directory allocation')
check(Store.custodyByItem(1001)~=nil,'directory release does not release held tool responsibility')
check(Service.returnResult('return-directory')==nil,'consumed directory evidence does not accumulate')

assert(dir:claim(key,2,'1','return-directory-again'))
check(Provider.claim({key=key,custodyId=tc.id},'1','return-directory-again',{actor=fakeActor,entry={id='home'},directory=dir})=='STARTED',
    'same custody can be dispatched again after known cancellation')
invItems={}
local unknownStop=stopAdapter(submittedSpec,fakeNpc)
check(unknownStop.requestStop('SAVE') and unknownStop.persistEffects(unknownStop.observeStop()),'missing original produces a retained stopped result')
Provider.advance({actor=fakeActor,now=6000,directory=dir})
check(dir:upsert(key,3,'toolReturn','home').jobId=='return-directory-again','unknown outcome cannot release directory')
check(not Store.canClaimTool('1',1001) and not Store.assignToolUse(tc.id,'new-job'),'same carrier cannot use unresolved custody')
check(Store.claimCustody('1',1001,'MOP',nil,'new-job')==nil,'new claim cannot bypass unresolved custody state')

-- Recover that exact intent once the original becomes observable at its destination.
destItems.items={tool}
tool.getContainer=function() return destContainer end
local beforeRecoveryActions=#bodyActions
check(Service.recoverFor(fakeActor,'1'),'unknown return has a controlled observation recovery')
submittedSpec.tick()
local resolved=stopAdapter(submittedSpec,fakeNpc)
check(resolved.requestStop('RECOVERY') and resolved.persistEffects(resolved.observeStop()),'recovered original settles only after actual stop')
Provider.advance({actor=fakeActor,now=11000,directory=dir})
check(dir:upsert(key,4,'toolReturn','home').jobId==nil and Store.custodyByItem(1001)==nil,'known recovered arrival clears original and old directory allocation')
check(#bodyActions==beforeRecoveryActions,'recovering unknown return never replays PUT')

local priorWorld=reloadRoot
local otherDirectory=require('EmberRoutesProbe/Kernel/TaskDirectory').new()
otherDirectory:upsert(key,1,'toolReturn','other-world') assert(otherDirectory:claim(key,1,'1','new-world-job'))
registry.data=function() return {} end
Provider.advance({actor=fakeActor,now=16000,directory=otherDirectory})
check(otherDirectory:upsert(key,2,'toolReturn','other-world').jobId=='new-world-job','old-world callbacks cannot release new-world allocation')
check(priorWorld.toolCustody.byId['custody:9:901']~=nil,'world switch cannot clear old persistent responsibility')

print(string.format('PASS %d Stage 2 tool return, custody lifecycle & recovery checks',n))
