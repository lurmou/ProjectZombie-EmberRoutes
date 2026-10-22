-- Type icons only; never instantiate or retain a physical InventoryItem.
local Presentation={}
local methods={}
methods.__index=methods
function Presentation.new() return setmetatable({icons={}},methods) end
function methods:icon(fullType)
    if type(fullType)~="string" or fullType=="" then return nil end
    local cached=self.icons[fullType]
    if cached~=nil then return cached or nil end
    local texture
    local getManager=_G.getScriptManager
    local manager=type(getManager)=="function" and getManager() or nil
    local item=manager and manager:FindItem(fullType)
    if item then
        texture=item:getNormalTexture()
        local variants=item.getIconsForTexture and item:getIconsForTexture()
        if variants and not variants:isEmpty() then
            -- The engine returns ArrayList<String>, not Texture objects.
            local name=variants:get(0)
            local tryGet=_G.tryGetTexture
            if type(name)=="string" and name~="" and type(tryGet)=="function" then
                texture=tryGet("Item_"..name) or texture
            end
        end
    end
    self.icons[fullType]=texture or false
    return texture
end
function methods:clear() self.icons={} end
return Presentation
