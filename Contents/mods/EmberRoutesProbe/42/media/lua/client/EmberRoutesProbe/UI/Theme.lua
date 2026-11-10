local Theme={
    -- Avatar palette is registered once; moving it out of drawing preserves its appearance.
    avatarSurface={r=.04,g=.06,b=.08,a=.95},avatarHead={r=.28,g=.35,b=.42,a=.85},
    avatarBody={r=.18,g=.25,b=.32,a=.85},avatarEdge={r=1,g=1,b=1,a=.9},avatarInk={r=1,g=1,b=1,a=1}
}

local function text(key, fallback)
    local value = getTextOrNull and getTextOrNull("IGUI_EmberRoutesProbe_"..key)
    return value or key or fallback
end

local PRESET_LABEL_KEYS={github="Theme_github",ae2="Theme_ae2",classic="Theme_classic"}

local PRESETS={
    github={
        id="github",
        name="GitHub 暗黑极简",
        labelKey=PRESET_LABEL_KEYS.github,
        window={r=0.051,g=0.067,b=0.090,a=0.98},      -- #0d1117 Canvas Default
        panel={r=0.086,g=0.106,b=0.133,a=0.95},       -- #161b22 Canvas Subtle (Card)
        cardHeader={r=0.071,g=0.090,b=0.118,a=1.0},  -- #12171e Card Header
        border={r=0.188,g=0.212,b=0.239,a=0.90},      -- #30363d Border Default
        borderSubtle={r=0.129,g=0.149,b=0.176,a=0.85},-- #21262d Border Subtle
        control={r=0.129,g=0.149,b=0.176,a=1.0},     -- #21262d Button Normal
        primary={r=0.137,g=0.525,b=0.212,a=1.0},     -- #238636 Primary Button (GitHub Green)
        primaryBorder={r=0.24,g=0.68,b=0.32,a=1.0},
        primaryHover={r=0.180,g=0.627,b=0.263,a=1.0},-- #2ea043
        primaryHoverBorder={r=0.25,g=0.73,b=0.31,a=1.0}, -- #3fb950
        accent={r=0.345,g=0.651,b=1.000,a=1.0},      -- #58a6ff Link/Focus Accent
        gold={r=0.824,g=0.600,b=0.133,a=1.0},        -- #d29922 Subdued Warning
        selected={r=0.188,g=0.212,b=0.239,a=1.0},    -- #30363d Active Fill (Elevated)
        selectedBorder={r=0.545,g=0.580,b=0.620,a=1.0}, -- #8b949e Active Outline
        hover={r=0.188,g=0.212,b=0.239,a=1.0},       -- #30363d Hover Fill
        hoverBorder={r=0.545,g=0.580,b=0.620,a=1.0}, -- #8b949e Hover Outline
        textColor={r=0.902,g=0.929,b=0.953,a=1.0},   -- #e6edf3 Foreground Default
        muted={r=0.545,g=0.580,b=0.620,a=1.0},       -- #8b949e Foreground Muted
        status={
            READY={r=0.247,g=0.725,b=0.314,a=1.0},   -- #3fb950
            UPDATING={r=0.824,g=0.600,b=0.133,a=1.0},-- #d29922
            ERROR={r=0.973,g=0.318,b=0.286,a=1.0}    -- #f85149
        }
    },
    ae2={
        id="ae2",
        name="AE2 现代科技",
        labelKey=PRESET_LABEL_KEYS.ae2,
        window={r=0.04,g=0.06,b=0.08,a=0.96},
        panel={r=0.06,g=0.09,b=0.13,a=0.95},
        cardHeader={r=0.08,g=0.12,b=0.18,a=1.0},
        border={r=0.22,g=0.38,b=0.52,a=0.90},
        borderSubtle={r=0.14,g=0.24,b=0.34,a=0.85},
        control={r=0.09,g=0.14,b=0.20,a=1.0},
        primary={r=0.14,g=0.36,b=0.55,a=1.0},
        primaryBorder={r=0.25,g=0.75,b=1.0,a=1.0},
        primaryHover={r=0.20,g=0.45,b=0.68,a=1.0},
        accent={r=0.25,g=0.75,b=1.0,a=1.0},
        gold={r=1.0,g=0.78,b=0.25,a=1.0},
        selected={r=0.14,g=0.32,b=0.48,a=0.95},
        selectedBorder={r=0.25,g=0.75,b=1.0,a=1.0},
        hover={r=0.18,g=0.30,b=0.44,a=1.0},
        hoverBorder={r=0.25,g=0.75,b=1.0,a=1.0},
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
        cardHeader={r=0.085,g=0.10,b=0.11,a=1.0},
        border={r=0.30,g=0.34,b=0.36,a=0.85},
        borderSubtle={r=0.20,g=0.24,b=0.26,a=0.80},
        control={r=0.11,g=0.13,b=0.14,a=1.0},
        primary={r=0.22,g=0.22,b=0.16,a=1.0},
        primaryBorder={r=0.81,g=0.72,b=0.46,a=1.0},
        primaryHover={r=0.28,g=0.28,b=0.20,a=1.0},
        accent={r=0.81,g=0.72,b=0.46,a=1.0},
        gold={r=0.81,g=0.72,b=0.46,a=1.0},
        selected={r=0.19,g=0.29,b=0.31,a=0.95},
        selectedBorder={r=0.81,g=0.72,b=0.46,a=1.0},
        hover={r=0.16,g=0.22,b=0.24,a=1.0},
        hoverBorder={r=0.81,g=0.72,b=0.46,a=1.0},
        textColor={r=0.91,g=0.93,b=0.91,a=1.0},
        muted={r=0.59,g=0.66,b=0.68,a=1.0},
        status={
            READY={r=0.65,g=0.82,b=0.65,a=1.0},
            UPDATING={r=0.81,g=0.72,b=0.46,a=1.0},
            ERROR={r=1.0,g=0.50,b=0.40,a=1.0}
        }
    }
}

