-- Unit tests for StockRule and StockStore under Kahlua VM.
local StockRule=require "EmberRoutesProbe/StockRule"

local checks=0
local function check(cond,msg)
    checks=checks+1
    assert(cond,msg or ("Assertion failed at check #"..checks))
end

-- 1. uniqueKey
check(StockRule.uniqueKey("settle_1","Base.Plank")=="settle_1:Base.Plank","valid unique key")
check(StockRule.uniqueKey("","Base.Plank")==nil,"empty settlement returns nil")
check(StockRule.uniqueKey("settle_1","")==nil,"empty fullType returns nil")
check(StockRule.uniqueKey(nil,"Base.Plank")==nil,"nil settlement returns nil")

-- 2. validate
local validRule={
    id="rule_1",
    settlementId="s1",
    fullType="Base.Plank",
    recipeId="MakePlanks",
    recipeSignature="sig_plank",
    npcId="worker_1",
    surfaceId="bench_1",
    minimum=50,
    enabled=true,
    revision=1,
    nextCycle=1
}
check(StockRule.validate(validRule)==true,"valid rule passes")
check(StockRule.validate({})==false,"empty table fails")
local r2={} for k,v in pairs(validRule) do r2[k]=v end
r2.minimum=0 check(StockRule.validate(r2)==false,"zero minimum fails")
r2.minimum=10000 check(StockRule.validate(r2)==false,"10000 minimum fails")
r2.minimum=50.5 check(StockRule.validate(r2)==false,"non-integer minimum fails")
r2.minimum=50 r2.npcId="" check(StockRule.validate(r2)==false,"empty npcId fails")

-- 3. evaluate
-- Disabling & Deleting
r2.npcId="worker_1" r2.enabled=false
check(StockRule.evaluate(r2,{state="READY",complete=true,count=10}).state=="DISABLED","disabled rule reports DISABLED")
r2.enabled=true r2.deleting=true
check(StockRule.evaluate(r2,{state="READY",complete=true,count=10}).state=="DELETING","deleting rule reports DELETING")
r2.deleting=false

-- Incomplete inventory
check(StockRule.evaluate(validRule,{state="UPDATING",complete=false,count=10}).state=="WAIT_INVENTORY","UPDATING inventory waits")
check(StockRule.evaluate(validRule,{state="READY",complete=false,count=10}).state=="WAIT_INVENTORY","incomplete inventory waits")

-- Manual order collision
check(StockRule.evaluate(validRule,{state="READY",complete=true,count=10},{hasManualOrder=true}).state=="WAIT_EXISTING_ORDER","manual order collision blocks")

-- Satisfied target
local sat=StockRule.evaluate(validRule,{state="READY",complete=true,count=50},{hasManualOrder=false},1)
check(sat.state=="SATISFIED" and sat.deficit==0,"P=50, M=50 is satisfied")
local over=StockRule.evaluate(validRule,{state="READY",complete=true,count=60},{hasManualOrder=false},1)
check(over.state=="SATISFIED" and over.deficit==0,"P=60, M=50 is satisfied")

-- Deficit & batch calculations
-- P=40, M=50, yield=1 -> D=10, requested=10, target=10
local def1=StockRule.evaluate(validRule,{state="READY",complete=true,count=40},{hasManualOrder=false},1)
check(def1.state=="DEFICIT" and def1.deficit==10 and def1.requested==10 and def1.target==10,"single yield deficit")

-- P=40, M=50, yield=4 -> D=10, requested=10, target=12 (3 batches)
local def4=StockRule.evaluate(validRule,{state="READY",complete=true,count=40},{hasManualOrder=false},4)
check(def4.state=="DEFICIT" and def4.deficit==10 and def4.requested==10 and def4.target==12 and def4.batches==3,"yield=4 rounds target up")

-- 32 batches cap: yield=1, deficit=100 -> requested=32, target=32
local cap1=StockRule.evaluate(validRule,{state="READY",complete=true,count=0},{hasManualOrder=false},1)
check(cap1.state=="DEFICIT" and cap1.deficit==50 and cap1.requested==32 and cap1.target==32,"32 batches cap for yield=1")

-- 32 batches cap: yield=4, deficit=200 -> maxBatchItems=128, requested=128, target=128
local bigRule={} for k,v in pairs(validRule) do bigRule[k]=v end bigRule.minimum=300
local cap4=StockRule.evaluate(bigRule,{state="READY",complete=true,count=0},{hasManualOrder=false},4)
check(cap4.state=="DEFICIT" and cap4.deficit==300 and cap4.requested==128 and cap4.target==128,"32 batches cap for yield=4")

-- Active cycle evaluation
local activeRule={} for k,v in pairs(validRule) do activeRule[k]=v end
activeRule.activeCycle={sequence=1,taskId="task_101",ruleRevision=1,phase="ATTACHED",requested=10}
local evalActive=StockRule.evaluate(activeRule,{state="READY",complete=true,count=10},{},1)
check(evalActive.state=="RESTOCKING" and evalActive.requested==10,"active cycle reports RESTOCKING")

