-- Field continuous batch and cross-job tool retention test (Phase 1C).
-- Verifies:
-- 1. Continuous batching: after completing target 1, continue() automatically picks up
--    adjacent target 2 without returning tools or fetching again (zero warehouse roundtrips).
-- 2. Tool retention: after Job 1 settles, tools remain securely held in ToolCustody.
-- 3. Cross-job reuse: a subsequent independent Job 2 claims a distant target and directly
--    reuses existing held tools with phase='WORK' (0 warehouse visits).

local n=0
local function check(v,msg) n=n+1 assert(v,msg) end
getTimestampMs=function() return 1000 end

local root={}
local registry={data=function() return root end,id=function() return 'claim-1' end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=registry
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}
package.loaded['EmberRoutesProbe/SettlementLedger']={
    data=function() return root end,
    get=function() return {id='settlement-1',areas={{x=0,y=0,w=30,h=30}}} end
}
package.loaded['EmberRoutesProbe/SettlementZones']={revision=function() return 1 end}
package.loaded['EmberRoutesProbe/JobPolicyService']={get=function() return {} end}
package.loaded['EmberRoutesProbe/MembershipService']={
    check=function() return {allowed=true,entryRevision=1} end,
    entry=function() return {id='settlement-1',areas={{x=0,y=0,w=30,h=30}}},nil,1 end,
    view=function() return {settlementId='settlement-1',context='SETTLEMENT'} end
}
package.loaded['EmberRoutesProbe/PublicWork']={
    priorities=function() return {cleaning=2,lumberjack=3,farming=3,forager=3} end
}

local crateSquare={getX=function() return 5 end,getY=function() return 5 end,getZ=function() return 0 end,canReachTo=function() return true end}
local stain1Square={getX=function() return 6 end,getY=function() return 5 end,getZ=function() return 0 end,canReachTo=function() return true end}
local stain2Square={getX=function() return 7 end,getY=function() return 5 end,getZ=function() return 0 end,canReachTo=function() return true end}
local stain3Square={getX=function() return 20 end,getY=function() return 20 end,getZ=function() return 0 end,canReachTo=function() return true end}

getCell=function()
    return {
        getGridSquare=function(_,x,y,z)
            if x==5 and y==5 then return crateSquare end
            if x==6 and y==5 then return stain1Square end
            if x==7 and y==5 then return stain2Square end
            if x==20 and y==20 then return stain3Square end
            return crateSquare
        end,
        getChunk=function() return nil end
    }
end

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

ItemTag={CHOP_TREE='ChopTree',CLEAN_STAINS='CleanStains',MOP='Mop',BROOM='Broom',DIG_PLOW='DigPlow'}
Fluid={Bleach='Bleach',CleaningLiquid='CleaningLiquid'}

-- Mock NPC and Worker Inventory
local npcInvItems={}
local npcInv={
    getItems=function()
        return {
            contains=function(_,it) for _,x in ipairs(npcInvItems) do if x==it then return true end end return false end,
            size=function() return #npcInvItems end,
            get=function(_,i) return npcInvItems[i+1] end
        }
    end,
    getFirstEvalRecurse=function(_,eval) for _,it in ipairs(npcInvItems) do if eval(it) then return it end end return nil end,
    hasRoomFor=function() return true end,
    isInCharacterInventory=function() return true end
}
local npcSquare={getX=function() return 5 end,getY=function() return 5 end,getZ=function() return 0 end,canReachTo=function() return true end}
local npc={
    getDescriptor=function() return {getID=function() return 1 end} end,
    getInventory=function() return npcInv end,
    getCurrentSquare=function() return npcSquare end,
    getX=function() return 5 end,getY=function() return 5 end,getZ=function() return 0 end,
    isDead=function() return false end,
    isDraggingCorpse=function() return false end,
    getPrimaryHandItem=function() return nil end,
    getSecondaryHandItem=function() return nil end,
    getStats=function() return nil end
}

