-- Native metadata only. Reading a recipe never grants permission to execute it.
local Facts={inputLimit=64,outputLimit=32,choiceLimit=512}
local function resource(value)
    for _,name in ipairs({'Item','Fluid','Energy'}) do
        if ResourceType[name] and value==ResourceType[name] then return name end
    end
    return 'OTHER'
end
local function flag(io,name)
    return io[name] and io[name](io) or false
end
local function amount(io)
    return io.getAmount and io:getAmount() or io:getIntAmount()
end
local function input(recipe,io)
    local kind=resource(io:getResourceType())
    return {io=io,slot=recipe:getIndexForIO(io),resource=kind,amount=amount(io),count=io:getIntAmount(),
        line=io:getOriginalLine(),keep=io:isKeep(),destroy=flag(io,'isDestroy'),
        variable=io:isVariableAmount(),any=flag(io,'isAcceptsAnyItem'),
        createTo=io:hasCreateToItem(),consumeFrom=io:hasConsumeFromItem(),
        automation=io:isAutomationOnly(),worn=io:isWorn(),onTick=io:isApplyOnTick()}
end
local function inputStamp(row)
    return table.concat({row.resource,tostring(row.amount),tostring(row.count),tostring(row.keep),
        tostring(row.destroy),tostring(row.variable),tostring(row.matchMode),row.line},':')
end
function Facts.read(id,native)
    if type(id)~='string' or id=='' or #id>200 then return nil,'RECIPE_UNAVAILABLE' end
    if not ResourceType or not ResourceType.Item then return nil,'CRAFT_API_UNAVAILABLE' end
    if not native then
        local manager=getScriptManager()
        native=manager and manager:getCraftRecipe(id)
    end
    if not native then return nil,'RECIPE_UNAVAILABLE' end
    local bridge=EmberRoutesProbeJava
    if not bridge or not bridge.recipeHasCallbacks or not bridge.recipeHasSpecialOutputs then
        return nil,'CRAFT_API_UNAVAILABLE'
    end
    local inputs,outputs=native:getInputs(),native:getOutputs()
    if inputs:size()>Facts.inputLimit or outputs:size()>Facts.outputLimit then return nil,'RECIPE_FACTS_LIMIT' end
    local result={id=id,recipe=native,name=native:getTranslationName(),inputs={},outputs={},
        surface=native:isAnySurfaceCraft(),inHand=native:isInHandCraftCraft(),
        workstation=native:requiresSpecificWorkstation(),buildable=native:isBuildableRecipe(),
        onTick=native:hasOnTickInputs() or native:hasOnTickOutputs(),
        callbacks=bridge.recipeHasCallbacks(native),specialOutputs=bridge.recipeHasSpecialOutputs(native)}
    local byIO,signature={}, {id,tostring(native:getTime()),tostring(result.surface),tostring(result.inHand),
        tostring(result.workstation),tostring(result.buildable),tostring(result.onTick),
        tostring(result.callbacks),tostring(result.specialOutputs)}
    for i=0,inputs:size()-1 do
        local row=input(native,inputs:get(i))
        if byIO[row.io] then return nil,'RECIPE_IO_INVALID' end
        byIO[row.io]=row result.inputs[#result.inputs+1]=row
        signature[#signature+1]='I:'..row.slot..':'..inputStamp(row)
    end
    -- A consumeFrom child may be embedded rather than enumerated as a root IO.
    for _,row in ipairs(result.inputs) do
        if row.io.hasParentScript and row.io:hasParentScript() then
            local parent=byIO[row.io:getParentScript()]
            if not parent then return nil,'RECIPE_IO_INVALID' end
            row.parentSlot=parent.slot
        end
        if row.consumeFrom then
            if not row.io.getConsumeFromItemScript then return nil,'CRAFT_API_UNAVAILABLE' end
            local io=row.io:getConsumeFromItemScript()
            if not io then return nil,'RECIPE_IO_INVALID' end
            local child=byIO[io] or input(native,io)
            child.parentSlot=row.slot row.child=child
            if io.getFluidMatchMode then child.matchMode=tostring(io:getFluidMatchMode()) end
            signature[#signature+1]='C:'..row.slot..':'..inputStamp(child)
        end
    end
    for i=0,outputs:size()-1 do
        local io=outputs:get(i) local possible=io:getPossibleResultItems()
        local count=possible and possible:size() or 0
        local row={io=io,resource=resource(io:getResourceType()),count=io:getIntAmount(),
            line=io:getOriginalLine(),variable=io:isVariableAmount(),chance=io:getChance(),
            onTick=io:isApplyOnTick(),createTo=io:hasCreateToItem(),choices={},
            choiceCount=count,truncated=count>Facts.choiceLimit}
        for j=0,math.min(count,Facts.choiceLimit)-1 do
            row.choices[#row.choices+1]=possible:get(j):getFullName()
        end
        result.outputs[#result.outputs+1]=row
        signature[#signature+1]=table.concat({'O',row.resource,tostring(row.count),tostring(row.variable),
            tostring(row.chance),row.line,table.concat(row.choices,';')},':')
    end
    local skills=native:getRequiredSkills()
    if skills then
        if skills:size()>64 then return nil,'RECIPE_FACTS_LIMIT' end
        for i=0,skills:size()-1 do signature[#signature+1]=tostring(skills:get(i)) end
    end
    result.signature=table.concat(signature,'\n')
    if #result.signature>16384 then return nil,'RECIPE_FACTS_LIMIT' end
    return result
end
return Facts