-- 4. StockStore operations
-- Mock Registry and Ledger environment
local mockModData={maintainStock={format=1,revision=0,rules={}},entries={}}
local mockSettlement={format=1,id="s1",factionId="f1",name="Camp",revision=1,areas={}}
local mockActor={isDead=function() return false end,getIndex=function() return 0 end}
_G.getSpecificPlayer=function() return mockActor end
_G.isClient=function() return false end
_G.isServer=function() return false end
_G.getRandomUUID=function() checks=checks+1 return "uuid_"..checks end

local Registry=require "EmberRoutesProbe/ContainerRegistry"
Registry.data=function() return mockModData end
local Ledger=require "EmberRoutesProbe/SettlementLedger"
Ledger.data=function() return {format=1,factionId="f1",entries={s1=mockSettlement}} end

local StockStore=require "EmberRoutesProbe/StockStore"

-- Create rule
local ruleId,err=StockStore.command(mockActor,"s1","create",{
    fullType="Base.WoodenStick",
    recipeId="CarveStick",
    recipeSignature="sig_stick",
    npcId="worker_1",
    minimum=20,
    enabled=true
})
check(ruleId~=nil and type(ruleId)=="string","rule created successfully")
local rule=StockStore.get(ruleId)
check(rule~=nil and rule.fullType=="Base.WoodenStick" and rule.minimum==20,"rule retrieved from store")

-- Duplicate creation rejection
local dupId,dupErr=StockStore.command(mockActor,"s1","create",{
    fullType="Base.WoodenStick",
    recipeId="CarveStick",
    recipeSignature="sig_stick",
    npcId="worker_1",
    minimum=30
})
check(dupId==nil and dupErr=="DUPLICATE_PRODUCT_RULE","duplicate fullType rule rejected")

-- Update rule
local upRes,upErr=StockStore.command(mockActor,"s1","update",{
    ruleId=ruleId,
    expectedRevision=1,
    minimum=35
})
check(upRes=="RULE_UPDATED","minimum updated")
rule=StockStore.get(ruleId)
check(rule.minimum==35 and rule.revision==2,"revision incremented on update")

-- Revision mismatch rejection
local badRev,badErr=StockStore.command(mockActor,"s1","update",{
    ruleId=ruleId,
    expectedRevision=1,
    minimum=40
})
check(badRev==nil and badErr=="REVISION_MISMATCH","revision mismatch rejected")

-- Disable / Enable
StockStore.command(mockActor,"s1","disable",{ruleId=ruleId,expectedRevision=2})
rule=StockStore.get(ruleId)
check(rule.enabled==false and rule.revision==3,"rule disabled")
StockStore.command(mockActor,"s1","enable",{ruleId=ruleId,expectedRevision=3})
rule=StockStore.get(ruleId)
check(rule.enabled==true and rule.revision==4,"rule re-enabled")

-- Cycle Lifecycle
local cycle=StockStore.prepareCycle(ruleId,"task_c1",15,10,1)
check(cycle~=nil and cycle.phase=="PREPARED" and cycle.sequence==1,"cycle prepared")
rule=StockStore.get(ruleId)
check(rule.activeCycle~=nil and rule.nextCycle==2,"nextCycle advanced")

-- Cannot prepare another cycle while active
local c2,c2Err=StockStore.prepareCycle(ruleId,"task_c2",10)
check(c2==nil and c2Err=="CANNOT_PREPARE_CYCLE","second cycle blocked while first active")

-- Attach cycle
check(StockStore.attachCycle(ruleId,"task_c1")==true,"cycle attached")
rule=StockStore.get(ruleId)
check(rule.activeCycle.phase=="ATTACHED","cycle phase is ATTACHED")

-- Settle cycle
check(StockStore.settleCycle(ruleId,"task_c1","DONE")==true,"cycle settled DONE")
rule=StockStore.get(ruleId)
check(rule.activeCycle==nil,"activeCycle cleared after settlement")

-- Delete with active cycle vs without
-- 1) Without active cycle:
local rDelId=StockStore.command(mockActor,"s1","create",{
    fullType="Base.Nails",recipeId="MakeNails",recipeSignature="sig_nails",
    npcId="worker_1",minimum=100
})
check(StockStore.command(mockActor,"s1","delete",{ruleId=rDelId,expectedRevision=1})=="RULE_DELETED","delete without active cycle removes rule directly")
check(StockStore.get(rDelId)==nil,"rule gone from store")

-- 2) With active cycle:
StockStore.prepareCycle(ruleId,"task_c2",10)
local delRes=StockStore.command(mockActor,"s1","delete",{ruleId=ruleId,expectedRevision=4})
check(delRes=="RULE_DELETING","delete with active cycle enters deleting state")
rule=StockStore.get(ruleId)
check(rule.deleting==true and rule.enabled==false,"rule marked deleting and disabled")
-- When cycle finishes:
StockStore.settleCycle(ruleId,"task_c2","DONE")
check(StockStore.get(ruleId)==nil,"rule purged once cycle concludes")

print("PASS stock-rules-test.lua: all "..checks.." assertions succeeded.")
return true