-- Mock Warehouse Container and Items
local mopItem={
    id=301,
    getID=function() return 301 end,
    getFullType=function() return 'Base.Mop' end,
    isBroken=function() return false end,
    hasTag=function(_,tag) return tag==ItemTag.CLEAN_STAINS or tag==ItemTag.MOP end,
    container=nil,
    getContainer=function(self) return self.container end
}
local bleachItem={
    id=302,
    getID=function() return 302 end,
    getFullType=function() return 'Base.Bleach' end,
    isBroken=function() return false end,
    hasTag=function() return false end,
    getFluidContainer=function()
        return {
            contains=function(_,fluid) return fluid==Fluid.Bleach end,
            getAmount=function() return 1.0 end
        }
    end,
    container=nil,
    getContainer=function(self) return self.container end
}

local crateItems={mopItem,bleachItem}
local crateContainer={
    getItems=function()
        return {
            size=function() return #crateItems end,
            get=function(_,i) return crateItems[i+1] end,
            contains=function(_,it) for _,x in ipairs(crateItems) do if x==it then return true end end return false end
        }
    end,
    hasRoomFor=function() return true end
}
mopItem.container=crateContainer
bleachItem.container=crateContainer

local crateObject={getSquare=function() return crateSquare end}
local crateEndpoint={id='crate-1',object=crateObject,container=crateContainer}

registry.resolve=function(id,intent)
    if id=='crate-1' then return crateEndpoint end
    return nil
end
registry.revalidate=function() return true end
registry.logistics=function() return 'STORAGE' end
registry.inventoryChanged=function() end

local entry={id='settlement-1',areas={{x=0,y=0,w=30,h=30}}}
package.loaded['EmberRoutesProbe/SettlementMembership']={
    query=function() return {'crate-1'} end
}
package.loaded['EmberRoutesProbe/SettlementGeometry']={
    inside=function() return true end
}
package.loaded['EmberRoutesProbe/WorkTransfer']={
    reachable=function() return true end,
    prepareMove=function() return {square=crateSquare} end
}
package.loaded['EmberRoutesProbe/Driver']={
    valid=function() return true end,
    same=function() return true end,
    unknown=function() return false end,
    bindId=function() return {id=1,handle=npc} end
}
package.loaded['EmberRoutesProbe/TaskRuntime']={
    current=function()
        return {
            accepting=function() return true end,
            owns=function() return false end,
            status=function() return nil end,
            submit=function() return true end
        }
    end
}