-- Dossier roles stay restrained under presets; other pages retain their palette.
local DOSSIER={
    background={r=.045,g=.055,b=.06,a=.97},panel={r=.065,g=.08,b=.085,a=.94},
    control={r=.11,g=.13,b=.14,a=1},separator={r=.30,g=.34,b=.36,a=.35},
    gold={r=.81,g=.72,b=.46,a=1},alert={r=1,g=.50,b=.40,a=1},
    text={r=.91,g=.93,b=.91,a=1},muted={r=.59,g=.66,b=.68,a=1},
    active={r=.46,g=.60,b=.49,a=1}
}
local currentPreset="github"
local listeners={}

local function copyColor(c)
    if not c then return nil end
    return {r=c.r,g=c.g,b=c.b,a=c.a or 1}
end

function Theme.applyPreset(id)
    local preset=PRESETS[id] or PRESETS.github
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
    Theme.danger=Theme.status and Theme.status.ERROR or {r=0.973,g=0.318,b=0.286,a=1.0}
    Theme.revision=(Theme.revision or 0)+1
    for _,callback in ipairs(listeners) do
        pcall(callback,preset)
    end
end

-- Initialize default to GitHub Primer Dark
Theme.applyPreset("github")

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

function Theme.getLabel() return Theme.presetLabel or text("Theme_github") end

function Theme.toggle()
    local nextId="github"
    if currentPreset=="github" then nextId="ae2"
    elseif currentPreset=="ae2" then nextId="classic"
    else nextId="github" end
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

