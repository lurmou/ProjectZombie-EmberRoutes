-- Exact native parent-slot allocation. No claims, movement or physical mutation.
local Inputs={limit=64}
local function integer(n)
    return type(n)=='number' and n==n and math.abs(n)<9007199254740992 and n==math.floor(n)
end
local function finite(n) return type(n)=='number' and n==n and n>=0 and n<math.huge end
local function fluid(row,item)
    local child=row.child
    if not child then return nil end
    -- First supported shape: one kept carrier, one fixed fluid child. Never pool bottles.
    if row.count~=1 or not row.keep or row.destroy or row.variable or child.resource~='Fluid'
        or child.variable or child.onTick or child.createTo or child.consumeFrom
        or not finite(child.amount) or child.amount<=0 then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
    if not item.getFluidContainer or not child.io.isFluidMatch then return nil,'CRAFT_API_UNAVAILABLE' end
    local container=item:getFluidContainer()
    if not container or not finite(container:getAmount()) or container:getAmount()<child.amount
        or not child.io:isFluidMatch(container) then return nil,'MATERIALS_UNAVAILABLE' end
    return {unit='FLUID_VOLUME',amount=child.amount,beforeAmount=container:getAmount(),
        matchMode=child.matchMode,line=child.line}
end
function Inputs.accept(row,item,npc)
    if not row.io:canUseItem(item,npc) then return false,'INPUT_CHANGED' end
    local flow,why=fluid(row,item)
    if why then return false,why end
    return true,flow
end
-- Internal adapter for an already capability-checked profile, not an execution grant.
-- Predicates remain runtime-only. The shared planner owns detached volume accounting.
function Inputs.planning(profile,npc)
    local facts=profile.facts
    local spec={id=facts.id,name=facts.name,signature=facts.signature,outputs=profile.outputs,
        inputs={},surface=facts.surface,product=false,yield=0}
    for kind,count in pairs(profile.outputs) do
        if not spec.product or kind<spec.product then spec.product=kind spec.yield=count end
    end
    for _,row in ipairs(profile.roots) do
        local input={slot=row.slot,count=row.count,keep=row.keep,types={},choices={},any=row.any==true}
        if not input.any then
            local possible=row.io:getPossibleInputItems()
            if not possible or possible:size()>512 then return nil,'RECIPE_FACTS_LIMIT' end
            for i=0,possible:size()-1 do
                local kind=possible:get(i):getFullName()
                if not input.types[kind] then input.types[kind]=true input.choices[#input.choices+1]=kind end
            end
        end
        if row.child then input.fluid={unit='FLUID_VOLUME',amount=row.child.amount} end
        input.accept=function(item) return Inputs.accept(row,item,npc) end
        spec.inputs[#spec.inputs+1]=input
    end
    return spec
end
function Inputs.bind(facts,entries,npc)
    if not facts or type(entries)~='table' or #entries>Inputs.limit then return nil,'INPUT_BINDING_INVALID' end
    local length=0
    for key in pairs(entries) do
        if not integer(key) or key<1 or key>#entries then return nil,'INPUT_BINDING_INVALID' end
        length=length+1
    end
    if length~=#entries then return nil,'INPUT_BINDING_INVALID' end
    local slots,seen={},{}
    local bound={manual={},entries={},facts=facts,
        proof={format=1,recipeId=facts.id,signature=facts.signature,inputs={}}}
    for _,row in ipairs(facts.inputs) do
        if row.parentSlot==nil then
            if row.resource~='Item' or not integer(row.slot) or row.slot<0 or slots[row.slot]
                or not integer(row.count) or row.count<1 or row.count>32 or row.variable
                or row.createTo or row.automation or row.worn or row.onTick then
                return nil,'RECIPE_MECHANISM_UNSUPPORTED'
            end
            slots[row.slot]={row=row,count=0}
        end
    end
    for _,entry in ipairs(entries) do
        if type(entry)~='table' then return nil,'INPUT_BINDING_INVALID' end
        local slot=slots[entry.slot] local item=entry.item
        if not slot or not item or not item.getID or not integer(entry.id) or item:getID()~=entry.id
            or seen[entry.id] then return nil,'INPUT_BINDING_INVALID' end
        local row=slot.row
        if slot.count>=row.count then return nil,'INPUT_CHANGED' end
        local accepted,flow=Inputs.accept(row,item,npc)
        if not accepted then return nil,flow end
        seen[entry.id]=true slot.count=slot.count+1
        local items=bound.manual[entry.slot] or ArrayList.new()
        bound.manual[entry.slot]=items items:add(item)
        bound.entries[#bound.entries+1]={slot=entry.slot,id=entry.id,item=item,io=row.io,keep=row.keep,fluid=flow}
        bound.proof.inputs[#bound.proof.inputs+1]={slot=entry.slot,itemId=entry.id,fullType=item:getFullType(),
            keep=row.keep,destroy=row.destroy,fluid=flow}
    end
    for _,slot in pairs(slots) do
        if slot.count~=slot.row.count then return nil,slot.row.keep and not slot.row.child and 'TOOLS_UNAVAILABLE' or 'MATERIALS_UNAVAILABLE' end
    end
    return bound
end
-- Flat membership is insufficient: the same two originals could be swapped between slots.
function Inputs.applied(logic,bound)
    if not logic or not bound or not logic.getRecipeData then return false end
    local data=logic:getRecipeData()
    if not data or not data.getDataForInputScript then return false end
    local all=data:getAllInputItems()
    if not all or all:size()~=#bound.entries then return false end
    local checked={}
    for _,entry in ipairs(bound.entries) do
        if entry.item:getID()~=entry.id or not all:contains(entry.item) then return false end
        if not checked[entry.slot] then
            local native=data:getDataForInputScript(entry.io)
            if not native or not native.getAppliedItemsCount or not native.hasAppliedItem then return false end
            local expected=bound.manual[entry.slot]
            if native:getAppliedItemsCount()~=expected:size() then return false end
            for i=0,expected:size()-1 do if not native:hasAppliedItem(expected:get(i)) then return false end end
            checked[entry.slot]=true
        end
    end
    return true
end
return Inputs
