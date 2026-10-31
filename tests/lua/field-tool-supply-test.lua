-- Field tool supply integration test (Phase 1B).
-- Verifies autonomous fetching of tools from settlement warehouse containers,
-- ISInventoryTransferAction execution, phase transition from PREPARE to WORK,
-- and preservation of custody claims through job completion.

local n=0
local function check(v,msg) n=n+1 assert(v,msg) end

local root={}
local registry={data=function() return root end,id=function() return 'claim-1' end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=registry
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return root end}
package.loaded['EmberRoutesProbe/SettlementZones']={revision=function() return 1 end}
package.loaded['EmberRoutesProbe/JobPolicyService']={get=function() return {} end}
package.loaded['EmberRoutesProbe/MembershipService']={
    check=function() return {allowed=true,entryRevision=1} end,
    entry=function() return {id='settlement-1',areas={{x=0,y=0,w=10,h=10}}},nil,1 end,
    view=function() return {settlementId='settlement-1',context='SETTLEMENT'} end
}
getCell=function()
    return {
        getGridSquare=function(_,x,y,z) return crateSquare end,
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

-- Mock NPC and World Inventory Item
local npcInvItems={}
local npcInv={
    getItems=function() return {contains=function(_,it) for _,x in ipairs(npcInvItems) do if x==it then return true end end return false end,size=function() return #npcInvItems end,get=function(_,i) return npcInvItems[i+1] end} end,
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
    getSecondaryHandItem=function() return nil end
}

-- Mock Warehouse Container and Crate Item
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
    getItems=function() return {size=function() return #crateItems end,get=function(_,i) return crateItems[i+1] end,contains=function(_,it) for _,x in ipairs(crateItems) do if x==it then return true end end return false end} end,
    hasRoomFor=function() return true end
}
mopItem.container=crateContainer
bleachItem.container=crateContainer

local crateSquare={getX=function() return 5 end,getY=function() return 5 end,getZ=function() return 0 end,canReachTo=function() return true end}
local crateObject={getSquare=function() return crateSquare end}
local crateEndpoint={id='crate-1',object=crateObject,container=crateContainer}

registry.resolve=function(id,intent)
    if id=='crate-1' then return crateEndpoint end
    return nil
end
registry.revalidate=function() return true end
registry.logistics=function() return 'STORAGE' end
registry.inventoryChanged=function() end

local entry={id='settlement-1',areas={{x=0,y=0,w=10,h=10}}}
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

-- Native action stub for Kahlua test
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

local stainPoint={x=5,y=5,z=0,identity='stain-101'}
package.loaded['EmberRoutesProbe/FieldDiscovery']={
    claim=function(pt) return {kind='STAIN',x=pt.x,y=pt.y,z=pt.z,identity=pt.identity},{'field-target:'..pt.identity} end,
    policy=function() return {} end,
    allowed=function() return true end,
    targets=function() return {stainPoint} end,
    object=function() return true end
}

local Store=require 'EmberRoutesProbe/LaborStore'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Field=require 'EmberRoutesProbe/FieldWork'
local ToolDiscovery=require 'EmberRoutesProbe/ToolDiscovery'
local FieldSupplies=require 'EmberRoutesProbe/FieldSupplies'
local ToolReq=require 'EmberRoutesProbe/ToolRequirements'
local Providers=require 'EmberRoutesProbe/FieldProviders'

-- 1. Verify ToolDiscovery detects warehouse supplies when inventory is empty
local supplies=ToolDiscovery.findSupplies(entry,npc,'STAIN')
check(supplies~=nil,'supplies found in warehouse')
check(not supplies.ready,'tools not yet in worker inventory')
check(#supplies.requirements==2,'found both mop and bleach')
check(supplies.requirements[1].inInventory==false,'mop in warehouse')
check(supplies.requirements[2].inInventory==false,'bleach in warehouse')

-- 2. Retrieve cleaning provider

local cleaningProvider=Providers.get('cleaning')
check(cleaningProvider~=nil,'cleaning provider retrieved')

-- Claim the work through real Field provider
local claimRes=cleaningProvider.claim({key='offer-1',point=stainPoint},'1','job-100',{actor=npc,entry=entry})
local j=Jobs.current():get('job-100')
check(j~=nil,'job created through provider claim')
check(j.payload.phase=='PREPARE','job initial phase is PREPARE')
check(j.payload.toolSupply~=nil,'toolSupply attached to job payload')
check(#j.payload.toolSupply.requirements==2,'two tool supply requirements recorded')

-- Verify that ToolCustody records are created in RESERVED state and assigned
local custodyMop=Store.custodyByItem(301)
local custodyBleach=Store.custodyByItem(302)
check(custodyMop~=nil and custodyMop.state=='RESERVED','mop custody created in RESERVED')
check(custodyBleach~=nil and custodyBleach.state=='RESERVED','bleach custody created in RESERVED')
check(custodyMop.activeJobId=='job-100','custody assigned to job-100')

local token=Store.claimField(j)
check(token~=nil,'field claim acquired')

-- 4. Execute FieldSupplies.step to transfer items into worker inventory
local lastAction=nil
local mockContext
mockContext={
    npc=npc,
    job=j,
    token=token,
    valid=function() return true end,
    same=function() return Store.validField(mockContext.job,mockContext.token) end,
    unknown=function(why) mockContext.reason=why return false end,
    change=function(fn)
        local cur=Jobs.current():get(mockContext.job.id)
        fn(cur)
        local ok,value=Store.replaceField(mockContext.job,mockContext.token,cur)
        if not ok then return false end
        mockContext.job=value
        return true
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

-- Run step: transfers first item (mop)
local step1=FieldSupplies.step(mockContext)
check(step1=='Running' and mockContext.node~=nil,'step 1 initiates transfer node')
local run1=mockContext.node.run()
check(run1=='Running','first item transfer action queued')
if lastAction and lastAction.transferItem then lastAction:transferItem(mopItem) end
if lastAction and lastAction.perform then lastAction:perform() end
local runState1=mockContext.node.run()
check(runState1=='Success','transfer 1 succeeds')
check(custodyMop.state=='HELD','mop custody updated to HELD')

-- Run step: transfers second item (bleach)
mockContext.node=nil
local step2=FieldSupplies.step(mockContext)
check(step2=='Running' and mockContext.node~=nil,'step 2 initiates transfer node')
local run2=mockContext.node.run()
check(run2=='Running','second item transfer action queued')
if lastAction and lastAction.transferItem then lastAction:transferItem(bleachItem) end
if lastAction and lastAction.perform then lastAction:perform() end
local runState2=mockContext.node.run()
check(runState2=='Success','transfer 2 succeeds')
check(custodyBleach.state=='HELD','bleach custody updated to HELD')

-- Run step: all items in inventory -> transitions phase to WORK!
mockContext.node=nil
local step3=FieldSupplies.step(mockContext)
check(step3=='Running','step 3 transitions phase')
check(mockContext.job.payload.phase=='WORK','job phase successfully transitioned to WORK')
check(mockContext.job.payload.toolSupply==nil,'toolSupply cleared after successful pickup')

-- 5. Complete and Settle the job
mockContext.change(function(cur)
    cur.payload.phase='SETTLED'
    cur.state='DONE'
    cur.obligations={}
    cur.payload.claims={}
end)
Store.finishField(mockContext.job)

-- Verify custody and claims remain intact after job settlement (NO ORPHAN / NO LEAK)
check(Store.custodyByItem(301)~=nil,'mop custody persists after job settlement')
check(Store.custodyByItem(302)~=nil,'bleach custody persists after job settlement')
check(Store.validToolUse('1','job-100',301),'mop remains lawfully held by NPC 1')

print(string.format('PASS %d field tool supply integration checks',n))
