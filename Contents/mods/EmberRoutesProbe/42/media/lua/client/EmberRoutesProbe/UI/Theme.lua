local Theme={
    window={r=0.045,g=0.055,b=0.06,a=0.97},panel={r=0.065,g=0.08,b=0.085,a=0.94},
    border={r=0.24,g=0.29,b=0.30,a=0.75},textColor={r=0.91,g=0.93,b=0.91,a=1},
    muted={r=0.59,g=0.66,b=0.68,a=1},accent={r=0.81,g=0.72,b=0.46,a=1},
    selected={r=0.19,g=0.29,b=0.31,a=0.95},hover={r=0.14,g=0.20,b=0.22,a=0.85},
    control={r=0.10,g=0.13,b=0.14,a=1},primary={r=0.22,g=0.22,b=0.16,a=1},
    status={READY={r=0.65,g=0.82,b=0.65,a=1},UPDATING={r=0.81,g=0.72,b=0.46,a=1},ERROR={r=1,g=0.5,b=0.4,a=1}}}
local function copy(c) return {r=c.r,g=c.g,b=c.b,a=c.a} end
function Theme.button(button,primary)
    button.backgroundColor=copy(primary and Theme.primary or Theme.control)
    button.backgroundColorMouseOver=copy(Theme.selected)
    button.borderColor=copy(Theme.border)
end
function Theme.list(list)
    list.backgroundColor=copy(Theme.panel) list.borderColor=copy(Theme.border) list.drawBorder=true
end
-- Vanilla disables buttons with a red border; reserve red for actionable errors.
function Theme.enable(button,enabled,primary)
    button:setEnable(enabled)
    Theme.button(button,primary and enabled)
    if not enabled then
        button.borderColor=copy(Theme.border)
        button.backgroundColor=copy(Theme.panel)
    end
end
function Theme.text(owner,label,x,y,color)
    owner:drawText(label,x,y,color.r,color.g,color.b,color.a,UIFont.Small)
end
function Theme.rect(owner,x,y,width,height,color,border)
    if border then owner:drawRectBorder(x,y,width,height,color.a,color.r,color.g,color.b)
    else owner:drawRect(x,y,width,height,color.a,color.r,color.g,color.b) end
end
return Theme
