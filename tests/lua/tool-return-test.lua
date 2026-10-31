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
    inventoryChanged=function() end
}
package.loaded['EmberRoutesProbe/ContainerRegistry']=registry
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}
package.loaded['EmberRoutesProbe/Work']={record=function() end}
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
        return {character=char,item=item,src=src,dst=dst,time=time}
    end
}

ModData={getOrCreate=function(k) return {} end}
getTimestampMs=function() return 1000 end

local submittedSpec=nil
local actionAdded=nil
local bodyActions={}
local fakeBody={
    move=function() return true end,
    stop=function() return true end,
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
                spec.start(fakeBody)
                return {ticket=1}
            end,
            stop=function() return true end
        }
    end
}
package.loaded['EmberRoutesProbe/TaskRuntime']=fakeRuntime

local Store=require 'EmberRoutesProbe/LaborStore'
local CustodyRecord=require 'EmberRoutesProbe/ToolCustodyRecord'
local ReturnRecord=require 'EmberRoutesProbe/ToolReturnRecord'

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

local FieldProviders=require 'EmberRoutesProbe/FieldProviders'
local cleaningDef=FieldProviders.get('cleaning')
-- Mock supply discovery returning 2 tools: 601 (available) and 602 (conflict)
local mockSupplies={
    requirements={
        {role='TOOL_MOP',item={getID=function() return 601 end},endpoint={id='c1'}},
        {role='TOOL_SOAP',item={getID=function() return 602 end},endpoint={id='c2'}}
    }
}
package.loaded['EmberRoutesProbe/ToolDiscovery']={
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
local Provider=require 'EmberRoutesProbe/ToolReturnProvider'
Provider.reset()

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
local Service=require 'EmberRoutesProbe/ToolReturnService'
Service.reset()

local invItems={}
local npcInv={
    getItems=function() return {size=function() return #invItems end,get=function(_,i) return invItems[i+1] end} end,
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

-- Move item to destination storage
destItems.items={}
mopItem.container=destContainer
table.insert(destItems.items,mopItem)

-- Tick 3: verifies arrival and completes
submittedSpec.tick()
check(submittedSpec.finished()==true,'task finished after physical arrival confirmed')
check(Store.custodyByItem(701)==nil,'custody completely cleared in store')

-- =========================================================================
-- 6. Safe Interrupt & Preemption by Higher-Priority Work (Step 5)
-- =========================================================================
Service.reset()
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
check(tool801.state=='HELD','aborted return restored custody to HELD')
check(tool801.returnJobId==nil,'returnJobId cleared')
check(Store.validToolUse('1','clean-job-new',801)==false,'not assigned yet')
Store.assignToolUse(tool801.id,'clean-job-new')
check(Store.validToolUse('1','clean-job-new',801),'tool immediately usable by new job without warehouse visit')

-- =========================================================================
-- 7. Membership Obligations & Recovery (Step 4)
-- =========================================================================
local MembershipRuntime=require 'EmberRoutesProbe/MembershipRuntime'
local MembershipService=require 'EmberRoutesProbe/MembershipService'

-- obligations() includes TOOL_CUSTODY
local obList=MembershipRuntime.obligations('1')
local foundCustody=false
for _,ob in ipairs(obList) do
    if ob.kind=='TOOL_CUSTODY' and ob.itemId==801 then foundCustody=true break end
end
check(foundCustody,'MembershipRuntime.obligations includes TOOL_CUSTODY')

-- advance() blocks leaving settlement with tool custody
local pendingFollow={kind='FOLLOW',requestId='req-f',expectedRevision=1}
local rowMember={revision=1,factionId='f',settlementId='home',context='SETTLEMENT'}
local blockedAdvance=MembershipService.advance('1',fakeActor,obList,false)
-- S.advance with active obligations blocks
check(not blockedAdvance,'MembershipService.advance blocks when obligations present')

-- =========================================================================
-- 8. Death & Save Recovery Handling (Step 6)
-- =========================================================================
-- NPC death marks custody DEAD_CARRIER and does NOT release claim
local deadCount=Store.markNpcCustodiesDead('1')
check(deadCount>=1,'marked custodies dead for NPC 1')
check(tool801.state=='DEAD_CARRIER','custody transitioned to DEAD_CARRIER')
check(not Store.canClaimTool('2',801),'item 801 claim is NOT released on death (remains on corpse)')

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
check(reloadedCustody.state=='HELD','PENDING_RETURN reverted to HELD on load recovery')
check(reloadedCustody.returnJobId==nil,'returnJobId cleared on load recovery')
check(Store.canClaimTool('9',901),'claim ownership successfully restored after load')

print(string.format('PASS %d Stage 2 tool return, custody lifecycle & recovery checks',n))
