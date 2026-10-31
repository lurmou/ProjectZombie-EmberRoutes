-- Fixed recipe BT under the existing TaskRuntime. No private scheduler or recipe replay.
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Cargo=require 'EmberRoutesProbe/CookingCargo'
local Craft=require 'EmberRoutesProbe/CookingCraft'
local Actions=require 'EmberRoutesProbe/CookingActions'
local Stations=require 'EmberRoutesProbe/CraftStations'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/MembershipService'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Tree=require 'EmberRoutesProbe/BehaviorTree'
local M={}
local function crafted(job)
    if job.payload.raw then
        local raw=job.payload.raw local a=Inventory.asset(job,raw.id)
        if a and a.custody~='SOURCE' then return {outputIds={raw.id}} end
    end
    local fixed=job.payload.fixed
    local evolved=job.payload.evolved
    -- A legal existing mixture may already meet the target before any ADD.
    -- Its output is the retained original, not a fabricated native receipt.
    if evolved and evolved.completed and evolved.baseSequence==0 then return {outputIds={evolved.originId}} end
    local sequence=fixed and fixed.craftSequence or evolved and evolved.completed and evolved.baseSequence
    for _,binding in ipairs(job.payload.bindings or {}) do
        if binding.sequence==sequence and binding.kind==(fixed and 'CRAFT' or 'ADD') then return binding end
    end
end
local function partial(job)
    local e=job.payload.evolved
    if e then
        -- An immutable ADD binding survives later return-transfer receipts.
        if e.activeSequence then
            for _,binding in ipairs(job.payload.bindings or {}) do
                if binding.sequence==e.activeSequence and binding.kind=='ADD' then return binding end
            end
        end
        local sequence=e.baseSequence
        for _,binding in ipairs(job.payload.bindings or {}) do
            if binding.sequence==sequence and binding.kind=='ADD' then return binding end
        end
    end