local queuedAction=nil
ISInventoryTransferAction={
    new=function(_,c_npc,item,from,to,time)
        return {
            npc=c_npc,item=item,from=from,to=to,time=time,
            isStarted=function() return true end,
            isValid=function() return true end,
            stop=function() queuedAction=nil end,
            transferItem=function(self,it)
                it.container=to
                npcInvItems[#npcInvItems+1]=it
                for idx,x in ipairs(crateItems) do if x==it then table.remove(crateItems,idx) break end end
                return true
            end,
            perform=function() queuedAction=nil end
        }
    end
}
ISTimedActionQueue={hasAction=function(a) return queuedAction==a and a~=nil end}

-- Stains: Stain 1 at (6,5), Stain 2 at (7,5) [adjacent], Stain 3 at (20,20) [distant]
local stain1Point={kind='STAIN',x=6,y=5,z=0,identity='stain-101'}
local stain2Point={kind='STAIN',x=7,y=5,z=0,identity='stain-102'}
local stain3Point={kind='STAIN',x=20,y=20,z=0,identity='stain-103'}

local activeStains={stain1Point,stain2Point,stain3Point}

package.loaded['EmberRoutesProbe/FieldDiscovery']={
    claim=function(pt)
        return {kind='STAIN',x=pt.x,y=pt.y,z=pt.z,identity=pt.identity},{'field-target:'..pt.identity}
    end,
    policy=function() return {continuousBatch=true,maxContinuousBatch=4} end,
    allowed=function() return true end,
    targets=function() return activeStains end,
    object=function(t) return true end
}

local Store=require 'EmberRoutesProbe/LaborStore'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Field=require 'EmberRoutesProbe/FieldWork'
local ToolDiscovery=require 'EmberRoutesProbe/ToolDiscovery'
local FieldSupplies=require 'EmberRoutesProbe/FieldSupplies'
local Providers=require 'EmberRoutesProbe/FieldProviders'

-- =========================================================================
-- Part 1: Initial Job 1 - Autonomous Tool Fetch & Stain 1 Execution
-- =========================================================================
local cleaningProvider=Providers.get('cleaning')
check(cleaningProvider~=nil,'cleaning provider exists')

local claimRes=cleaningProvider.claim({key='offer-1',point=stain1Point},'1','job-1',{actor=npc,entry=entry})
check(claimRes=='QUEUED','job-1 queued')

local j1=Jobs.current():get('job-1')
check(j1~=nil,'job-1 record created')
check(j1.payload.phase=='PREPARE','job-1 initial phase is PREPARE')
check(j1.payload.toolSupply~=nil,'toolSupply exists for job-1')

local token1=Store.claimField(j1)
check(token1~=nil,'token1 acquired for job-1')

local lastAction=nil
local context1
context1={
    npc=npc,
    job=j1,
    token=token1,
    valid=function() return true end,
    same=function() return Store.validField(context1.job,context1.token) end,
    unknown=function(why) context1.reason=why return false end,
    change=function(fn)
        local cur=Jobs.current():get(context1.job.id)
        fn(cur)
        local ok,val=Store.replaceField(context1.job,context1.token,cur)
        if ok then context1.job=val end
        return ok
    end,
    body={
        snapshot=function() return {nativeStopped=true} end,
        stop=function() return true end,
        current=function() return true end,
        retained=function() return true end,
        add=function(act) lastAction=act queuedAction=act return true end
    },
    move=function() return 'Success' end
}

-- Fetch Mop (Item 1)
FieldSupplies.step(context1)
context1.node.run()
lastAction:transferItem(mopItem)
lastAction:perform()
context1.node.run()

-- Fetch Bleach (Item 2)
context1.node=nil
FieldSupplies.step(context1)
context1.node.run()
lastAction:transferItem(bleachItem)
lastAction:perform()
context1.node.run()

-- Transition to WORK
context1.node=nil
FieldSupplies.step(context1)
check(context1.job.payload.phase=='WORK','job-1 transitioned to WORK')
check(context1.job.payload.toolSupply==nil,'job-1 toolSupply cleared')

local custodyMop=Store.custodyByItem(301)
local custodyBleach=Store.custodyByItem(302)
check(custodyMop.state=='HELD' and custodyBleach.state=='HELD','tools are HELD in custody')

-- Stain 1 Work completes
check(Store.validToolUse('1','job-1',301),'mop valid for job-1')
check(Store.validToolUse('1','job-1',302),'bleach valid for job-1')

-- Remove stain 1 from active stains
table.remove(activeStains,1)

-- =========================================================================
-- Part 2: Continuous Batching - Immediate Transition to Stain 2
-- =========================================================================
-- Now def.continue(context1) is invoked when stain 1 finishes
local continued=cleaningProvider.continue(context1)
check(continued==true,'continuous batch continuation succeeded')
check(context1.job.payload.batchCount==2,'batchCount incremented to 2')
check(context1.job.payload.target.identity=='stain-102','target switched to stain-102')
check(context1.job.payload.phase=='WORK','continuous batch remains in WORK phase (0 warehouse visits)')
check(context1.job.payload.toolSupply==nil,'no toolSupply required for continuous batch')

-- Verify that resource lock for stain-101 was released and stain-102 is now claimed
check(Store.resourceOwner('field-target:stain-101')==nil,'stain-101 target lock released')
check(Store.resourceOwner('field-target:stain-102')~=nil,'stain-102 target lock acquired')
check(Store.resourceOwner('field-target:stain-102').taskId=='job-1','stain-102 owned by job-1')

-- Tools remain in worker custody throughout the batch switch
check(Store.validToolUse('1','job-1',301),'mop still authorized for continuous batch')
check(Store.validToolUse('1','job-1',302),'bleach still authorized for continuous batch')

-- Remove stain 2 from active stains (stain 2 cleaned)
table.remove(activeStains,1)

-- Try continue again: remaining stain-103 is at (20,20), which is >5 tiles away
local continueFar=cleaningProvider.continue(context1)
check(continueFar==false,'distant stain outside 5-tile radius rejected by continuous batch')

-- Settle Job 1
context1.change(function(cur)
    cur.payload.phase='SETTLED'
    cur.state='SETTLING'
    cur.obligations={}
    cur.payload.claims={}
end)
context1.change(function(cur)
    cur.state='DONE'
end)
check(Store.finishField(context1.job),'job-1 finished cleanly')

-- CRITICAL CHECK: After Job 1 finishes, tools must NOT be orphaned or lose custody
check(Store.custodyByItem(301)~=nil,'mop custody persists after job-1 settlement')
check(Store.custodyByItem(302)~=nil,'bleach custody persists after job-1 settlement')
check(Store.custodyByItem(301).state=='HELD','mop remains in HELD state')
check(Store.custodyByItem(302).state=='HELD','bleach remains in HELD state')

-- =========================================================================
-- Part 3: Cross-Job Tool Retention - Job 2 Directly Reuses Tools
-- =========================================================================
-- Now Job 2 claims distant Stain 3 at (20,20)
local claimRes2=cleaningProvider.claim({key='offer-2',point=stain3Point},'1','job-2',{actor=npc,entry=entry})
check(claimRes2=='QUEUED','job-2 claimed and queued')

local j2=Jobs.current():get('job-2')
check(j2~=nil,'job-2 record created')
-- CRITICAL CHECK: Job 2 starts directly in WORK phase with 0 toolSupply requirements!
check(j2.payload.phase=='WORK','job-2 starts directly in WORK phase without warehouse trip!')
check(j2.payload.toolSupply==nil,'job-2 has no toolSupply requirements')

local token2=Store.claimField(j2)
check(token2~=nil,'token2 acquired for job-2')

-- Verify tool custody activeJobId was transferred to job-2
check(Store.custodyByItem(301).activeJobId=='job-2','mop activeJobId assigned to job-2')
check(Store.custodyByItem(302).activeJobId=='job-2','bleach activeJobId assigned to job-2')
check(Store.validToolUse('1','job-2',301),'mop validly authorized for job-2')
check(Store.validToolUse('1','job-2',302),'bleach validly authorized for job-2')

-- Settle Job 2
local context2
context2={
    npc=npc,
    job=j2,
    token=token2,
    change=function(fn)
        local cur=Jobs.current():get(j2.id)
        fn(cur)
        local ok,val=Store.replaceField(context2.job,context2.token,cur)
        if ok then context2.job=val end
        return ok
    end
}
context2.change(function(cur)
    cur.payload.phase='SETTLED'
    cur.state='SETTLING'
    cur.obligations={}
    cur.payload.claims={}
end)
context2.change(function(cur)
    cur.state='DONE'
end)
check(Store.finishField(context2.job),'job-2 finished cleanly')

-- Tool custody remains intact in HELD state on the NPC
check(Store.custodyByItem(301).state=='HELD','mop custody retained on worker')
check(Store.custodyByItem(302).state=='HELD','bleach custody retained on worker')

print('PASS '..n..' field continuous batch & tool retention checks')
