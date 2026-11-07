-- Explicit execution capabilities; native recipe facts remain in the shared catalog.
-- Extensions register a verified original-preserving food family here.
local P={}
local results={['Base.PotOfSoupRecipe']='SOUP',['Base.PotOfStew']='STEW',
    ['Base.PanFriedVegetables']='STIRFRY',['Base.Salad']='SALAD'}
function P.register(fullType,family)
    if type(fullType)~='string' or #fullType>256 or not string.find(fullType,'.',1,true)
        or (family~='SOUP' and family~='STEW' and family~='STIRFRY' and family~='SALAD') then return false end
    if results[fullType] and results[fullType]~=family then return false end
    results[fullType]=family return true
end
function P.meal(fullType) return results[fullType]~=nil end
function P.accept(recipe) return results[recipe:getFullResultItem()]~=nil end
return P
