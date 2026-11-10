local Directory=require 'EmberRoutesProbe/Kernel/TaskDirectory'
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end

-- 1. Verify TaskDirectory claim & release invariants
local dir=Directory.new()
local offer=dir:upsert('delivery:order-1',1,'hauling','settlement-1')
check(offer and not offer.jobId,'fresh offer has no jobId')

-- 2. Verify leisure wake contract with PublicWork
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path

local root={} local now=1000
local inLeisure=true
local leisureReadyCount=0
local assigned=nil
local idleLeisureCount=0

local actor={getUsername=function() return 'player' end,isRecipeKnown=function() return true end,isDead=function() return false end}
local entry={id='settlement-1',revision=1}
local npcId='npc-1'

local npcObj={
    id=npcId,
    getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end,
    getCharacterActions=function() return {isEmpty=function() return not inLeisure end} end,
    getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end
}

package.loaded['EmberRoutesProbe/Kernel/Boot']={
    ready=true,runtimeReady=true,hasJava=function() return true end,
    careProbeWork=function(id) return id==npcId and inLeisure end,
    leisureWorkReady=function(id,targetJobId)
        leisureReadyCount=leisureReadyCount+1
    end,
    idleLeisure=function(id,e) idleLeisureCount=idleLeisureCount+1 end
}

