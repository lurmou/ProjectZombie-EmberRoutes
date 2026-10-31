-- Cooking Policy Definition.
-- Declares settlement-level directives for cooking operations:
-- Kitchen zone binding, spoilage strategies, allowed ingredient categories,
-- and batch cooking preferences.
local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'

local CookingPolicyDef = {
    category = 'cooking',
    order = 20,
    titleKey = 'IGUI_EmberRoutesProbe_Policy_cook_title',
    descKey = 'IGUI_EmberRoutesProbe_Policy_cook_desc',
}

function CookingPolicyDef.getDefaults()
    return {
        kitchenZoneId = '',
        spoilageStrategy = 'EXPIRE_SOON_FIRST',
        allowedFoodCategories = {
            Vegetables = true,
            Meat = true,
            Fruits = true,
            Canned = false, -- Default save canned food for emergencies
            Dairy = true,
            Spices = true,
        },
        allowRotten = false,
        batchMeals = true,
    }
end

function CookingPolicyDef.getFields(settlementId)
    return {
        {
            key = 'kitchenZoneId',
            editor = 'zone_dropdown',
            label = 'IGUI_EmberRoutesProbe_Policy_cook_kitchenZone',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_cook_kitchenZone_tip',
        },
        {
            key = 'spoilageStrategy',
            editor = 'enum_tabs',
            label = 'IGUI_EmberRoutesProbe_Policy_cook_spoilageStrategy',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_cook_spoilageStrategy_tip',
            options = {
                { value = 'EXPIRE_SOON_FIRST', label = 'IGUI_EmberRoutesProbe_Policy_cook_strat_expire' },
                { value = 'FRESH_FIRST',       label = 'IGUI_EmberRoutesProbe_Policy_cook_strat_fresh' },
                { value = 'ANY_SAFE',          label = 'IGUI_EmberRoutesProbe_Policy_cook_strat_any' },
            }
        },
        {
            key = 'allowedFoodCategories',
            editor = 'tag_chips',
            label = 'IGUI_EmberRoutesProbe_Policy_cook_categories',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_cook_categories_tip',
            tags = {
                { id = 'Vegetables', label = 'IGUI_EmberRoutesProbe_Food_Vegetables' },
                { id = 'Meat',       label = 'IGUI_EmberRoutesProbe_Food_Meat' },
                { id = 'Fruits',     label = 'IGUI_EmberRoutesProbe_Food_Fruits' },
                { id = 'Canned',     label = 'IGUI_EmberRoutesProbe_Food_Canned' },
                { id = 'Dairy',      label = 'IGUI_EmberRoutesProbe_Food_Dairy' },
                { id = 'Spices',     label = 'IGUI_EmberRoutesProbe_Food_Spices' },
            }
        },
        {
            key = 'allowRotten',
            editor = 'toggle',
            label = 'IGUI_EmberRoutesProbe_Policy_cook_allowRotten',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_cook_allowRotten_tip',
        },
        {
            key = 'batchMeals',
            editor = 'toggle',
            label = 'IGUI_EmberRoutesProbe_Policy_cook_batchMeals',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_cook_batchMeals_tip',
        },
    }
end

function CookingPolicyDef.validate(draft)
    if draft.spoilageStrategy ~= nil and type(draft.spoilageStrategy) ~= 'string' then
        return false, 'INVALID_STRATEGY'
    end
    if draft.allowedFoodCategories ~= nil and type(draft.allowedFoodCategories) ~= 'table' then
        return false, 'INVALID_CATEGORIES'
    end
    return true
end

-- Auto-register upon loading
Registry.register(CookingPolicyDef)

return CookingPolicyDef