local function hookTactileButton(button)
    if button._emberSkinned then return end
    button._emberSkinned = true
    button.yoffset = 0
    local origPrerender = button.prerender
    button.prerender = function(self)
        if not self:getIsVisible() then
            if origPrerender then origPrerender(self) end
            return
        end
        local isDown = self.pressed and self.enable
        local isHover = ((self.mouseOver and self:isMouseOver()) or self.joypadFocused) and self.enable and not isDown

        if isDown then
            self.yoffset = 1
        else
            self.yoffset = 0
        end

        -- Synchronize dynamic hover border and text highlighting (Zero-GC pointer swap)
        if self.isBorderVisible and self.enable then
            if isHover then
                if self.emberHoverBorder then self.borderColor = self.emberHoverBorder end
                if self.emberHoverText then self.textColor = self.emberHoverText end
            else
                if self.emberNormalBorder then self.borderColor = self.emberNormalBorder end
                if self.emberNormalText then self.textColor = self.emberNormalText end
            end
        end

        if origPrerender then origPrerender(self) end

        if isDown and self.displayBackground then
            -- Mechanical top inset shadow line on press (Active state)
            self:drawRect(0, 0, self.width, 1, 0.65, 0, 0, 0)
        end

        -- Focus State: 2px Focus Ring outline (Keyboard Tab / Controller Focus)
        local isFocused = (self.joypadFocused or self.isFocused == true) and self.enable
        if isFocused and self.isBorderVisible then
            local fc = Theme.accent
            self:drawRectBorder(-2, -2, self.width + 4, self.height + 4, 0.85, fc.r, fc.g, fc.b)
        end

        -- Loading State: kinetic pulse / submitting indicator
        if self.loading then
            local t = (getTimestampMs and getTimestampMs()) or (os.time() * 1000)
            local dotCount = (math.floor(t / 350) % 3) + 1
            local dots = (dotCount == 1 and '.') or (dotCount == 2 and '..') or '...'
            local lText = (self.loadingText or (self.origTitle or self.title or '')) .. dots
            local tm = getTextManager()
            local tw = tm and tm:MeasureStringX(self.font or UIFont.Small, lText) or (#lText * 8)
            local th = tm and tm:getFontHeight(self.font or UIFont.Small) or 14
            local tx = math.floor((self.width - tw) / 2)
            local ty = math.floor((self.height - th) / 2) + self.yoffset
            self:drawRect(0, 0, self.width, self.height, 0.85, 0.08, 0.10, 0.14)
            self:drawRectBorder(0, 0, self.width, self.height, 0.80, Theme.accent.r, Theme.accent.g, Theme.accent.b)
            Theme.text(self, lText, tx, ty, Theme.accent, self.font or UIFont.Small)
        end
    end

    function button:setLoading(isLoading, loadingText)
        if isLoading then
            if not self.origTitle then self.origTitle = self.title end
            self.loading = true
            self.loadingText = loadingText
            self.enable = false
        else
            self.loading = false
            self.enable = true
            if self.origTitle then
                self:setTitle(self.origTitle)
                self.origTitle = nil
            end
        end
    end
end

---Draws a 2px outer Focus Ring around any bounding rectangle.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param height number
---@param color table?
function Theme.focusRing(owner, x, y, width, height, color)
    local c = color or Theme.accent
    owner:drawRectBorder(x - 2, y - 2, width + 4, height + 4, 0.85, c.r, c.g, c.b)
end

---Draws an auxiliary form helper text or disabled reason line.
---@param owner ISPanel
---@param x number
---@param y number
---@param width number
---@param helperText string
---@param isError boolean?
function Theme.formHelper(owner, x, y, width, helperText, isError)
    if not owner or not helperText or helperText == '' then return end
    local c = isError and (Theme.status and Theme.status.ERROR or Theme.accent) or Theme.muted
    Theme.text(owner, helperText, x, y, c, UIFont.Small)
end

function Theme.button(button,primary)
    if not button then return end
    hookTactileButton(button)
    button.emberPrimary=primary
    button.displayBackground=true
    button.isBorderVisible=true
    local bg=primary and Theme.primary or Theme.control
    local bc=primary and (Theme.primaryBorder or Theme.accent) or Theme.border
    local hover=primary and (Theme.primaryHover or Theme.hover) or Theme.hover
    local hoverBc=primary and (Theme.primaryHoverBorder or Theme.status.READY) or (Theme.hoverBorder or Theme.selectedBorder)
    local textC=primary and {r=1,g=1,b=1,a=1} or Theme.textColor
    local textHover={r=1,g=1,b=1,a=1}

    button.emberNormalBorder=copyColor(bc)
    button.emberHoverBorder=copyColor(hoverBc)
    button.emberNormalText=copyColor(textC)
    button.emberHoverText=copyColor(textHover)

    button.backgroundColor=copyColor(bg)
    button.borderColor=copyColor(bc)
    button.backgroundColorMouseOver=copyColor(hover)
    button.borderColorEnabled=copyColor(bc)
    button.backgroundColorEnabled=copyColor(bg)
    button.textColor=copyColor(textC)
    button.textureColor=copyColor(textC)
    if button.setBackgroundRGBA then button:setBackgroundRGBA(bg.r,bg.g,bg.b,bg.a or 1) end
    if button.setBorderRGBA then button:setBorderRGBA(bc.r,bc.g,bc.b,bc.a or 1) end
end

function Theme.styleButton(button,primary,active)
    if not button then return end
    hookTactileButton(button)
    button.emberPrimary=primary
    button.emberActive=active
    button.displayBackground=true
    button.isBorderVisible=true
    local bg=active and Theme.selected or (primary and Theme.primary or Theme.control)
    local bc=active and (Theme.selectedBorder or Theme.muted) or (primary and (Theme.primaryBorder or Theme.accent) or Theme.border)
    local hover=active and Theme.selected or (primary and (Theme.primaryHover or Theme.hover) or Theme.hover)
    local hoverBc=active and (Theme.selectedBorder or Theme.muted) or (primary and (Theme.primaryHoverBorder or Theme.status.READY) or (Theme.hoverBorder or Theme.selectedBorder))
    local textC=(active or primary) and {r=1,g=1,b=1,a=1} or Theme.textColor
    local textHover={r=1,g=1,b=1,a=1}

    button.emberNormalBorder=copyColor(bc)
    button.emberHoverBorder=copyColor(hoverBc)
    button.emberNormalText=copyColor(textC)
    button.emberHoverText=copyColor(textHover)

    button.backgroundColor=copyColor(bg)
    button.borderColor=copyColor(bc)
    button.backgroundColorMouseOver=copyColor(hover)
    button.borderColorEnabled=copyColor(bc)
    button.backgroundColorEnabled=copyColor(bg)
    button.textColor=copyColor(textC)
    button.textureColor=copyColor(textC)
    if button.setBackgroundRGBA then button:setBackgroundRGBA(bg.r,bg.g,bg.b,bg.a or 1) end
    if button.setBorderRGBA then button:setBorderRGBA(bc.r,bc.g,bc.b,bc.a or 1) end
end

---Draws a clean, zero-GC card background and perimeter border without vertical side stripes.
---@param panel any ISPanel or drawing context
---@param bounds table { x, y, width, height, visible }
---@param opts table? Optional { headerHeight }
function Theme.drawCard(panel, bounds, opts)
    if not panel or not bounds or bounds.visible == false then return end
    local x = bounds.x or 0
    local y = bounds.y or 0
    local w = bounds.width or 0
    local h = bounds.height or 0
    if w <= 0 or h <= 0 then return end

    local p = Theme.panel
    local b = Theme.border
    panel:drawRect(x, y, w, h, p.a or 0.95, p.r, p.g, p.b)
    panel:drawRectBorder(x, y, w, h, b.a or 0.90, b.r, b.g, b.b)

    if opts and opts.headerHeight and opts.headerHeight > 0 then
        local bs = Theme.borderSubtle or b
        panel:drawRect(x + 1, y + opts.headerHeight, w - 2, 1, bs.a or 0.85, bs.r, bs.g, bs.b)
    end
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
        button.emberNormalBorder=bc
        button.emberHoverBorder=bc
        button.emberNormalText=Theme.muted
        button.emberHoverText=Theme.muted
        if button.setBorderRGBA then button:setBorderRGBA(bc.r,bc.g,bc.b,bc.a) end
        if button.setBackgroundRGBA then button:setBackgroundRGBA(bg.r,bg.g,bg.b,bg.a) end
    end
end

function Theme.combo(comboBox)
    if not comboBox then return end
    comboBox.backgroundColor = copyColor(Theme.control)
    comboBox.borderColor = copyColor(Theme.border)
    comboBox.backgroundColorMouseOver = copyColor(Theme.hover or Theme.control)
    comboBox.textColor = copyColor(Theme.textColor)
    if comboBox.popup then
        comboBox.popup.backgroundColor = copyColor(Theme.panel)
        comboBox.popup.borderColor = copyColor(Theme.border)
        comboBox.popup.drawBorder = true
    end
end

function Theme.input(entry)
    if not entry then return end
    entry.backgroundColor = copyColor(Theme.panel)
    entry.borderColor = copyColor(Theme.border)
    entry.textColor = copyColor(Theme.textColor)
end

function Theme.text(owner,label,x,y,color,font)
    if not owner or not label then return end
    local c=color or Theme.textColor
    owner:drawText(label,x,y,c.r,c.g,c.b,c.a or 1,font or UIFont.Small)
end

return Theme
