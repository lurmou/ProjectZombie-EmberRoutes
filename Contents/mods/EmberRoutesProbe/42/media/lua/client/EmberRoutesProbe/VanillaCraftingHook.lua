-- Hook vanilla B42 Crafting UI (ISWidgetHandCraftControl) to inject "Delegate to Settlement" button.
-- Pure non-invasive extension: preserves vanilla crafting actions 100%.

local Ledger = require 'EmberRoutesProbe/SettlementLedger'
local Dashboard = require 'EmberRoutesProbe/SettlementDashboard'

local Hook = {}

local function text(key, ...)
    return getText('IGUI_EmberRoutesProbe_Vanilla_' .. key, ...)
end

local function onDelegateClick(widget)
    local logic = widget.logic
    local recipe = logic and logic:getRecipe()
    if not recipe then return end

    local recipeId = recipe:getName()
    if not recipeId or recipeId == '' then
        recipeId = recipe:getOriginalname()
    end
    if not recipeId or recipeId == '' then return end

    local player = widget.player or getSpecificPlayer(0) or getPlayer()
    if not player then return end

    -- 1. Locate current settlement at player coordinates
    local settlements = Ledger.at(player:getX(), player:getY())
    local entry = settlements and settlements[1]
    if not entry then
        player:Say(text('noSettlement'))
        return
    end

    -- 2. Open PublicOrderDialog with selected recipe context
    local panel = Dashboard.open(player, entry.id, 'warehouse')
    if panel then
        panel:openPublicOrder({
            recipeId = recipeId,
            recipeName = recipe:getTranslationName()
        })
    end
end

function Hook.install()
    if not ISWidgetHandCraftControl then return end
    if Hook._installed then return end
    Hook._installed = true

    -- Hook createChildren to add the delegate button
    local old_createChildren = ISWidgetHandCraftControl.createChildren
    function ISWidgetHandCraftControl:createChildren()
        old_createChildren(self)

        local btnH = getTextManager():getFontHeight(UIFont.Small) + 6
        self.buttonEmberDelegate = ISButton:new(0, 0, 0, btnH, text('delegateButton'), self, onDelegateClick)
        self.buttonEmberDelegate.font = UIFont.Small
        self.buttonEmberDelegate.enable = true
        self.buttonEmberDelegate:initialise()
        self.buttonEmberDelegate:instantiate()
        self:addChild(self.buttonEmberDelegate)
    end

    -- Hook calculateLayout to position the delegate button alongside the craft button
    local old_calculateLayout = ISWidgetHandCraftControl.calculateLayout
    function ISWidgetHandCraftControl:calculateLayout(_preferredWidth, _preferredHeight)
        old_calculateLayout(self, _preferredWidth, _preferredHeight)

        if self.buttonCraft and self.buttonEmberDelegate then
            local origW = self.buttonCraft:getWidth()
            local spacing = 5
            local halfW = math.max(60, math.floor((origW - spacing) / 2))

            self.buttonCraft:setWidth(halfW)

            self.buttonEmberDelegate:setX(self.buttonCraft:getX() + halfW + spacing)
            self.buttonEmberDelegate:setY(self.buttonCraft:getY())
            self.buttonEmberDelegate:setWidth(halfW)
            self.buttonEmberDelegate:setHeight(self.buttonCraft:getHeight())
            self.buttonEmberDelegate:setVisible(self.buttonCraft:isVisible())
        end
    end

    -- Hook onInputsChanged / onRecipeChanged to keep delegate button available regardless of player inventory
    local old_onInputsChanged = ISWidgetHandCraftControl.onInputsChanged
    if old_onInputsChanged then
        function ISWidgetHandCraftControl:onInputsChanged()
            old_onInputsChanged(self)
            if self.buttonEmberDelegate and self.logic then
                local recipe = self.logic:getRecipe()
                -- Delegate button is enabled if recipe exists and player knows it
                local player = self.player or getSpecificPlayer(0) or getPlayer()
                local canDelegate = recipe ~= nil and (not player or player:isRecipeKnown(recipe, true))
                self.buttonEmberDelegate.enable = canDelegate
            end
        end
    end
end

-- Auto-register on game boot
Events.OnGameStart.Add(Hook.install)

return Hook
