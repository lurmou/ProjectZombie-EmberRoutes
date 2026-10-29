--[[
    Avatar3DView.lua - EmberRoutes UI
    Static cached 3D character portrait.

    Bakes the worker's actual 3D model appearance into a single cached texture
    via the engine DeadBodyAtlas (the same tech ProjectRemnants uses for party
    portraits) and draws that ONE image. This replaces the earlier per-frame
    ISUI3DModel viewport, so roster render cost is independent of NPC count and
    the人员管理 screen never spins up a live skeletal-animation view per worker.

    Draw crop constants (PORTRAIT_TEXTURE_ZOOM / Y_OFFSET) are replicated from
    the proven ProjectRemnants NPCFW_PartyPortrait path.
]]

require "ISUI/ISPanel"
local Theme = require "EmberRoutesProbe/UI/Theme"

---@class EmberRoutesAvatar3DView:ISPanel
---@field fontHeight number
---@field pad number
---@field character IsoGameCharacter?
---@field survivorDesc SurvivorDesc?
---@field isBust boolean
---@field injuryAlert boolean
---@field statusText string?
---@field statusColor table?
local Avatar3DView = ISPanel:derive("EmberRoutesAvatar3DView")

-- Crop presets replicated from ProjectRemnants NPCFW_PartyPortrait (proven).
local PORTRAIT_TEXTURE_ZOOM      = 5.5    -- head-and-torso bust framing
local PORTRAIT_TEXTURE_Y_OFFSET  = -0.70
local FULLBODY_TEXTURE_ZOOM      = 2.2    -- whole-body framing
local FULLBODY_TEXTURE_Y_OFFSET  = 0.0

---@param x number
---@param y number
---@param width number
---@param height number
---@return EmberRoutesAvatar3DView
function Avatar3DView:new(x, y, width, height)
    local o = ISPanel.new(self, x, y, width, height)
    o.background = false
    o.fontHeight = getTextManager():getFontHeight(UIFont.Small)
    o.pad = math.ceil(o.fontHeight * 0.4)
    o.character = nil
    o.survivorDesc = nil
    o.isBust = true
    o.injuryAlert = false
    o.statusText = nil
    o.statusColor = nil
    o.fallbackTexture = nil
    o.fallbackInitials = nil
    -- Cached portrait (a Texture userdata from the Java bridge).
    o.portraitTexture = nil
    o.portraitCharacter = nil
    o.portraitRefreshAt = 0
    o:initialise()
    return o
end

function Avatar3DView:initialise()
    ISPanel.initialise(self)
end

function Avatar3DView:createChildren()
    -- No live 3D viewport. The portrait is a single cached texture drawn in
    -- prerender, so this widget costs nothing per frame.
    ISPanel.createChildren(self)
end

---Toggle between Face/Torso bust framing and full-body framing.
---This only swaps the draw crop preset; it does not re-render a 3D model.
function Avatar3DView:toggleBust()
    self.isBust = not self.isBust
end

---Update character reference and cached-portrait source.
---@param character IsoGameCharacter?
---@param desc SurvivorDesc?
---@param fallbackOpts table? {texture=Texture, initials=string, injury=boolean}
function Avatar3DView:setCharacter(character, desc, fallbackOpts)
    self.character = character
    self.survivorDesc = desc or (character and character.getDescriptor and character:getDescriptor())
    fallbackOpts = fallbackOpts or {}
    self.fallbackTexture = fallbackOpts.texture
    self.fallbackInitials = fallbackOpts.initials
    self.initialsW = self.fallbackInitials and getTextManager():MeasureStringX(UIFont.Small, self.fallbackInitials) or 0
    self.injuryAlert = fallbackOpts.injury or false

    -- Force a portrait re-fetch whenever the bound character changes.
    if self.portraitCharacter ~= character then
        self.portraitTexture = nil
        self.portraitCharacter = character
        self.portraitRefreshAt = 0
    end
end

---Force the next prerender to re-bake the portrait (call after clothing/equip change).
function Avatar3DView:invalidatePortrait()
    if self.portraitCharacter then
        self.portraitRefreshAt = 0
    end
end

