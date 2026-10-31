_G.Events=_G.Events or {}
for _,name in ipairs({'ISTimedActionQueue','ISEatFoodAction','ISDrinkFluidAction','ISInventoryTransferAction','ISBaseTimedAction'}) do
    package.loaded['TimedActions/'..name]=true
end
local MockAction={} function MockAction:derive() return setmetatable({},{__index=self}) end
package.loaded['Entity/TimedActions/ISHandcraftAction']=MockAction
package.loaded['TimedActions/ISInventoryTransferAction']=MockAction

local count=0
local function check(v,s) count=count+1 assert(v,s) end

-- 1. Test ProductionChainPlan preference routing
local Plan=require 'EmberRoutesProbe/ProductionChainPlan'
local dummyProducers={
    ['Base.Plank']={
        {
            id='Base.SawBigBranch',product='Base.Plank',name='Saw Big Branch',yield=1,
            outputs={['Base.Plank']=1},
            inputs={{slot=0,count=1,types={['Base.BigBranch']=true},choices={'Base.BigBranch'},keep=false}}
        },
        {
            id='Base.SawLogs',product='Base.Plank',name='Saw Logs',yield=3,
            outputs={['Base.Plank']=3},
            inputs={{slot=0,count=1,types={['Base.Log']=true},choices={'Base.Log'},keep=false}}
        }
    }
}

local tableRecipe={
    id='Base.MakeTable',product='Base.Table',name='Make Table',yield=1,
    outputs={['Base.Table']=1},
    inputs={{slot=0,count=2,types={['Base.Plank']=true},choices={'Base.Plank'},keep=false}}
}

-- Stock has both BigBranch and Log available for crafting planks
local stock={
    {id=101,fullType='Base.BigBranch'},
    {id=102,fullType='Base.BigBranch'},
    {id=103,fullType='Base.Log'}
}

local function runPlan(pref)
    local chain=Plan.new(tableRecipe,1,stock,dummyProducers,nil,pref)
    local result,reason
    while not chain.done do
        result,reason=chain:step(64)
    end
    return result,reason
end

