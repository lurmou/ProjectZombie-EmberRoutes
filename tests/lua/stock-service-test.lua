-- Integration test for StockService: scheduling, non-preemption, early settle, and overlap checks.
local checks=0
local function check(cond,msg)
    checks=checks+1
    assert(cond,msg or ("Assertion failed at check #"..checks))
end

-- Mock Events before loading any modules
_G.Events=_G.Events or {}
local events={}
for _,name in ipairs({'OnContainerUpdate','OnTick','OnTickEvenPaused','OnGameStart','OnPreMapLoad','OnSave','OnServerStarted'}) do
    events[name]={}
    _G.Events[name]={Add=function(fn) events[name][#events[name]+1]=fn end}
end

_G.DebugLog={log=function() end}
_G.ISInventoryTransferAction={new=function(_,b,v,f,t) return {character=b,item=v,from=f,to=t} end}
_G.ISEatFoodAction={new=function() return {} end}
_G.ISDrinkFluidAction={new=function() return {} end}
_G.ISHandcraftAction={new=function() return {} end}
_G.ISTimedActionQueue={hasAction=function() return false end,clear=function() end,add=function() end}

for _,name in ipairs({"ISTimedActionQueue","ISEatFoodAction","ISDrinkFluidAction","ISInventoryTransferAction"}) do
    package.loaded["TimedActions/"..name]=true
end
package.loaded["Entity/TimedActions/ISHandcraftAction"]=true

-- Mock environment
local mockModData={maintainStock={format=1,revision=0,rules={}},craftProbes={format=1,byNpc={}},craftSurfaces={},entries={}}
local mockSettlement1={format=1,id="s1",factionId="f1",name="Camp1",revision=1,areas={}}
local mockSettlement2={format=1,id="s2",factionId="f1",name="Camp2",revision=1,areas={}}

local mockActor={
    isDead=function() return false end,
    getIndex=function() return 0 end,
    getUsername=function() return "Player1" end,
    getX=function() return 10 end,
    getY=function() return 10 end,
    getZ=function() return 0 end,
    Say=function() end
}

local mockNpc={
    isDead=function() return false end,
    getBodyDamage=function()
        return {getOverallBodyHealth=function() return 100 end}
    end,
    getCharacterActions=function()
        return {isEmpty=function() return true end}
    end,
    getFullName=function() return "Bob" end,
    getX=function() return 10 end,
    getY=function() return 10 end,
    getZ=function() return 0 end
}

_G.getSpecificPlayer=function() return mockActor end
_G.isClient=function() return false end
_G.isServer=function() return false end
_G.getRandomUUID=function() checks=checks+1 return "uuid_"..checks end
_G.getTimestampMs=function() return 1000 end
_G.getTextOrNull=function(k) return nil end
_G.getText=function(k) return k end

local Registry=require "EmberRoutesProbe/ContainerRegistry"
Registry.data=function() return mockModData end

local Ledger=require "EmberRoutesProbe/SettlementLedger"
Ledger.data=function()
    return {format=1,factionId="f1",entries={s1=mockSettlement1,s2=mockSettlement2}}
end
Ledger.authorized=function() return true end
Ledger.view=function(actor,id)
    return id=="s1" and mockSettlement1 or id=="s2" and mockSettlement2 or nil
end

local Index=require "EmberRoutesProbe/WarehouseIndex"
local mockIndexResults={}
Index.candidates=function(actor,settlementId,req)
    local r=mockIndexResults[settlementId..":"..req.fullType]
    if r then return r end
    return {state="READY",complete=true,knownCount=0,revision=1,settlementRevision=1}
end
Index.watch=function(settlementId,callback)
    return function() end
end
Index.refresh=function(settlementId) end

local Driver=require "EmberRoutesProbe/Driver"
Driver.bindId=function(actor,id)
    return {handle=mockNpc}
end

local Work=require "EmberRoutesProbe/Work"
Work.busy=function(id) return false end

local StockStore=require "EmberRoutesProbe/StockStore"
local StockService=require "EmberRoutesProbe/StockService"
local Production=require "EmberRoutesProbe/Production"

-- 1. checkEarlySettle
-- Fake in-flight production order context
local fakeContext={
    actor=mockActor,
    record={
        product="Base.Plank",
        settlementId="s1",
        origin={kind="MAINTAIN_STOCK",ruleId="rule_es_1",cycleSequence=1}
    }
}

-- Create rule with minimum = 50
local ruleId=StockStore.command(mockActor,"s1","create",{
    fullType="Base.Plank",
    recipeId="MakePlanks",
    recipeSignature="sig_plank",
    npcId="worker_1",
    minimum=50,
    enabled=true
})
fakeContext.record.origin.ruleId=ruleId

-- Test 1a: inventory has 40 < 50 -> returns false
mockIndexResults["s1:Base.Plank"]={state="READY",complete=true,knownCount=40}
check(StockService.checkEarlySettle(fakeContext)==false,"P=40 < M=50 does not early settle")

-- Test 1b: inventory has 50 >= 50 -> returns true!
mockIndexResults["s1:Base.Plank"]={state="READY",complete=true,knownCount=50}
check(StockService.checkEarlySettle(fakeContext)==true,"P=50 >= M=50 triggers early settle")

-- Test 1c: rule disabled -> returns true (immediate settle)
StockStore.command(mockActor,"s1","disable",{ruleId=ruleId})
check(StockService.checkEarlySettle(fakeContext)==true,"disabled rule triggers early settle")

-- Reset rule
StockStore.command(mockActor,"s1","enable",{ruleId=ruleId})

-- 2. Mock Production.execute to verify nonPreemptive options
local lastExecOptions=nil
local origExec=Production.execute
Production.execute=function(actor,cmd,obj,id,options)
    lastExecOptions=options
    return "STARTED"
end

-- Set inventory count to 20, minimum is 50 -> deficit 30
mockIndexResults["s1:Base.Plank"]={state="READY",complete=true,knownCount=20}
StockService.markDirty(ruleId)
StockService.tick()

check(lastExecOptions~=nil,"Production.execute was dispatched")
check(lastExecOptions.nonPreemptive==true,"dispatched with nonPreemptive=true")
check(lastExecOptions.origin~=nil and lastExecOptions.origin.kind=="MAINTAIN_STOCK","dispatched with origin")
check(lastExecOptions.quantity==30,"dispatched with requested deficit quantity")

-- Verify cycle attached
local r=StockStore.get(ruleId)
check(r.activeCycle~=nil and r.activeCycle.phase=="ATTACHED","rule cycle attached")

-- Clean up
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local currentRuntime=Runtime.current
local receipt={state='PENDING'}
local cancelled=0
Runtime.current=function() return {
    inspect=function(_,h) assert(h==receipt) return {state=receipt.state} end,
    stopJob=function() cancelled=cancelled+1 return true end,
} end
StockStore.settleCycle(ruleId,r.activeCycle.taskId,'DONE')
Production.execute=function() return 'QUEUED',receipt end
StockService.markDirty(ruleId) StockService.tick()
r=StockStore.get(ruleId)
check(r.activeCycle and r.activeCycle.phase=='PREPARED','queued cycle stays prepared until real production starts')
StockService.markDirty(ruleId) StockService.tick()
r=StockStore.get(ruleId) check(r.activeCycle and r.activeCycle.phase=='PREPARED','live admission is not treated as orphaned cycle')
receipt.state='REJECTED'
StockService.markDirty(ruleId) StockService.tick()
r=StockStore.get(ruleId) check(not r.activeCycle,'rejected admission clears only the unstarted prepared cycle')
receipt.state='PENDING'
StockService.markDirty(ruleId) StockService.tick()
StockStore.command(mockActor,'s1','disable',{ruleId=ruleId})
StockService.markDirty(ruleId) StockService.tick()
r=StockStore.get(ruleId) check(cancelled==1 and not r.activeCycle,'disabling rule cancels its queued request')
StockStore.command(mockActor,'s1','enable',{ruleId=ruleId})
StockService.markDirty(ruleId) StockService.tick()
r=StockStore.get(ruleId)
package.loaded['EmberRoutesProbe/BusinessJobs']={crafts=function() return {[r.npcId]={id=r.activeCycle.taskId,released=false}} end}
mockModData.craftProbes.byNpc.worker_1={id=r.activeCycle.taskId,released=false}
StockService.markDirty(ruleId) StockService.tick()
r=StockStore.get(ruleId) check(r.activeCycle.phase=='ATTACHED','matching real production record attaches prepared cycle')
Runtime.current=currentRuntime
Production.execute=origExec
print("PASS stock-service-test.lua: all "..checks.." assertions succeeded.")
return true
