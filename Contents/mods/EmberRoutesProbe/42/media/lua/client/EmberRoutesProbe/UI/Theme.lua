local Theme={
    -- Legacy avatar palette is registered once; moving it out of drawing preserves its appearance.
    avatarSurface={r=.04,g=.06,b=.08,a=.95},avatarHead={r=.28,g=.35,b=.42,a=.85},
    avatarBody={r=.18,g=.25,b=.32,a=.85},avatarEdge={r=1,g=1,b=1,a=.9},avatarInk={r=1,g=1,b=1,a=1}
}

local function text(key, fallback)
    local value = getTextOrNull and getTextOrNull("IGUI_EmberRoutesProbe_"..key)
    return value or key or fallback
end

-- PRESETS is built at module load, so store keys and resolve the label lazily.
local PRESET_LABEL_KEYS={ae2="Theme_ae2",classic="Theme_classic"}

local PRESETS={
    ae2={
        id="ae2",
        name="AE2 现代科技",
        labelKey=PRESET_LABEL_KEYS.ae2,        window={r=0.04,g=0.06,b=0.08,a=0.96},
        panel={r=0.06,g=0.09,b=0.13,a=0.95},
        border={r=0.22,g=0.38,b=0.52,a=0.90},
        control={r=0.09,g=0.14,b=0.20,a=1.0},
        primary={r=0.14,g=0.36,b=0.55,a=1.0},
        accent={r=0.25,g=0.75,b=1.0,a=1.0},
        gold={r=1.0,g=0.78,b=0.25,a=1.0},
        selected={r=0.14,g=0.32,b=0.48,a=0.95},
        hover={r=0.18,g=0.30,b=0.44,a=1.0},
        textColor={r=0.94,g=0.97,b=1.0,a=1.0},
        muted={r=0.50,g=0.64,b=0.75,a=1.0},
        status={
            READY={r=0.35,g=0.88,b=0.60,a=1.0},
            UPDATING={r=1.0,g=0.78,b=0.25,a=1.0},
            ERROR={r=1.0,g=0.42,b=0.38,a=1.0}
        }
    },
    classic={
        id="classic",
        name="原版经典",
        labelKey=PRESET_LABEL_KEYS.classic,
        window={r=0.045,g=0.055,b=0.06,a=0.97},
        panel={r=0.065,g=0.08,b=0.085,a=0.94},
        border={r=0.30,g=0.34,b=0.36,a=0.85},
        control={r=0.11,g=0.13,b=0.14,a=1.0},
        primary={r=0.22,g=0.22,b=0.16,a=1.0},
        accent={r=0.81,g=0.72,b=0.46,a=1.0},
        gold={r=0.81,g=0.72,b=0.46,a=1.0},
        selected={r=0.19,g=0.29,b=0.31,a=0.95},
        hover={r=0.16,g=0.22,b=0.24,a=1.0},
        textColor={r=0.91,g=0.93,b=0.91,a=1.0},
        muted={r=0.59,g=0.66,b=0.68,a=1.0},
        status={
            READY={r=0.65,g=0.82,b=0.65,a=1.0},
            UPDATING={r=0.81,g=0.72,b=0.46,a=1.0},
            ERROR={r=1.0,g=0.50,b=0.40,a=1.0}
        }
    }
}

-- Dossier roles stay restrained under both presets; other pages retain their palette.
local DOSSIER={
    background={r=.045,g=.055,b=.06,a=.97},panel={r=.065,g=.08,b=.085,a=.94},
    control={r=.11,g=.13,b=.14,a=1},separator={r=.30,g=.34,b=.36,a=.35},
    gold={r=.81,g=.72,b=.46,a=1},alert={r=1,g=.50,b=.40,a=1},
    text={r=.91,g=.93,b=.91,a=1},muted={r=.59,g=.66,b=.68,a=1},
    active={r=.46,g=.60,b=.49,a=1}
}
local currentPreset="classic"
local listeners={}

local function copyColor(c)
    if not c then return nil end
    return {r=c.r,g=c.g,b=c.b,a=c.a or 1}
end

function Theme.applyPreset(id)
    local preset=PRESETS[id] or PRESETS.ae2
    currentPreset=preset.id
    Theme.presetName=preset.name
    Theme.presetLabel=text(preset.labelKey)
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
    Theme.dossier={}
    for role,color in pairs(DOSSIER) do Theme.dossier[role]=copyColor(color) end
    Theme.revision=(Theme.revision or 0)+1
    for _,callback in ipairs(listeners) do
        pcall(callback,preset)
    end
end

-- Initialize default to AE2 Modern
Theme.applyPreset("classic")

