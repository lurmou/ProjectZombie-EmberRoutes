-- Recipe discovery is incremental metadata work, never an inventory/furniture scan.
local Recipe=require "EmberRoutesProbe/ProductionRecipe"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Catalog={}
local root,source,rows,byId,position,revision,done=nil,nil,{},{},0,0,false
local queryState
local categorySet={}
local productionById,productionByType={},{}
local lastSlice
local function ensure()
    if root~=Registry.data() then
        root=Registry.data() source=nil rows={} byId={} categorySet={} position=0 revision=revision+1 done=false queryState=nil
        productionById={} productionByType={} lastSlice=nil
    end
    if not source then
        local manager=getScriptManager()
        if manager and manager.getAllCraftRecipes then source=manager:getAllCraftRecipes() end
    end
end
function Catalog.step()
    ensure() if done or not source then return end
    local clock=_G.getTimestampMs
    if type(clock)=="function" then
        local now=clock() if lastSlice and now-lastSlice<8 then return end lastSlice=now
    end
    for _=1,4 do
        if position>=source:size() then done=true revision=revision+1 break end
        local native=source:get(position) position=position+1
        local id=EmberRoutesProbeJava.recipeKey(native)
        if id~="" and not byId[id] then
            local spec,reason=Recipe.read(id)
            if spec then
                productionById[id]=spec
                for kind in pairs(spec.outputs) do
                    productionByType[kind]=productionByType[kind] or {}
                    table.insert(productionByType[kind],spec)
                end
            end
            local category=native:getCategory() or "Other"
            local row={id=id,name=native:getTranslationName(),category=category,
                supported=spec~=nil,reason=reason,surface=spec and spec.surface or false,
                product=spec and spec.product,yield=spec and spec.yield or 0}
            local searchParts={row.name,id,category,getTextOrNull("IGUI_CraftCategory_"..category) or category}
            for i=0,math.min(8,native:getOutputs():size())-1 do
                local io=native:getOutputs():get(i)
                if io:getResourceType()==ResourceType.Item then
                    local items=io:getPossibleResultItems()
                    for j=0,math.min(16,items:size())-1 do
                        local item=items:get(j) searchParts[#searchParts+1]=item:getDisplayName() searchParts[#searchParts+1]=item:getFullName()
                    end
                end
            end
            row.search=string.lower(table.concat(searchParts," "))
            rows[#rows+1]=row byId[id]=row revision=revision+1
            categorySet[category]=categorySet[category] or {supported=false}
            if row.supported then categorySet[category].supported=true end
        end
    end
end
-- Internal production lookup shares discovery with the browser; no second catalogue scan.
function Catalog.productionIndex()
    ensure() return productionById,productionByType,done
end
function Catalog.query(search,category,unsupported,page,size)
    ensure() size=math.max(1,math.min(size or 12,24))
    local result,categories,total={},{},0
    search=string.lower(string.sub(search or "",1,160)) page=math.max(1,page or 1)
    local key=search.."\n"..tostring(category).."\n"..tostring(unsupported)
    if not queryState or queryState.key~=key then queryState={key=key,matches={},position=0} end
    local matches=queryState.matches
    for i=queryState.position+1,math.min(#rows,queryState.position+128) do
        local row=rows[i]
        if row.supported or unsupported then
            if (not category or row.category==category) and string.find(row.search,search,1,true) then matches[#matches+1]=row end
        end
        queryState.position=i
    end
    for name,info in pairs(categorySet) do if info.supported or unsupported then categories[#categories+1]=name end end
    -- Metadata loads in script order. Never recursively sort a large list in Kahlua.
    -- Stable append order also prevents inventory changes from moving recipe cards.
    table.sort(categories) total=#matches
    local pages=math.max(1,math.ceil(total/size)) page=math.min(page,pages)
    for i=(page-1)*size+1,math.min(total,page*size) do
        local copy={} for k,v in pairs(matches[i]) do copy[k]=v end result[#result+1]=copy
    end
    return {rows=result,categories=categories,total=total,page=page,pages=pages,revision=revision..":"..queryState.position,
        loading=not done or queryState.position<#rows}
end
function Catalog.describe(id)
    ensure()
    local spec,reason=Recipe.read(id)
    if spec then return Recipe.describe(spec) end
    local native=getScriptManager():getCraftRecipe(id)
    return {id=id,name=native and native:getTranslationName() or id,supported=false,reason=reason,inputs={},outputs={}}
end
return Catalog