end
function M.new(actor,binding,job,object,budgets,safe,options)
    if not Record.valid(job) or not (job.payload.fixed or job.payload.evolved or job.payload.raw)
        or job.payload.fixed and job.payload.source~='REQUEST'
        or job.effects~='KNOWN' or type(budgets)~='function' or type(safe)~='function'
        or not binding or binding.id~=job.npcId then return nil,'COOKING_AGENT_SPEC_INVALID' end
    if job.payload.duty and (not job.payload.heat or not job.payload.duty.position)
        or (job.state~='PREPARING' and job.state~='SUSPENDED' and job.state~='SETTLING') then
        return nil,'COOKING_JOB_RETAINED'
    end
    local world=Registry.data()
    local c={actor=actor,npc=binding.handle,job=job,items={},sources={},effects=job.effects,
        cancelled=options and options.settleOnly==true or false}
    local function current()
        if Registry.data()~=world then return false end
        local saved=Jobs.current():peek(c.job.id)
        return saved and saved.revision==c.job.revision and saved.npcId==job.npcId or false
    end
    local function eligible()
        if not current() or c.npc:isDead() or actor:isDead() or not safe() then return false end
        local entry=Membership.entry(job.npcId,job.scopeId) if not entry then return false end
        c.entry=entry
        local recovery=c.cancelled or crafted(c.job)~=nil
        local fact=Membership.check(job.npcId,recovery and 'RECOVERY' or 'WORK',
            {x=c.npc:getX(),y=c.npc:getY(),z=c.npc:getZ(),scopeId=job.scopeId})
        return recovery and fact.sharedResources==true or not recovery and fact.allowed==true
    end
    c.valid=eligible
    local function phase(value)
        return {kind='Action',run=function()
            if c.job.payload.phase==value then return 'Success' end
            local j=Record.copy(c.job) j.payload.phase=value
            return Context.publish(c,j) and 'Success' or 'Failure'
        end}
    end
    local function preparation()
        local tree
        return {kind='Action',run=function()
            if c.cancelled or crafted(c.job) then return 'Success' end
            if not tree then
                if c.job.payload.raw then
                    local item=c.items[c.job.payload.raw.id]
                    if not item then c.reason='COOKING_INPUT_UNAVAILABLE' return 'Failure' end
                    tree=assert(Tree.new({kind='Sequence',children={Cargo.coldGate(c,item:getUnequippedWeight()),phase('FETCHING'),Cargo.fetch(c)}}))
                    return Tree.tick(tree,c,c.budget)
                end
                if c.job.payload.evolved then
                    local Evolved=require 'EmberRoutesProbe/CookingEvolved'
                    local recipe=options and options.evolvedRecipe
                    local why
                    if not recipe then recipe,why=Evolved.recipe(c.job.payload.evolved.recipeId) end
                    if not recipe then c.reason=why return 'Failure' end
                    local sig=Evolved.signature(recipe)
                    if sig~=c.job.payload.evolved.signature then
                        require('EmberRoutesProbe/Log').write('COOKING','EVOLVED_PROFILE_CHANGED: id='..tostring(c.job.payload.evolved.recipeId)..' expected='..tostring(c.job.payload.evolved.signature)..' actual='..tostring(sig))
                        c.reason='EVOLVED_PROFILE_CHANGED' return 'Failure'
                    end
                    local added,weight=0,0
                    for _,input in ipairs(Cargo.inputs(c.job)) do
                        local asset=Inventory.asset(c.job,input.id) local item=c.items[input.id]
                        if asset.custody=='HELD' or asset.custody=='SOURCE' then
                            if not item then c.reason='COOKING_INPUT_UNAVAILABLE' return 'Failure' end
                            weight=weight+item:getUnequippedWeight()
                            if item:getContainer()~=c.npc:getInventory() then added=added+item:getUnequippedWeight() end
                        end
                    end
                    if not require('EmberRoutesProbe/ProductionCarry').fits(c.npc,added) then
                        c.reason='CAPACITY_UNAVAILABLE' return 'Failure'
                    end
                    local mixture
                    local manager=getScriptManager and getScriptManager()
                    local output=manager and manager.getItem and manager:getItem(recipe:getFullResultItem())
                    if not output or not output.getActualWeight or output:getActualWeight()<=0 then
                        c.reason='COOKING_OUTPUT_WEIGHT_UNKNOWN' return 'Failure'
                    end
                    weight=output:getActualWeight()
                    tree=assert(Tree.new({kind='Sequence',children={Cargo.coldGate(c,weight),phase('FETCHING'),Cargo.fetch(c),
                        require('EmberRoutesProbe/CookingKitchen').leaf(c),
                        {kind='Action',run=function()
                            if not mixture then
                                local why
                                mixture,why=Evolved.new(c,recipe)
                                if not mixture then c.reason=why return 'Failure' end
                            end
                            return mixture.run()
                        end}}}))
                    return Tree.tick(tree,c,c.budget)
                end
                local profile,why=Craft.profile(c.job.payload.fixed.recipeId)
                if not profile or profile.facts.signature~=c.job.payload.fixed.signature then
                    c.reason=why or 'COOKING_PROFILE_CHANGED' return 'Failure'
                end
                if not Craft.known(c.npc,profile.facts.recipe) then c.reason='NPC_RECIPE_UNKNOWN' return 'Failure' end
                local added=0
                for _,input in ipairs(c.job.payload.fixed.inputs) do
                    local item=c.items[input.id]
                    if not item then c.reason='COOKING_INPUT_UNAVAILABLE' return 'Failure' end
                    if item:getContainer()~=c.npc:getInventory() then added=added+item:getUnequippedWeight() end
                end
                if not require('EmberRoutesProbe/ProductionCarry').fits(c.npc,added,0,profile.weight) then
                    c.reason='CAPACITY_UNAVAILABLE' return 'Failure'
                end
                tree=assert(Tree.new({kind='Sequence',children={Cargo.coldGate(c,profile.weight),
                    {kind='Action',run=function()
                        if not profile.facts.workstation and not profile.facts.surface then return 'Success' end
                        local site,why=Stations.reserve(c,object,profile.facts)
                        if not site then c.reason=why return 'Failure' end return 'Success'
                    end},phase('FETCHING'),Cargo.fetch(c),require('EmberRoutesProbe/CookingKitchen').leaf(c),phase('ADDING'),
                    {kind='Action',run=function()
                        if not profile.facts.workstation and not profile.facts.surface then return 'Success' end
                        c.craftMove=c.craftMove or Cargo.move(c,{object=object},function() return Stations.valid(c,object,profile.facts) end)
                        return c.craftMove.run()
                    end},
                    {kind='Action',run=function()
                        local cold=require('EmberRoutesProbe/CookingFacilities').cold(c.coldTarget,'put')
                        if not cold or not cold.cold then c.reason='COLD_STORAGE_UNAVAILABLE' return 'Failure' end
                        return 'Success'
                    end}}}))
            end
            return Tree.tick(tree,c,c.budget)
        end}
    end
    local function craft()
        local leaf
        return {kind='Action',run=function()
            if c.cancelled or c.job.payload.evolved or c.job.payload.raw or not leaf and crafted(c.job) then return 'Success' end
            if not leaf then
                local p=c.job.payload local a=p.attempt
                if not p.fixed.craftSequence or a and a.kind=='CRAFT' and a.state=='ABORTED' then
                    local j=Record.copy(c.job) j.payload.fixed.craftSequence=p.sequence+1
                    if not Context.publish(c,j) then return 'Failure' end
                end
                local entries={}
                for _,input in ipairs(c.job.payload.fixed.inputs) do
                    entries[#entries+1]={id=input.id,slot=input.slot,item=c.items[input.id]}
                end
                local why
                leaf,why=Actions.craft(c,c.job.payload.fixed.craftSequence,c.job.payload.fixed.recipeId,entries,object)
                if not leaf then c.reason=why return 'Failure' end
            end
            local state=leaf.run()
            if state=='Failure' then c.reason=c.reason or 'COOKING_CRAFT_STOPPED' end
            return state
        end}
    end
    local function outputs()
        return {kind='Action',run=function()
            local binding=crafted(c.job) or c.cancelled and partial(c.job)
            if not binding then return c.cancelled and 'Success' or 'Failure' end
            local snapshot,why=Inventory.snapshot(c.npc:getInventory())
            if not snapshot then c.reason=why return 'Failure' end
            for _,id in ipairs(binding.outputIds) do
                local asset=Inventory.asset(c.job,id)
                if asset.custody=='HELD' then
                    local item=snapshot[id]
                    if not item or item:getFullType()~=asset.fullType then c.reason='COOKING_OUTPUT_MISSING' return 'Failure' end
                    c.items[id]=item
                elseif asset.custody~='STATION' and asset.custody~='DELIVERED'
                    and not (asset.custody=='RETURNED' and (c.cancelled or c.job.payload.heat and c.job.payload.heat.aborted)) then
                    c.reason='COOKING_OUTPUT_RECONCILE_REQUIRED' return 'Failure'
                end
            end
            return 'Success'
        end}
    end
    local function heat()
        local leaf
        return {kind='Action',run=function()
            if not leaf then
                local binding=crafted(c.job) or c.cancelled and partial(c.job)
                if not binding and not c.job.payload.heat then return c.cancelled and 'Success' or 'Failure' end
                local why
                leaf,why=require('EmberRoutesProbe/CookingHeat').new(c,
                    c.job.payload.heat and c.job.payload.heat.itemIds or binding.outputIds,c.furnace,c.cancelled)
                if not leaf then c.reason=why return 'Failure' end
            end
            local state=leaf.run()
            if state=='Success' and c.job.payload.heat.aborted then c.cancelled=true end
            return state
        end}
    end
    local function deliver()
        local leaf
        return {kind='Action',run=function()
            if not leaf then leaf=Cargo.store(c,true,c.cancelled) end
            return leaf.run()
        end}
    end
    local spec={npcId=job.npcId,jobId=job.id,kind='COOKING',binding=binding,
        nonPreemptive=true,captureStop=true,reconcileErrors=true}
    local function progressive()
        local a=c.job.payload.attempt
        return a and a.id==c.progressive and a.state=='COMMITTING' and (a.kind=='WATER' or a.kind=='FLUID')
    end
    function spec.validate() return not c.stopping and (c.job.effects=='KNOWN' or progressive()) and eligible() end
    function spec.start(body)
        c.body=body
        local why
        c.token,why=Store.claimCooking(c.job)
        if not c.token then return false,why,'UNCHANGED' end
        if c.job.state=='SUSPENDED' then
            local j=Record.copy(c.job) j.state='PREPARING'
            if not Context.publish(c,j) then return false,c.reason,'UNCHANGED' end
        end
        if c.job.state=='PREPARING' then
            local j=Record.copy(c.job) j.state='RUNNING' j.payload.stopProof=nil
            if not Context.publish(c,j) then return false,c.reason,'UNCHANGED' end
        end
        c.tree=assert(Tree.new({kind='Sequence',children={Cargo.locate(c),preparation(),craft(),outputs(),Cargo.store(c,false),heat(),
            phase('DELIVERING'),deliver(),phase('RETURNING'),Cargo.store(c,false),
            {kind='Action',run=function()
                if not c.cancelled then
                    local heat=c.job.payload.heat local delivered=0
                    if not heat or not heat.closed or heat.aborted then c.reason='HEAT_STOPPED_BEFORE_COOKED' return 'Failure' end
                    for _,asset in ipairs(c.job.payload.assets) do
                        if asset.role=='OUTPUT' then
                            if asset.custody~='DELIVERED' then c.reason='COOKING_OUTPUT_MISSING' return 'Failure' end
                            delivered=delivered+1
                        end
                    end
                    if delivered==0 then c.reason='COOKING_OUTPUT_MISSING' return 'Failure' end
                end
                if not require('EmberRoutesProbe/CookingCapacity').release(c) then return 'Failure' end
                if #c.job.payload.claims>0 or c.job.payload.station or c.job.payload.duty then return 'Failure' end
                local j=Record.copy(c.job) j.state='SETTLING'
                if not Context.publish(c,j) then return 'Failure' end
                c.completed=true return 'Success'
            end}}}))
        return true
    end
    function spec.tick()
        if c.job.effects=='UNKNOWN' and not progressive() then c.done=true return end
        if not Context.active(c) then c.reason='COOKING_AUTHORITY_LOST' c.done=true return end
        c.budget=budgets()
        c.done=Tree.tick(c.tree,c,c.budget)~='Running' or c.job.effects=='UNKNOWN' and not progressive()
    end
    function spec.finished() return c.done==true end
    function spec.stopAdapter(controller,ticket)
        if not c.token then return nil,'NO_COOKING_CLAIM' end
        return Context.stopAdapter(c,controller,ticket)
    end
    function spec.persistFailure(fact,why)
        if c.closed then return true end
        if not current() or fact.bodyStopped~=true then return false end
        if c.token then return c.job.state=='SUSPENDED' or c.job.state=='RECONCILE_REQUIRED' end
        local j=Record.copy(c.job) j.state='SUSPENDED' j.payload.reason=string.sub(tostring(why or 'COOKING_START_REJECTED'),1,256)
        return Jobs.current():update(j.id,j.revision,{state=j.state,payload=j.payload})==true
    end
    return spec,c
end
return M
