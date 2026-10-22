local Presentation=require 'EmberRoutesProbe/UI/ItemPresentation'
local normal,variant={},{} local calls=0
function getScriptManager() return {FindItem=function(_,id)
    if id=='missing' then return nil end
    return {getNormalTexture=function() return normal end,getIconsForTexture=function()
        return {isEmpty=function() return id=='normal' end,get=function() return id end}
    end}
end} end
function tryGetTexture(name) calls=calls+1 if name=='Item_variant' then return variant end end
local icons=Presentation.new()
assert(icons:icon('variant')==variant,'variant name must resolve to a texture object')
assert(icons:icon('variant')==variant and calls==1,'resolved texture is cached')
assert(icons:icon('absent-variant')==normal,'missing variant texture falls back to normal texture')
assert(icons:icon('normal')==normal,'normal texture stays a texture object')
assert(icons:icon('missing')==nil and icons:icon(nil)==nil,'missing scripts and absent types have no icon')
icons:clear() assert(icons:icon('variant')==variant and calls==3,'clear discards cached resolutions')
print('PASS 6 icon texture contracts; engine metadata/texture loading mocked')
