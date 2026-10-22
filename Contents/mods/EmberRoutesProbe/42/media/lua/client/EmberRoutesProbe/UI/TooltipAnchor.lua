-- B42.21 lists/text entries assign local mouse positions to a top-level tooltip.
-- Its prerender draws there before render moves it to screen coordinates.
-- Scope the correction to our instances; keep vanilla tooltip content/lifecycle.
local Anchor={}
---@param widget table
function Anchor.position(widget)
    ---@type ISToolTip?
    local tooltip=widget.tooltipUI
    if tooltip and tooltip:getIsVisible() and tooltip.followMouse~=false
            and not (tooltip.desiredX and tooltip.desiredY) then
        -- Match installed ISToolTip.render before its first background draw.
        tooltip:setX(getMouseX()+32)
        tooltip:setY(getMouseY()+10)
    end
end
---@param widget table
---@param method string
function Anchor.attach(widget,method)
    local native=widget[method]
    if type(native)~="function" then return end
    widget[method]=function(self,...)
        local result=native(self,...)
        Anchor.position(self)
        return result
    end
end
---@param widget table?
function Anchor.clear(widget)
    local tooltip=widget and widget.tooltipUI
    if tooltip then
        tooltip:setVisible(false)
        tooltip:removeFromUIManager()
    end
end
return Anchor