-- Without preferences, first producer (SawBigBranch) is chosen
local planDefault,reasonDefault=runPlan(nil)
check(planDefault~=nil,'default plan succeeds: '..tostring(reasonDefault))
check(#planDefault.nodes==2,'chain plan has 2 nodes')
check(planDefault.nodes[1].recipeId=='Base.SawBigBranch','default chooses first producer (SawBigBranch)')

-- With preference for Base.SawLogs, SawLogs is chosen!
local planPref,reasonPref=runPlan({['Base.Plank']='Base.SawLogs'})
check(planPref~=nil,'pref plan succeeds: '..tostring(reasonPref))
check(#planPref.nodes==2,'chain plan with preferences has 2 nodes')
check(planPref.nodes[1].recipeId=='Base.SawLogs','chain plan respects preferences for SawLogs')

-- 2. Test PublicPreview passing preferences & CHECKING handling
local passedPref=nil
package.loaded['EmberRoutesProbe/CraftingService']={
    status=function() return {workers={{id='w1'}}} end,
    preview=function(actor,scope,workerId,recipeId,qty,surfaceId,callback,pref)
        passedPref=pref
        -- Simulate first frame returning CHECKING (previously caused a bug if cancelled early)
        callback({state='CHECKING'})
        -- Simulate subsequent frame returning resolved chain
        callback({
            state='READY',
            counts={},
            chain={
                nodes={
                    {recipeId=pref and pref['Base.Plank'] or 'Base.SawBigBranch',product='Base.Plank',recipeName='Sawing',requested=3},
                    {recipeId='Base.MakeTable',product='Base.Table',recipeName='Make Table',requested=1}
                }
            }
        })
        return function() end
    end
}

local PublicPreview=require 'EmberRoutesProbe/PublicPreview'
local finalResult=nil
PublicPreview.watch({},'s1','Base.MakeTable',1,nil,function(res)
    finalResult=res
end,{['Base.Plank']='Base.SawLogs'})

check(passedPref and passedPref['Base.Plank']=='Base.SawLogs','PublicPreview passed preferences to CraftingService')
check(finalResult and finalResult.state=='READY','CHECKING state did not cancel preview or drop result')
check(finalResult.chain.nodes[1].recipeId=='Base.SawLogs','resolved chain has preferred precursor')

-- 3. Test PublicWork.create & saveRule receiving and persisting preferences
local rootData={orders={},stockRules={},publicWork={format=1,sequence=0,orders={},priorities={},rules={}}}
package.loaded['EmberRoutesProbe/ContainerRegistry']={
    data=function() return rootData end,
    resolve=function() return nil end,
    id=function() return 'gen-id-1' end,
    listeners={},
    inventoryListeners={}
}
local Boot=require 'EmberRoutesProbe/Boot'
Boot.ready=true
Boot.runtimeReady=true
Boot.hasJava=function() return true end
function isClient() return false end
function isServer() return false end

package.loaded['EmberRoutesProbe/SettlementLedger']={
    view=function(actor,scope) return {id=scope} end, listeners={}
}
package.loaded['EmberRoutesProbe/ProductionRecipe']={
    read=function(id) return {id=id,name='Make Table',product='Base.Table',yield=1,recipe={}} end
}

local actor={
    isRecipeKnown=function() return true end,
    getUsername=function() return 'Survivor' end
}

local PublicWork=require 'EmberRoutesProbe/PublicWork'
local resOrder,orderId=PublicWork.create(actor,'entry1','Base.MakeTable',1,nil,PublicWork.requestId(),{['Base.Plank']='Base.SawLogs'})
check(resOrder=='ORDER_CREATED','PublicWork.create returns ORDER_CREATED')
local createdOrders=PublicWork.orders('entry1')
check(#createdOrders==1,'created order recorded')
check(createdOrders[1].preferences and createdOrders[1].preferences['Base.Plank']=='Base.SawLogs','PublicWork.create persisted preferences')

local resRule=PublicWork.saveRule(actor,'entry1','Base.MakeTable',5,10,nil,{['Base.Plank']='Base.SawLogs'})
check(resRule=='RULE_SAVED','PublicWork.saveRule returns RULE_SAVED')
local savedRule=PublicWork.rule('entry1','Base.Table')
check(savedRule and savedRule.preferences and savedRule.preferences['Base.Plank']=='Base.SawLogs','PublicWork.saveRule persisted preferences')

-- 4. Test BlueprintRows and Dialog blueprint item construction logic
UIFont=UIFont or {Small=1,Medium=2,Large=3}
getTextManager=function() return {
    MeasureStringX=function(self,font,s) return (s and #s or 0)*7 end,
    getFontHeight=function(self,font) return 16 end
} end

function getItemNameFromFullType(fullType)
    if fullType=='Base.Plank' then return 'Plank' end
    if fullType=='Base.Log' then return 'Log' end
    if fullType=='Base.Saw' then return 'Handsaw' end
    if fullType=='Base.GardenSaw' then return 'Garden Saw' end
    return fullType
end

-- Verify BlueprintRows style metrics calculate switch badge
local BlueprintRows=require 'EmberRoutesProbe/UI/BlueprintRows'
local dummyList={width=400}
local dummyDialog={fontHeight=20,pad=8,presentation={icon=function() return nil end}}
local style=BlueprintRows.style(dummyDialog)

-- Prepare row for chain_step with canSwitch=true
local rowStep={
    kind='chain_step',
    fullType='Base.Plank',
    title='Saw Big Branch',
    sub='Output: 3',
    stepBadge='Step 1',
    surfaceBadge='Hands',
    canSwitch=true,
    switchText='[⟳ Switch: Saw Logs]',
    isLast=false
}
local prepared=style.prepare(dummyList,rowStep)
check(prepared.switchW and prepared.switchW>0,'switchW calculated for switchable precursor step')
check(prepared.title=='Saw Big Branch','title prepared correctly')

print('PASS '..count..' recipe chain preferences and preview checks; native host mocked')
