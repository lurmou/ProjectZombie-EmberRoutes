-- Cooking demand is an existing PublicWork Order, never another Job/stock ledger.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Profiles=require 'EmberRoutesProbe/CookingProfiles'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local M={}
function M.parentAllows(o)
    if not o.parentOrderId then return true end
    local root=Registry.data() local p=root.publicWork and root.publicWork.orders[o.parentOrderId]
    return p and p.state=='WAITING' and not p.pauseRequested and not p.cancelRequested or false
end
function M.prerequisite(o)
    local root=Registry.data() local child=o.prerequisiteId and root.publicWork and root.publicWork.orders[o.prerequisiteId]
    if child and child.state~='DONE' and child.state~='CANCELLED' then return child end
end
function M.wait(o,reason)
    if o and o.state=='WAITING' and not o.jobId and reason and o.reason~=reason then
        o.reason=reason o.revision=o.revision+1 Signals.changed()
    end
end
function M.describe(id,native)
    if type(id)~='string' then return nil end
    if string.sub(id,1,8)=='evolved:' then
        local Evolved=require 'EmberRoutesProbe/CookingEvolved'
        local recipe=native or Evolved.recipe(string.sub(id,9))
        if not recipe or not Evolved.signature(recipe) or not Profiles.accept(recipe) then return nil end
        local base=recipe:getBaseItem()
        local label=getItemNameFromFullType and getItemNameFromFullType(base) or base
        return {id=id,recipeId=recipe:getOriginalname(),kind='EVOLVED',name=recipe:getName(),
            recipe=recipe,product=recipe:getFullResultItem(),yield=1,supported=true,
            category='Cooking',surface=false,inputs={{slot=0,count=1,keep=true,names={label},choices={{fullType=base,name=label}}}},
            outputs={{fullType=recipe:getFullResultItem(),count=1}},cooking=true}
    end
    -- Use an installed Food script's canonical registered ItemType. This avoids
    -- assuming the Java ItemType class itself is exposed as a Lua global.
    local manager=getScriptManager and getScriptManager()
    local reference=manager and manager.getItem and manager:getItem('Base.Carrot')
    local foodType=reference and reference.getItemType and reference:getItemType()
    if not foodType then return nil end
    local profile=require('EmberRoutesProbe/CookingCraft').profile(id,native)
    if not profile then return nil end
    local product,yield
    for _,row in ipairs(profile.facts.outputs) do
        local script=row.io:getPossibleResultItems():get(0)
        if not script.getItemType or script:getItemType()~=foodType then return nil end
        local kind=row.choices[1]
        if not product or kind<product then product=kind yield=row.count end
    end
    if not product then return nil end
    local display=require('EmberRoutesProbe/ProductionRecipe').describe({id=id,name=profile.facts.name,
        product=product,yield=yield,inputs=profile.roots,outputs=profile.outputs,surface=false})
    for i,input in ipairs(profile.roots) do
        if input.child then
            if #display.inputs[i].names==0 then display.inputs[i].names={getText('IGUI_EmberRoutesProbe_Public_COOKING_FLUID_CARRIER')} end
            display.inputs[#display.inputs+1]={slot='fluid:'..input.slot,count=input.child.amount,keep=false,
                names={getText('IGUI_EmberRoutesProbe_Public_COOKING_FLUID_REQUIREMENT')},choices={}}
        end
    end
    return {id=id,recipeId=id,kind='CRAFT',name=profile.facts.name,recipe=profile.facts.recipe,
        product=product,yield=yield,supported=true,category='Cooking',surface=false,
        inputs=display.inputs,outputs=display.outputs,cooking=true,profile=profile}
end
function M.first(scope)
    local best
    for _,o in pairs(Registry.data().publicWork and Registry.data().publicWork.orders or {}) do
        if o.category=='cooking' and o.settlementId==scope and o.state=='WAITING' and not o.jobId
            and M.parentAllows(o) and not M.prerequisite(o)
            and (not best or o.sequence<best.sequence) then best=o end
    end
    return best
end
function M.get(id)
    local root=Registry.data() local o=root.publicWork and root.publicWork.orders[id]
    return o and o.category=='cooking' and o or nil
end
function M.command(o,action)
    if o.state=='DONE' or o.state=='CANCELLED' then return 'TASK_CHANGED' end
    if action=='resume' then
        if not o.pauseRequested and o.state~='PAUSED' then return 'INVALID_COMMAND' end
        o.pauseRequested=nil if not o.jobId then o.state='WAITING' end
    elseif action=='stop' or action=='return' then
        o.pauseRequested=action=='stop' or nil o.cancelRequested=action=='return' or nil
        if o.jobId then
            o.stopBatchRequested=true
            o.state='STOPPING'
            local j=Jobs.current():peek(o.jobId) local r=require('EmberRoutesProbe/TaskRuntime').current()
            if j and r then r:stopJob(j.npcId,j.id,'COOKING_ORDER_CANCEL') end
        else o.state=action=='stop' and 'PAUSED' or 'CANCELLED' end
    else return 'INVALID_COMMAND' end
    o.revision=o.revision+1 Signals.changed(o.npcId)
    local Probe=require 'EmberRoutesProbe/Boot'
    if Probe.invalidateStudy then Probe.invalidateStudy(o.settlementId) end
    return 'ORDER_UPDATED'
end
function M.settle(job)
    if job.payload.source~='REQUEST' then return end
    local o=M.get(job.payload.sourceId)
    if not o or o.jobId~=job.id then return end
    o.npcId=job.npcId
    if job.state~='DONE' and job.state~='CANCELLED' then
        local a=job.payload.attempt
        local runtime=require('EmberRoutesProbe/TaskRuntime').current()
        local live=runtime and runtime:status(job.npcId,job.id)
        local pouring=live and live.state=='ACTIVE' and a and a.state=='COMMITTING' and (a.kind=='WATER' or a.kind=='FLUID')
        o.state=job.effects~='KNOWN' and not pouring and 'RECONCILE_REQUIRED' or job.state=='RUNNING' and 'RUNNING' or 'WAITING'
        o.reason=job.payload.reason or 'WAITING_CLAIM' return
    end
    if job.effects~='KNOWN' or #job.payload.claims>0 then return end
    for _ in pairs(job.obligations) do return end
    local delivered=0
    for _,a in ipairs(job.payload.assets) do
        if a.role=='OUTPUT' and a.fullType==o.product and a.custody=='DELIVERED' then delivered=delivered+1 end
    end
    o.delivered=(o.delivered or 0)+delivered o.lastJobId=job.id o.jobId=nil o.npcId=nil
    o.stopBatchRequested=nil
    o.state=o.cancelRequested and 'CANCELLED' or o.pauseRequested and 'PAUSED'
        or o.delivered>=o.target and 'DONE' or 'WAITING'
    o.reason=o.state=='WAITING' and 'WAITING_CLAIM' or o.state
    o.revision=o.revision+1 Signals.changed()
end
function M.study(o,descriptor)
    if not o or not descriptor or descriptor.kind~='CRAFT' then return nil end
    local recipe=descriptor.recipe
    local keys={recipe:getName()}
    local meta=recipe.getMetaRecipe and recipe:getMetaRecipe()
    if meta and meta~='' then keys[#keys+1]=meta end
    if recipe.getTranslationName then keys[#keys+1]=recipe:getTranslationName() end
    return {orderId=o.id,recipeId=o.recipeId,knowledge=keys}
end
return M
