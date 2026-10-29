-- Fixed CraftRecipe adapter inside the owning Cooking Job/Session.
local Facts=require 'EmberRoutesProbe/CraftRecipeFacts'
local Inputs=require 'EmberRoutesProbe/CraftRecipeInputs'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Stations=require 'EmberRoutesProbe/CraftStations'
local Context=require 'EmberRoutesProbe/CookingContext'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Carry=require 'EmberRoutesProbe/ProductionCarry'
local Food=require 'EmberRoutesProbe/CookingFood'
local M={}
local function integer(n) return type(n)=='number' and n>=1 and n<=32 and n==math.floor(n) end
function M.profile(id,native)
    local facts,why=Facts.read(id,native) if not facts then return nil,why end
    if facts.buildable or facts.callbacks or facts.specialOutputs or facts.onTick
        or #facts.inputs==0 or #facts.inputs>16 or #facts.outputs==0 or #facts.outputs>8 then
        return nil,'RECIPE_MECHANISM_UNSUPPORTED'
    end
    if not facts.workstation then
        local ordinary,reason=require('EmberRoutesProbe/ProductionRecipe').fromFacts(facts)
        if not ordinary then return nil,reason end
    end
    local roots,total={},0
    for _,row in ipairs(facts.inputs) do if row.parentSlot==nil then
        if row.resource~='Item' or not integer(row.count) or row.variable or row.createTo
            or row.automation or row.worn or row.onTick then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
        if row.child then
            local child=row.child
            if row.count~=1 or not row.keep or row.destroy or child.resource~='Fluid' or child.variable
                or child.onTick or child.createTo or child.consumeFrom or child.amount<=0 then
                return nil,'RECIPE_MECHANISM_UNSUPPORTED'
            end
        else
            local possible=row.io:getPossibleInputItems()
            if not possible or possible:size()==0 or possible:size()>512 then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
            for i=0,possible:size()-1 do if row.io:isUsesPartialItem(possible:get(i)) then
                return nil,'RECIPE_MECHANISM_UNSUPPORTED'
            end end
        end
        roots[#roots+1]=row total=total+row.count
    end end
    if total==0 or total>16 then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
    local result={facts=facts,roots=roots,outputs={},count=0,weight=0}
    for _,row in ipairs(facts.outputs) do
        if row.resource~='Item' or not integer(row.count) or row.variable or row.onTick or row.createTo
            or row.choiceCount~=1 or row.chance~=1 then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
        local kind=row.choices[1] local item=row.io:getPossibleResultItems():get(0)
        result.outputs[kind]=(result.outputs[kind] or 0)+row.count result.count=result.count+row.count
        result.weight=result.weight+item:getActualWeight()*row.count
    end
    if result.count+total+2>Record.limit then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
    return result
end
local function knowledge(npc,recipe)
    if not npc:isRecipeKnown(recipe,true) then return false end
    for i=0,recipe:getRequiredSkillCount()-1 do
        local skill=recipe:getRequiredSkill(i)
        if npc:getPerkLevel(skill:getPerk())<skill:getLevel() then return false end
    end
    return true
end
M.known=knowledge
function M.leaf(c,sequence,recipeId,entries,object,makeLeaf)
    require 'Entity/TimedActions/ISHandcraftAction'
    local ids={}
    if type(entries)~='table' or #entries==0 or #entries>Record.limit then return nil,'INPUT_BINDING_INVALID' end
    for _,entry in ipairs(entries) do
        if type(entry)~='table' or type(entry.id)~='number' then return nil,'INPUT_BINDING_INVALID' end
        ids[#ids+1]=entry.id
    end
    local function matches(s)
        if s.recipeId~=recipeId or object and object:getModData().EmberRoutesCraftProbeBenchId~=s.siteId
            or not s.inputs or not s.inputs.inputs or #s.inputs.inputs~=#entries then return false end
        for i,entry in ipairs(entries) do
            local input=s.inputs.inputs[i]
            if input.slot~=entry.slot or input.itemId~=entry.id then return false end
        end
        return true
    end
    -- A known replay is historical observation; it needs no live milk or workstation.
    if sequence==c.job.payload.sequence then
        return makeLeaf(c,sequence,'CRAFT',ids,{matches=matches})
    end
    local profile,why=M.profile(recipeId) if not profile then return nil,why end
    local facts=profile.facts local root=c.npc:getInventory() local beforeItems
    local needsSite=facts.workstation or facts.surface
    local function owned() return not needsSite or Stations.owned(c,object) end
    local function range(action)
        if facts.workstation then return action.logic:isCharacterInRangeOfWorkbench() end
        return not needsSite or require('EmberRoutesProbe/WorkTransfer').reachable(c.npc,{object=object})
    end
    local bound,reason=Inputs.bind(facts,entries,c.npc) if not bound then return nil,reason end
    if #c.job.payload.assets+profile.count>Record.limit or #c.job.payload.claims+profile.count>Record.limit then return nil,'COOKING_ASSET_LIMIT' end
    local function live()
        if not Context.current(c) or not knowledge(c.npc,facts.recipe) then return false end
        for _,entry in ipairs(bound.entries) do
            local asset=Inventory.asset(c.job,entry.id)
            if not asset or asset.custody~='HELD' or asset.fullType~=entry.item:getFullType()
                or not Store.validCooking(c.job,c.token,'item:'..entry.id)
                or not Inventory.contains(entry.item,root,entry.id) or not entry.io:canUseItem(entry.item,c.npc) then return false end
            if instanceof(entry.item,'Food') then
                local food=Food.read(entry.item)
                if not food or not food.safe or food.frozen then return false end
            end
        end
        return true
    end
    local function unchanged(s)
        if not live() then return false end
        local current=M.profile(recipeId)
        if not current or current.facts.signature~=s.signature then return false end
        for _,flow in ipairs(s.flows) do
            local found
            for _,entry in ipairs(bound.entries) do if entry.id==flow.itemId then found=entry.item end end
            local snapshot=found and Fluids.read(found:getFluidContainer())
            if not snapshot or not Fluids.equal(snapshot,flow.snapshot) then return false end
        end
        return true
    end
    return makeLeaf(c,sequence,'CRAFT',ids,{
        matches=matches,live=live,
        capture=function()
            if not live() or not Carry.fits(c.npc,0,0,profile.weight) then return nil,'CRAFT_PRECONDITION' end
            local flows={}
            for _,entry in ipairs(bound.entries) do if entry.fluid then
                local snapshot,err=Fluids.read(entry.item:getFluidContainer()) if not snapshot then return nil,err end
                flows[#flows+1]={itemId=entry.id,amount=entry.fluid.amount,snapshot=snapshot}
            end end
            local site,err
            if needsSite then site,err=Stations.reserve(c,object,facts) if not site then return nil,err end end
            return {recipeId=recipeId,signature=facts.signature,siteId=site and site.id,
                leaseId=c.job.payload.station and c.job.payload.station.leaseId,inputs=bound.proof,flows=flows}
        end,
        valid=function(s)
            return unchanged(s) and (not needsSite or Stations.valid(c,object,facts)) and Carry.fits(c.npc,0,0,profile.weight)
        end,
        unchanged=unchanged,
        prepare=function() return not needsSite or Stations.acquire(c,object,facts) end,
        create=function()
            local containers=ArrayList.new() containers:add(root)
            local site=needsSite and Stations.read(object,facts)
            if needsSite and not site then return nil end
            return ISHandcraftAction:new(c.npc,facts.recipe,containers,object,site and site.bench,bound.manual,nil,nil,1,0)
        end,
        started=function(action)
            return action.craftStarted and action.logic and range(action)
                and Inputs.applied(action.logic,bound) and owned()
        end,
        beforeEffect=function(action)
            beforeItems=Inventory.snapshot(root)
            return beforeItems~=nil and Inputs.applied(action.logic,bound) and owned() and range(action)
        end,
        observe=function(action,s,nativeOK)
            local before=beforeItems if not before then return nil end
            local j=Inventory.retainOutputs(c.job,before,root) if not j then return nil end
            local outputs=ArrayList.new() action.logic:getCreatedOutputItems(outputs)
            local seen,counts,outputIds={}, {},{}
            local verified=nativeOK==true and outputs:size()==profile.count local flows={}
            for i=0,math.min(outputs:size(),Record.limit)-1 do
                local item=outputs:get(i) local key,kind=item:getID(),item:getFullType()
                if seen[key] or before[key] or Inventory.asset(c.job,key) then verified=false end
                seen[key]=true counts[kind]=(counts[kind] or 0)+1 outputIds[#outputIds+1]=key
                local asset=Inventory.asset(j,key)
                if not asset and not before[key] and #j.payload.assets<Record.limit then
                    asset={id=key,fullType=kind,custody='UNKNOWN',role='TOOL'}
                    j.payload.assets[#j.payload.assets+1]=asset j.payload.claims[#j.payload.claims+1]='item:'..key
                end
                if not Inventory.contains(item,root,key) then
                    verified=false
                    local world=item.getWorldItem and item:getWorldItem()
                    local square=world and world:getSquare()
                    if asset and not before[key] and square and world.getWorldObjectIndex and world:getWorldObjectIndex()>=0 then
                        asset.custody='WORLD' asset.position={x=square:getX(),y=square:getY(),z=square:getZ()}
                    end
                end
            end
            for kind,n in pairs(profile.outputs) do if counts[kind]~=n then verified=false end counts[kind]=nil end
            for _ in pairs(counts) do verified=false end
            local consumed=action.logic:getRecipeData():getAllConsumedItems()
            for _,entry in ipairs(bound.entries) do
                if entry.keep then
                    if not Inventory.contains(entry.item,root,entry.id) then verified=false end
                    if not entry.fluid and consumed:contains(entry.item) then verified=false end
                elseif not consumed:contains(entry.item) or entry.item:getContainer()~=nil
                    or root:getItems():contains(entry.item) then verified=false end
            end
            for _,flow in ipairs(s.flows) do
                local item
                for _,entry in ipairs(bound.entries) do if entry.id==flow.itemId then item=entry.item end end
                local after=item and Fluids.read(item:getFluidContainer())
                if not after or not Fluids.consumed(flow.snapshot,after,flow.amount) then verified=false end
                flows[#flows+1]={itemId=flow.itemId,amount=flow.amount,before=flow.snapshot,after=after}
            end
            -- Publish every observed new original before deciding whether the
            -- full operation can be confirmed, including native throws/drops.
            if not Context.publish(c,j) then return nil end
            if not verified then return nil end
            j=Record.copy(c.job)
            for _,entry in ipairs(bound.entries) do if not entry.keep then Inventory.release(j,entry.id,'CONSUMED') end end
            for _,key in ipairs(outputIds) do Inventory.asset(j,key).role='OUTPUT' end
            return j,{attemptId=j.payload.attempt.id,observed=true,inputsObserved=true,outputIds=outputIds,flows=flows}
        end,
        cleanup=function(stopped,s) return not needsSite or Stations.release(c,stopped,s.leaseId) end,
    })
end
return M