package.loaded['EmberRoutesProbe/SelfCare/HealthAssessment']={canWork=function() return true end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() return 'job-uuid-1' end}
local ledgerData={priorities={}}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={
    view=function() return entry end,
    at=function() return {entry} end,
    data=function() return ledgerData end
}
package.loaded['EmberRoutesProbe/Settlement/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={
    bindId=function(_,id) return {handle=npcObj,id=id} end,
    suspended=function() return false end
}
package.loaded['EmberRoutesProbe/Cooking/CookingProvider']={retained=function() return false end}
package.loaded['EmberRoutesProbe/Field/FieldWork']={retained=function() return false end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {accepting=function() return true end,status=function() return nil end} end}
package.loaded['EmberRoutesProbe/Work/Work']={
    busy=function(id) return inLeisure end,
    hasCargo=function() return false end,
    allowAutomation=function() end,
    record=function() return nil end
}
package.loaded['EmberRoutesProbe/Settlement/Companion']={exportState=function() return {mode='HOLD'} end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Settlement/SettlementMembership']={query=function() return {'crate'} end}
package.loaded['EmberRoutesProbe/Work/LaborStore']={custodyForNpc=function() return {} end}
package.loaded['EmberRoutesProbe/Field/ToolReturnService']={
    canInterrupt=function() return false end,
    reconcile=function() end,
    returnResult=function() end,
    liveTask=function() end,
    forgetResult=function() end,
    startFor=function() end
}
package.loaded['EmberRoutesProbe/Field/FieldDemand']={advance=function() end}

function isClient() return false end
function isServer() return false end
function getTimestampMs() return now end
function getSpecificPlayer() return actor end
EmberRoutesProbeJava={workerCount=function() return 1 end,workerIdAt=function(i) return npcId end}

package.loaded['EmberRoutesProbe/Crafting/ProductionRecipe']={read=function() return {} end,inspect=function() return {} end}
package.loaded['EmberRoutesProbe/Crafting/CraftSurfaces']={resolve=function() return {} end}
package.loaded['EmberRoutesProbe/Work/BusinessJobs']={
    records=function() return {} end,
    crafts=function() return {} end,
    flush=function() end,
    record=function() return nil end,
    canRetire=function() return false end
}
package.loaded['EmberRoutesProbe/Crafting/ProductionChain']={new=function() return {step=function() return {nodes={}} end,cancel=function() end} end}
package.loaded['EmberRoutesProbe/Crafting/Production']={execute=function() return 'QUEUED' end}
package.loaded['EmberRoutesProbe/Logistics/LogisticsService']={publicOffer=function() return nil end,preparePublic=function() return true end}

local membershipRows=dofile('tests/lua/membership-fixture.lua')(function() return entry end,{npcId})

local Public=require 'EmberRoutesProbe/Work/PublicWork'
Public.prepareRecovery()

-- Register test delivery provider under hauling category
local testProvider={
    category='hauling',
    defaultPriority=3,
    discover=function(env)
        local o=env.upsertOffer('delivery:order-1',1,'hauling',env.entry.id)
        offer=o
        if o and not o.jobId then
            env.candidates[#env.candidates+1]={
                key='delivery:order-1',revision=1,category='hauling',allowed=true,score=1,delivery=true
            }
        end
    end,
    claim=function(selected,id,jobId,env)
        local claimedOffer=env.directory and env.directory:upsert(selected.key,selected.revision,selected.category,env.entry.id)
        assigned={selected=selected,npcId=id,jobId=jobId,offer=claimedOffer}
        return 'QUEUED'
    end,
    hasWork=function() return true end
}
Public.registerProvider(testProvider)
Public.setPriority(actor,entry.id,npcId,'hauling',1)

local function tick(step)
    now=now+(step or (require('EmberRoutesProbe/Kernel/TickConfig').discoveryIdleMs+1))
    Public.tick()
end

-- TEST STEP 1: NPC is in leisure (pushups / sitting)
inLeisure=true
tick() tick()

-- Verify:
-- 1. leisureWorkReady was called to wake the NPC up
check(leisureReadyCount==1,'leisureWorkReady notified on candidate discovery')
-- 2. Directory offer was reserved with a deterministic claim
local currentOffer=offer

check(currentOffer.jobId=='job-uuid-1' and currentOffer.npcId==npcId,'directory offer deterministically reserved for the worker during leisure probe')
-- 3. Job was NOT assigned while NPC was in leisure
check(assigned==nil,'job was not claimed while NPC in leisure')
-- 4. Idle leisure was NOT triggered (NPC was already in leisure)
check(idleLeisureCount==0,'idle leisure was not re-offered during probe')

-- TEST STEP 2: NPC has stopped leisure (inLeisure is false, 50ms later)
inLeisure=false
tick(55)

-- Verify:
-- 1. Now that NPC is free, the delivery job is cleanly claimed and queued!
check(assigned~=nil,'job was successfully claimed once NPC exited leisure')
check(assigned.npcId==npcId and assigned.jobId=='job-uuid-1','correct NPC and job assigned')
check(assigned.offer and assigned.offer.jobId=='job-uuid-1','directory offer atomically claimed by the worker')

-- TEST STEP 3: With no more work, NPC cleanly enters idle leisure
inLeisure=false
assigned=nil
testProvider.discover=function() end -- no more work
tick() tick()
check(idleLeisureCount>0,'idle leisure offered when truly no work exists')

-- TEST STEP 4: TaskDirectory withdrawal rejects claims
local dir2=Directory.new()
dir2:upsert('craft:order-x',1,'crafting','settlement-1')
dir2:claim('craft:order-x',1,'npc-x','job-x')
dir2:withdraw('craft:order-x')
check(dir2:isWithdrawn('craft:order-x')==true,'withdrawn offer is reported as withdrawn')
local ok,why=dir2:claim('craft:order-x',1,'npc-x','job-x')
check(ok==false and why=='OFFER_WITHDRAWN','withdrawn offer rejects claim with OFFER_WITHDRAWN')

-- TEST STEP 5: CraftingProvider rejects CANCELLED or PAUSED orders
package.loaded['EmberRoutesProbe/Cooking/CookingOrders']={parentAllows=function() return true end}
local CraftingProvider=require 'EmberRoutesProbe/Crafting/CraftingProvider'
local craftResult=CraftingProvider.claim({order={state='CANCELLED'}},'npc-1','job-1',{})
check(craftResult=='TASK_CHANGED','CraftingProvider rejects cancelled orders')
local craftResult2=CraftingProvider.claim({order={state='PAUSED'}},'npc-1','job-1',{})
check(craftResult2=='TASK_CHANGED','CraftingProvider rejects paused orders')

-- TEST STEP 6: Manual cancel reservation via Probe.cancelReservation
inLeisure=true
assigned=nil
testProvider.discover=function(env)
    local o=env.upsertOffer('delivery:order-2',1,'hauling',env.entry.id)
    if o and not o.jobId then
        env.candidates[#env.candidates+1]={
            key='delivery:order-2',revision=1,category='hauling',allowed=true,score=1,delivery=true
        }
    end
end
tick()
check(Public.hasReservation(npcId)==true,'reservation active for delivery:order-2')
package.loaded['EmberRoutesProbe/Kernel/Boot'].cancelReservation(npcId,'USER')
check(Public.hasReservation(npcId)==false,'Probe.cancelReservation immediately clears reservation')

print('PASS '..checks..' leisure-to-work transition & zero-lock invariant checks')
