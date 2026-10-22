-- Actual incremental catalog, fake engine metadata; no inventory APIs exist here.
local checks=0
local function check(value,message) assert(value,message) checks=checks+1 end
local root={} local calls=0
local function list(t) function t:size() return #self end function t:get(i) return self[i+1] end return t end
local natives={}
ResourceType={Item='Item'}
for i=1,1024 do
    local id='Base.Recipe'..i
    local item={getDisplayName=function() return 'Product'..i end,getFullName=function() return 'Base.Product'..i end}
    local output={getResourceType=function() return 'Item' end,getPossibleResultItems=function() return list({item}) end}
    natives[i]={id=id,getCategory=function() return 'Category'..(i%4) end,getTranslationName=function() return 'Recipe'..i end,
        getOutputs=function() return list({output}) end}
end
function getScriptManager() return {getAllCraftRecipes=function() return list(natives) end} end
function getTextOrNull() return nil end
EmberRoutesProbeJava={recipeKey=function(recipe) return recipe.id end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/ProductionRecipe']={read=function(id)
    calls=calls+1
    if id=='Base.Recipe5' then return nil,'RECIPE_MECHANISM_UNSUPPORTED' end
    return {product='Base.Product',yield=1,surface=false}
end}
local Catalog=require 'EmberRoutesProbe/CraftingCatalog'
Catalog.step()
local result=Catalog.query('',nil,false,1,12)
check(calls==4 and result.loading and result.total==4,'first slice inspects only four native recipes and reports partial loading')
for _=1,256 do Catalog.step() end
result=Catalog.query('Product1000',nil,false,1,12)
check(result.loading and result.total==0,'new search is bounded instead of scanning the complete directory in one frame')
for _=1,8 do result=Catalog.query('Product1000',nil,false,1,12) end
check(not result.loading and result.total==1 and result.rows[1].id=='Base.Recipe1000','translated product names participate in search')
for _=1,8 do result=Catalog.query('Recipe5',nil,false,1,24) end
local unsupported=false for _,row in ipairs(result.rows) do if row.id=='Base.Recipe5' then unsupported=true end end
check(not unsupported,'unsupported execution mechanism is excluded by default')
for _=1,8 do result=Catalog.query('Recipe5',nil,true,1,24) end
unsupported=false for _,row in ipairs(result.rows) do if row.id=='Base.Recipe5' then unsupported=not row.supported end end
check(unsupported,'explicit mechanism filter exposes unavailable recipe without enabling execution')
local key=result.rows[1].id result.rows[1].id='corrupted'
result=Catalog.query('Recipe5',nil,true,1,24)
check(result.rows[1].id==key,'row snapshots do not expose mutable catalog records')
root={} result=Catalog.query('',nil,false,1,12)
check(result.total==0 and result.loading,'world transition discards the old recipe index')
print('PASS '..checks..' bounded catalog contracts; native metadata mocked')
