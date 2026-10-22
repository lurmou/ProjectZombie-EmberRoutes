local Theme={}

local PRESETS={
    ae2={
        id="ae2",
        name="AE2 现代科技",
        icon="✦",
        radius=3,
        glow=true,
        window={r=0.035,g=0.045,b=0.055,a=0.96},
        panel={r=0.050,g=0.065,b=0.080,a=0.93},
        border={r=0.22,g=0.38,b=0.48,a=0.85},
        textColor={r=0.94,g=0.96,b=0.98,a=1},
        muted={r=0.52,g=0.64,b=0.72,a=1},
        accent={r=0.25,g=0.72,b=0.96,a=1},
        gold={r=0.96,g=0.76,b=0.25,a=1},
        selected={r=0.15,g=0.32,b=0.46,a=0.95},
        hover={r=0.12,g=0.24,b=0.35,a=0.88},
        control={r=0.07,g=0.11,b=0.15,a=1},
        primary={r=0.18,g=0.36,b=0.50,a=1},
        status={
            READY={r=0.40,g=0.85,b=0.65,a=1},
            UPDATING={r=0.96,g=0.76,b=0.25,a=1},
            ERROR={r=1.0,g=0.45,b=0.40,a=1}
        }
    },
    classic={
        id="classic",
        name="原版经典",
        icon="❖",
        radius=0,
        glow=false,
        window={r=0.045,g=0.055,b=0.06,a=0.97},
        panel={r=0.065,g=0.08,b=0.085,a=0.94},
        border={r=0.24,g=0.29,b=0.30,a=0.75},
        textColor={r=0.91,g=0.93,b=0.91,a=1},
        muted={r=0.59,g=0.66,b=0.68,a=1},
        accent={r=0.81,g=0.72,b=0.46,a=1},
        gold={r=0.81,g=0.72,b=0.46,a=1},
        selected={r=0.19,g=0.29,b=0.31,a=0.95},
        hover={r=0.14,g=0.20,b=0.22,a=0.85},
        control={r=0.10,g=0.13,b=0.14,a=1},
        primary={r=0.22,g=0.22,b=0.16,a=1},
        status={
            READY={r=0.65,g=0.82,b=0.65,a=1},
            UPDATING={r=0.81,g=0.72,b=0.46,a=1},
            ERROR={r=1.0,g=0.50,b=0.40,a=1}
        }
    }
}

local currentPreset="ae2"
local listeners={}

local function copyColor(c)
    if not c then return nil end
    return {r=c.r,g=c.g,b=c.b,a=c.a or 1}
end

function Theme.applyPreset(id)
    local preset=PRESETS[id] or PRESETS.ae2
    currentPreset=preset.id
    Theme.activePreset=preset.id
    Theme.radius=preset.radius
    Theme.glow=preset.glow
    Theme.presetName=preset.name
    Theme.presetIcon=preset.icon
    for k,v in pairs(preset) do
        if type(v)=="table" then
            if k=="status" then
                Theme.status=Theme.status or {}
                for sk,sv in pairs(v) do Theme.status[sk]=copyColor(sv) end
            else
                Theme[k]=copyColor(v)
            end
        end
    end
    for _,callback in ipairs(listeners) do
        pcall(callback,preset)
    end
end

-- Initialize default to AE2 Modern
Theme.applyPreset("ae2")

function Theme.getPreset() return currentPreset end
function Theme.getPresets() return PRESETS end

function Theme.toggle()
    local nextId=currentPreset=="ae2" and "classic" or "ae2"
    Theme.applyPreset(nextId)
    return nextId
end

