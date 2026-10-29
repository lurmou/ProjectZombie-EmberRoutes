-- Metadata/slot contracts in installed Kahlua; native objects are deliberately mocked.
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
local function list(values)
    local value=values or {}
    function value:size() return #self end
    function value:get(index) return self[index+1] end
    function value:add(item) self[#self+1]=item end
    function value:contains(item) for _,entry in ipairs(self) do if entry==item then return true end end return false end
    return value
end
ArrayList={new=function() return list() end}
ResourceType={Item='Item',Fluid='Fluid',Energy='Energy'}
package.loaded['EmberRoutesProbe/CraftRecipeAdapter']={}
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
function getTextOrNull() end
local function input(slot,kind,quantity)
    local io={slot=slot,kind=kind,quantity=quantity,keep=false}
    function io:getResourceType() return self.kind end
    function io:getIntAmount() return math.floor(self.quantity) end
    function io:getAmount() return self.quantity end
    function io:getOriginalLine() return self.line or self.kind..':'..self.quantity end
    function io:isVariableAmount() return false end
    function io:isKeep() return self.keep end function io:isDestroy() return self.destroy==true end
    function io:hasCreateToItem() return false end function io:hasConsumeFromItem() return self.child~=nil end
    function io:getConsumeFromItemScript() return self.child end
    function io:hasParentScript() return self.parent~=nil end function io:getParentScript() return self.parent end
    function io:isAutomationOnly() return false end function io:isWorn() return false end function io:isApplyOnTick() return false end
    function io:isAcceptsAnyItem() return self.child~=nil end
    function io:getPossibleInputItems() return list({{getFullName=function() return 'Base.Log' end}}) end
    function io:isUsesPartialItem() return self.partial==true end
    function io:canUseItem(item) return item.allowed~=false end
    function io:getFluidMatchMode() return 'mixture' end
    function io:isFluidMatch(container) return container.kind=='CowMilk' or container.kind=='SheepMilk' end
    return io
end
local function recipe(id,inputs,kind)
    local product={getFullName=function() return kind end,getActualWeight=function() return 1 end,
        getDisplayName=function() return kind end}
    local output=input(20,'Item',1)
    function output:getPossibleResultItems() return list({product}) end
    function output:getChance() return 1 end
    local r={id=id,inputs=list(inputs),outputs=list({output})}
    function r:getInputs() return self.inputs end function r:getOutputs() return self.outputs end
    function r:getIndexForIO(io) return io.slot end
    function r:getTranslationName() return self.id end function r:getTime() return 500 end
    function r:isAnySurfaceCraft() return not self.station end function r:isInHandCraftCraft() return false end
    function r:requiresSpecificWorkstation() return self.station==true end function r:isBuildableRecipe() return false end
    function r:hasOnTickInputs() return false end function r:hasOnTickOutputs() return false end
    function r:getRequiredSkills() return list() end function r:getCategory() return 'Farming' end
    return r
end
local milk=input(1,'Fluid',5) local carrier=input(0,'Item',1)
carrier.child=milk carrier.keep=true milk.parent=carrier
local butter=recipe('Base.churn_butter',{carrier,milk},'Base.Butter') butter.station=true
local ordinary=recipe('Base.SawLogs',{input(0,'Item',1)},'Base.Plank')
local scripts={['Base.churn_butter']=butter,['Base.SawLogs']=ordinary}
function getScriptManager() return {getCraftRecipe=function(_,id) return scripts[id] end,
    getAllCraftRecipes=function() return list({butter,ordinary}) end} end
EmberRoutesProbeJava={recipeHasCallbacks=function(r) return r.callbacks==true end,
    recipeHasSpecialOutputs=function() return false end,recipeKey=function(r) return r.id end}
local Facts=require 'EmberRoutesProbe/CraftRecipeFacts'
local Production=require 'EmberRoutesProbe/ProductionRecipe'
local Inputs=require 'EmberRoutesProbe/CraftRecipeInputs'
local facts=Facts.read(butter.id)
check(facts and facts.workstation and facts.inputs[1].child==facts.inputs[2],'read keeps the native fluid parent/child relationship')
check(facts.inputs[2].amount==5 and facts.inputs[2].parentSlot==0,'fluid volume is attached to the original parent IO')
local spec,why=Production.fromFacts(facts)
check(not spec and why=='RECIPE_MECHANISM_UNSUPPORTED','metadata discovery does not enable the legacy workstation executor')
check(Production.read(ordinary.id)~=nil,'ordinary item recipes retain legacy capability')
ordinary.callbacks=true
check(not Production.read(ordinary.id) and Facts.read(ordinary.id).callbacks,'callbacks remain discoverable and execution-blocked')
ordinary.callbacks=false
local original=facts.signature milk.quantity=6
check(Facts.read(butter.id).signature~=original,'changed embedded fluid requirement changes definition signature')
milk.quantity=5
milk.line='-fluid scripted milk amount'
local parsedStamp=Facts.read(butter.id).signature
milk.quantity=6
check(Facts.read(butter.id).signature~=parsedStamp,'resolved fluid amount changes signature even when original source text is unchanged')
milk.quantity=5 milk.line=nil
local function item(id,amount,kind)
    local value={id=id,fluid={amount=amount,kind=kind or 'CowMilk'}}
    function value:getID() return self.id end function value:getFullType() return 'Mod.MilkCarrier' end
    function value:getFluidContainer() return self.fluid end
    function value.fluid:getAmount() return self.amount end
    return value
end
local bucket=item(101,5) local smallA,smallB=item(102,2.5),item(103,2.5)
local bound=Inputs.bind(facts,{{slot=0,item=bucket,id=101}},{})
check(bound and bound.manual[0]:get(0)==bucket and bound.manual[1]==nil,'manual inputs bind the physical parent, not the child fluid slot')
check(bound.proof.inputs[1].fluid.unit=='FLUID_VOLUME' and bound.proof.inputs[1].fluid.beforeAmount==5,'binding retains typed initial volume and actual original ID')
check(not Inputs.bind(facts,{{slot=0,item=smallA,id=102},{slot=0,item=smallB,id=103}},{}),'two small bottles never pool into one carrier slot')
check(not Inputs.bind(facts,{{slot=0,item=item(104,0),id=104}},{}),'an empty wildcard container is not a milk input')
check(not Inputs.bind(facts,{{slot=0,item=item(105,5,'Water'),id=105}},{}),'matching total volume cannot substitute water for milk')
check(not Inputs.bind(facts,{{slot=0,item=bucket,id=999}},{}),'a stale item ID cannot bind a different original')
check(not Inputs.bind(facts,{[1]={slot=0,item=bucket,id=101},[3]={slot=0,item=bucket,id=101}},{}),'sparse allocations are rejected')
carrier.destroy=true
check(not Inputs.bind(Facts.read(butter.id),{{slot=0,item=bucket,id=101}},{}),'destroyed-carrier shapes are not silently treated as kept tools')
carrier.destroy=false
local other=item(106,5)
local second=input(2,'Item',1)
local two=recipe('Mod.TwoSlots',{carrier,second},'Base.Butter')
local twoFacts=Facts.read(two.id,two)
local twoBound=Inputs.bind(twoFacts,{{slot=0,item=bucket,id=101},{slot=2,item=other,id=106}},{})
local actual={[carrier]=list({bucket}),[second]=list({other})}
local data={getAllInputItems=function() return list({bucket,other}) end,
    getDataForInputScript=function(_,io) return {
        getAppliedItemsCount=function() return actual[io]:size() end,
        hasAppliedItem=function(_,value) return actual[io]:contains(value) end}
    end}
local logic={getRecipeData=function() return data end}
check(Inputs.applied(logic,twoBound),'native per-slot manual assignment is checked')
actual[carrier],actual[second]=actual[second],actual[carrier]
check(not Inputs.applied(logic,twoBound),'same flat item set swapped across slots is rejected')
local Catalog=require 'EmberRoutesProbe/CraftingCatalog'
Catalog.step()
local byId,byType=Catalog.recipeIndex()
local executable=Catalog.productionIndex()
check(byId[butter.id] and byType['Base.Butter'][1].id==butter.id and not executable[butter.id],
    'unsupported producer remains in the shared facts index but outside legacy execution')
check(executable[ordinary.id]~=nil,'shared discovery retains supported legacy producers')
local planning=assert(Inputs.planning({facts=facts,roots={facts.inputs[1]},outputs={['Base.Butter']=1}},{}))
check(planning.inputs[1].any and planning.inputs[1].fluid.amount==5
    and planning.inputs[1].accept(bucket) and not planning.inputs[1].accept(smallA),
    'shared metadata becomes a typed wildcard BOM without treating small carriers as reusable tools')
local planner=require('EmberRoutesProbe/ProductionChainPlan').new(planning,1,
    {{id=101,fullType=bucket:getFullType(),item=bucket,fluidAmount=5}},{})
for _=1,100 do planner:step(1) if planner.done then break end end
check(planner.result and planner.result.nodes[1].fluidInputs[1].itemId==101,
    'native facts, typed input adapter and existing BOM share the same physical parent identity')
root={} check(not Catalog.recipeIndex()[butter.id],'world reset drops stale metadata handles')
print('PASS '..checks..' recipe facts and exact-slot checks; native objects mocked, game NOT RUN')
