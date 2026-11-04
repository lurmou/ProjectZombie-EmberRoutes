-- Actual catalog, complete detached native-metadata contract; no inventory access.
local function list(t) function t:size() return #self end function t:get(i) return self[i+1] end return t end
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/CookingOrders']={describe=function() end}
package.loaded['EmberRoutesProbe/CraftRecipeFacts']={read=function(id)
 return {id=id,outputs={{resource='Item',choices=id=='other' and {'Base.Other'} or {'Base.Primary','Base.Plank'}}}}
end}
package.loaded['EmberRoutesProbe/ProductionRecipe']={fromFacts=function(f)
 return {product=f.id=='other' and 'Base.Other' or 'Base.Primary',yield=1,outputs={['Base.Primary']=1,['Base.Plank']=1}}
end}
local recipes={}
for _,id in ipairs({'one','two','other'}) do
 recipes[#recipes+1]={id=id,getCategory=function() return 'Wood' end,getTranslationName=function() return id end,getOutputs=function() return list({}) end}
end
function getScriptManager() return {getAllCraftRecipes=function() return list(recipes) end} end
function getTextOrNull() end
EmberRoutesProbeJava={recipeKey=function(r) return r.id end}
local C=require 'EmberRoutesProbe/CraftingCatalog'
C.step()
local s=C.query('',nil,false,1,24,'Base.Plank')
assert(s.total==2 and s.rows[1].id=='one' and s.rows[2].id=='two','matches secondary outputs and all producing recipes')
s.rows[1].outputTypes['Base.Plank']=false
s=C.query('',nil,false,1,24,'Base.Plank')
assert(s.rows[1].outputTypes['Base.Plank'],'detached output metadata cannot change filter authority')
s=C.query('',nil,false,1,24,'Base.Impossible')
assert(s.total==0 and #s.rows==0 and not s.loading,'exact product filtering returns empty, not a similar recipe')
print('ui-product-filter: 3 PASS; actual incremental catalog')
