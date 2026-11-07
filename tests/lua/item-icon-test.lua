local Presentation=require 'EmberRoutesProbe/UI/ItemPresentation'
local normal,variant={},{} local calls=0
function getScriptManager() return {FindItem=function(_,id)
    if id=='missing' then return nil end
    if id=='tinted' then
        return {
            getNormalTexture=function() return normal end,
            getR=function() return 0.8 end,
            getG=function() return 0.2 end,
            getB=function() return 0.1 end
        }
    end
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

local tr,tg,tb=icons:color('tinted')
assert(math.abs(tr-0.8)<0.001 and math.abs(tg-0.2)<0.001 and math.abs(tb-0.1)<0.001,'tinted item returns script colors')
local mr,mg,mb=icons:color('missing')
assert(mr==1 and mg==1 and mb==1,'missing items default to 1,1,1 color')
local nr,ng,nb=icons:color('normal')
assert(nr==1 and ng==1 and nb==1,'untinted items default to 1,1,1 color')

icons:clear() assert(icons:icon('variant')==variant and calls==3,'clear discards cached resolutions')
print('PASS 9 icon texture and color contracts; engine metadata/texture loading mocked')