function Theme.onThemeChanged(callback)
    listeners[#listeners+1]=callback
end

local function drawRoundedFill(owner,x,y,w,h,r,color)
    local a,cr,cg,cb=color.a or 1,color.r,color.g,color.b
    owner:drawRect(x+r,y,w-r*2,h,a,cr,cg,cb)
    owner:drawRect(x,y+r,r,h-r*2,a,cr,cg,cb)
    owner:drawRect(x+w-r,y+r,r,h-r*2,a,cr,cg,cb)
    if r>=2 then
        owner:drawRect(x+1,y+1,r-1,r-1,a,cr,cg,cb)
        owner:drawRect(x+w-r,y+1,r-1,r-1,a,cr,cg,cb)
        owner:drawRect(x+1,y+h-r,r-1,r-1,a,cr,cg,cb)
        owner:drawRect(x+w-r,y+h-r,r-1,r-1,a,cr,cg,cb)
    end
end

local function drawRoundedOutline(owner,x,y,w,h,r,color,glow)
    local a,cr,cg,cb=color.a or 1,color.r,color.g,color.b
    owner:drawRect(x+r,y,w-r*2,1,a,cr,cg,cb)
    owner:drawRect(x+r,y+h-1,w-r*2,1,a,cr,cg,cb)
    owner:drawRect(x,y+r,1,h-r*2,a,cr,cg,cb)
    owner:drawRect(x+w-1,y+r,1,h-r*2,a,cr,cg,cb)
    if r>=1 then
        owner:drawRect(x+1,y+1,1,1,a,cr,cg,cb)
        owner:drawRect(x+w-2,y+1,1,1,a,cr,cg,cb)
        owner:drawRect(x+1,y+h-2,1,1,a,cr,cg,cb)
        owner:drawRect(x+w-2,y+h-2,1,1,a,cr,cg,cb)
    end
    if glow and a>0.4 then
        local ga=a*0.22
        owner:drawRect(x+r,y-1,w-r*2,1,ga,cr,cg,cb)
        owner:drawRect(x+r,y+h,w-r*2,1,ga,cr,cg,cb)
        owner:drawRect(x-1,y+r,1,h-r*2,ga,cr,cg,cb)
        owner:drawRect(x+w,y+r,1,h-r*2,ga,cr,cg,cb)
    end
end

function Theme.rect(owner,x,y,width,height,color,border,radiusOverride)
    local r=radiusOverride or (Theme.radius or 0)
    if r>0 and width>=r*2 and height>=r*2 then
        if border then
            drawRoundedOutline(owner,x,y,width,height,r,color,Theme.glow)
        else
            drawRoundedFill(owner,x,y,width,height,r,color)
        end
    else
        if border then
            owner:drawRectBorder(x,y,width,height,color.a or 1,color.r,color.g,color.b)
        else
            owner:drawRect(x,y,width,height,color.a or 1,color.r,color.g,color.b)
        end
    end
end

function Theme.button(button,primary)
    button.emberPrimary=primary
    button.backgroundColor=copyColor(primary and Theme.primary or Theme.control)
    button.backgroundColorMouseOver=copyColor(Theme.selected)
    button.borderColor=copyColor(primary and Theme.accent or Theme.border)

    if not button.emberThemeInjected then
        button.emberThemeInjected=true
        local nativeDrawRect=button.drawRect
        local nativeDrawRectBorder=button.drawRectBorder
        button.drawRect=function(self,x,y,w,h,a,r,g,b)
            if Theme.radius and Theme.radius>0 then
                Theme.rect(self,x,y,w,h,{r=r,g=g,b=b,a=a},false)
            else
                nativeDrawRect(self,x,y,w,h,a,r,g,b)
            end
        end
        button.drawRectBorder=function(self,x,y,w,h,a,r,g,b)
            if Theme.radius and Theme.radius>0 then
                local color={r=r,g=g,b=b,a=a}
                if self.isMouseOver and not self.emberPrimary then
                    color=Theme.accent
                end
                Theme.rect(self,x,y,w,h,color,true)
            else
                nativeDrawRectBorder(self,x,y,w,h,a,r,g,b)
            end
        end
    end
end

function Theme.list(list)
    list.backgroundColor=copyColor(Theme.panel)
    list.borderColor=copyColor(Theme.border)
    list.drawBorder=true
end

function Theme.enable(button,enabled,primary)
    button:setEnable(enabled)
    Theme.button(button,primary and enabled)
    if not enabled then
        button.borderColor=copyColor(Theme.border)
        button.backgroundColor=copyColor(Theme.panel)
    end
end

function Theme.text(owner,label,x,y,color)
    owner:drawText(label,x,y,color.r,color.g,color.b,color.a or 1,UIFont.Small)
end

return Theme