---Lazily (re)bake the portrait texture via the Java bridge. Throttled so the
---Lua->Java round-trip only happens when the character or equipment changes.
function Avatar3DView:fetchPortrait()
    local character = self.character
    if not character then
        self.portraitTexture = nil
        self.portraitCharacter = nil
        self.portraitRefreshAt = 0
        return
    end
    local now = getTimestampMs and getTimestampMs() or 0
    if now < self.portraitRefreshAt then return end
    local ok, tex = pcall(function()
        if EmberRoutesProbeJava and EmberRoutesProbeJava.getPortraitTexture then
            return EmberRoutesProbeJava.getPortraitTexture(character)
        end
        return nil
    end)
    if ok and tex then
        self.portraitTexture = tex
        self.portraitRefreshAt = now + 1000
    else
        -- Brief back-off; the caller's fallback (profession icon / initials) shows meanwhile.
        self.portraitRefreshAt = now + 100
    end
end

function Avatar3DView:prerender()
    ISPanel.prerender(self)
    local p = self.pad

    -- 1. Dark survival frame with subtle border
    Theme.rect(self, 0, 0, self.width, self.height, {r = 0.04, g = 0.06, b = 0.08, a = 0.95})
    Theme.rect(self, 0, 0, self.width, self.height, Theme.border, true)

    -- 2. Ensure the cached portrait is fresh, then draw it (or fall back).
    self:fetchPortrait()

    local hasPortrait = self.portraitTexture ~= nil
    if hasPortrait then
        local zoom = self.isBust and PORTRAIT_TEXTURE_ZOOM or FULLBODY_TEXTURE_ZOOM
        local yOff = self.isBust and PORTRAIT_TEXTURE_Y_OFFSET or FULLBODY_TEXTURE_Y_OFFSET
        local size = self.width - p * 2
        local texSize = size * zoom
        local tx = (self.width - texSize) / 2
        local ty = p + size * yOff
        self:setStencilRect(p, p, size, size)
        self:drawTextureScaledAspect(self.portraitTexture, tx, ty, texSize, texSize, 1, 1, 1, 1)
        self:clearStencilRect()
    else
        -- 3. Fallback rendering when the portrait is unavailable.
        local cx = math.floor(self.width / 2)
        local cy = math.floor(self.height / 2)

        if self.fallbackTexture then
            self:drawTextureScaledAspect(self.fallbackTexture, p, p, self.width - p * 2, self.height - p * 2, 1, 1, 1, 1)
        else
            -- Clean silhouette
            local headR = math.max(6, math.floor(self.height * 0.18))
            local headY = math.floor(self.height * 0.15)
            Theme.rect(self, cx - headR, headY, headR * 2, headR * 2, {r = 0.28, g = 0.35, b = 0.42, a = 0.85})
            local bodyW = math.max(12, math.floor(self.width * 0.55))
            local bodyH = math.max(8, math.floor(self.height * 0.35))
            local bodyY = headY + headR * 2 + 2
            Theme.rect(self, cx - math.floor(bodyW / 2), bodyY, bodyW, bodyH, {r = 0.18, g = 0.25, b = 0.32, a = 0.85})

            if self.fallbackInitials and self.fallbackInitials ~= "" then
                local tw = self.initialsW or 0
                local th = self.fontHeight
                Theme.text(self, self.fallbackInitials, cx - math.floor(tw / 2), headY + math.floor((headR * 2 - th) / 2), Theme.gold)
            end
        end
    end

    -- 4. Injury Warning Badge Overlay
    if self.injuryAlert then
        local badgeSize = math.max(14, math.floor(self.fontHeight * 0.9))
        local bx = self.width - badgeSize - 3
        local by = 3
        Theme.rect(self, bx, by, badgeSize, badgeSize, Theme.status.ERROR)
        Theme.rect(self, bx, by, badgeSize, badgeSize, {r = 1, g = 1, b = 1, a = 0.9}, true)
        Theme.text(self, "+", bx + 3, by - 1, {r = 1, g = 1, b = 1, a = 1})
    end
end

function Avatar3DView:onMouseDown(x, y)
    -- Click to toggle bust / full-body framing
    if x > self.width - 24 and y > self.height - 24 then
        self:toggleBust()
        return true
    end
    return false
end

return Avatar3DView