function Theme.watch(callback)
    listeners[#listeners+1]=callback
    local live=true
    return function()
        if not live then return end
        live=false
        for i=#listeners,1,-1 do if listeners[i]==callback then table.remove(listeners,i) break end end
    end
end
function Theme.dossierList(list)
    list.backgroundColor=copyColor(Theme.dossier.background)
    list.borderColor=copyColor(Theme.dossier.separator)
    list.drawBorder=false
end
function Theme.dossierButton(button,primary)
    button.backgroundColor=copyColor(Theme.dossier.control)
    button.backgroundColorMouseOver=copyColor(Theme.dossier.panel)
    button.borderColor=copyColor(Theme.dossier.separator)
    button.textColor=copyColor(primary and Theme.dossier.text or Theme.dossier.muted)
    button.displayBackground=primary==true
    button.isBorderVisible=false
end
function Theme.getLabel() return Theme.presetLabel or text("Theme_classic") end

function Theme.toggle()
    local nextId=currentPreset=="ae2" and "classic" or "ae2"
    Theme.applyPreset(nextId)
    return nextId
end


function Theme.rect(owner,x,y,width,height,color,border)
    if not owner or not color then return end
    local a=color.a or 1
    local r=color.r or 1
    local g=color.g or 1
    local b=color.b or 1
    if border then
        owner:drawRectBorder(x,y,width,height,a,r,g,b)
    else
        owner:drawRect(x,y,width,height,a,r,g,b)
    end
end

function Theme.button(button,primary)
    if not button then return end
    button.emberPrimary=primary
    button.displayBackground=true
    button.isBorderVisible=true
    local bg=primary and Theme.primary or Theme.control
    local bc=primary and Theme.accent or Theme.border
    local hover=primary and Theme.accent or Theme.hover
    button.backgroundColor=copyColor(bg)
    button.borderColor=copyColor(bc)
    button.backgroundColorMouseOver=copyColor(hover)
    button.borderColorEnabled=copyColor(bc)
    button.backgroundColorEnabled=copyColor(bg)
    button.textColor=copyColor(Theme.textColor)
    button.textureColor=copyColor(Theme.textColor)
    if button.setBackgroundRGBA then button:setBackgroundRGBA(bg.r,bg.g,bg.b,bg.a or 1) end
    if button.setBorderRGBA then button:setBorderRGBA(bc.r,bc.g,bc.b,bc.a or 1) end
end

function Theme.styleButton(button,primary,active)
    if not button then return end
    button.emberPrimary=primary
    button.displayBackground=true
    button.isBorderVisible=true
    local bg=active and Theme.selected or (primary and Theme.primary or Theme.control)
    local bc=(active or primary) and Theme.accent or Theme.border
    local hover=primary and Theme.accent or Theme.hover
    button.backgroundColor=copyColor(bg)
    button.borderColor=copyColor(bc)
    button.backgroundColorMouseOver=copyColor(hover)
    button.borderColorEnabled=copyColor(bc)
    button.backgroundColorEnabled=copyColor(bg)
    button.textColor=copyColor(active and Theme.textColor or (primary and Theme.textColor or Theme.muted))
    button.textureColor=copyColor(Theme.textColor)
    if button.setBackgroundRGBA then button:setBackgroundRGBA(bg.r,bg.g,bg.b,bg.a or 1) end
    if button.setBorderRGBA then button:setBorderRGBA(bc.r,bc.g,bc.b,bc.a or 1) end
end

function Theme.list(list)
    if not list then return end
    list.backgroundColor=copyColor(Theme.panel)
    list.borderColor=copyColor(Theme.border)
    list.drawBorder=true
end

function Theme.enable(button,enabled,primary)
    if not button then return end
    button:setEnable(enabled)
    Theme.button(button,primary and enabled)
    if not enabled then
        local bc={r=Theme.border.r,g=Theme.border.g,b=Theme.border.b,a=0.45}
        local bg={r=Theme.panel.r,g=Theme.panel.g,b=Theme.panel.b,a=0.7}
        button.borderColor=bc
        button.backgroundColor=bg
        button.textColor=copyColor(Theme.muted)
        if button.setBorderRGBA then button:setBorderRGBA(bc.r,bc.g,bc.b,bc.a) end
        if button.setBackgroundRGBA then button:setBackgroundRGBA(bg.r,bg.g,bg.b,bg.a) end
    end
end

function Theme.text(owner,label,x,y,color)
    if not owner or not label then return end
    local c=color or Theme.textColor
    owner:drawText(label,x,y,c.r,c.g,c.b,c.a or 1,UIFont.Small)
end

return Theme
