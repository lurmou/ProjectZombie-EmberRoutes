-- Type icons and default script colors only; never instantiate or retain a physical InventoryItem.
local Presentation={}
local methods={}
methods.__index=methods
function Presentation.new() return setmetatable({icons={},colors={}},methods) end
function methods:icon(fullType)
    if type(fullType)~="string" or fullType=="" then return nil end
    local cached=self.icons[fullType]
    if cached~=nil then return cached or nil end
    local texture
    local r,g,b=1,1,1
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
        if item.getR then
            local vr=tonumber(item:getR())
            if vr and vr>=0 and vr<=1 then r=vr end
        end
        if item.getG then
            local vg=tonumber(item:getG())
            if vg and vg>=0 and vg<=1 then g=vg end
        end
        if item.getB then
            local vb=tonumber(item:getB())
            if vb and vb>=0 and vb<=1 then b=vb end
        end
    end
    self.icons[fullType]=texture or false
    self.colors[fullType]={r,g,b}
    return texture
end
function methods:color(fullType)
    if type(fullType)~="string" or fullType=="" then return 1,1,1 end
    local c=self.colors[fullType]
    if c then return c[1],c[2],c[3] end
    self:icon(fullType)
    c=self.colors[fullType]
    if c then return c[1],c[2],c[3] end
    return 1,1,1
end
function methods:clear()
    self.icons={}
    self.colors={}
end
return Presentation
