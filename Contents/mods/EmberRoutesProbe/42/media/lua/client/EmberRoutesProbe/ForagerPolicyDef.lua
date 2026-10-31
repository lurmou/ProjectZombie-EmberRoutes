--[[
  EmberRoutesProbe / ForagerPolicyDef.lua
  搜寻/觅食工自治规程定义
  声明据点级觅食偏好、安全搜寻半径、仓储上限与生态维护
--]]

local Registry = require 'EmberRoutesProbe/JobPolicyRegistry'

local ForagerPolicyDef = {
    category = 'forager',
    order = 25,
    titleKey = 'IGUI_EmberRoutesProbe_Policy_forager_title',
    descKey = 'IGUI_EmberRoutesProbe_Policy_forager_desc',
}

function ForagerPolicyDef.getDefaults()
    return {
        searchFocus = 'balanced',
        searchRange = 'surrounding',
        forageZoneId = '',
        maxStones = 40,
        maxHerbs = 30,
        autoRefillZone = true,
    }
end

function ForagerPolicyDef.getFields(settlementId)
    return {
        {
            key = 'searchFocus',
            editor = 'enum_tabs',
            label = 'IGUI_EmberRoutesProbe_Policy_forager_focus',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_forager_focus_tip',
            options = {
                { value = 'balanced', label = 'IGUI_EmberRoutesProbe_Policy_forager_focus_balanced' },
                { value = 'medicinal', label = 'IGUI_EmberRoutesProbe_Policy_forager_focus_medicinal' },
                { value = 'food', label = 'IGUI_EmberRoutesProbe_Policy_forager_focus_food' },
                { value = 'materials', label = 'IGUI_EmberRoutesProbe_Policy_forager_focus_materials' },
                { value = 'insects', label = 'IGUI_EmberRoutesProbe_Policy_forager_focus_insects' },
            },
        },
        {
            key = 'searchRange',
            editor = 'enum_tabs',
            label = 'IGUI_EmberRoutesProbe_Policy_forager_range',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_forager_range_tip',
            options = {
                { value = 'settlement_only', label = 'IGUI_EmberRoutesProbe_Policy_forager_range_inner' },
                { value = 'surrounding', label = 'IGUI_EmberRoutesProbe_Policy_forager_range_surrounding' },
                { value = 'assigned_zone', label = 'IGUI_EmberRoutesProbe_Policy_forager_range_assigned' },
            },
        },
        {
            key = 'forageZoneId',
            editor = 'zone_dropdown',
            label = 'IGUI_EmberRoutesProbe_Policy_forager_zone',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_forager_zone_tip',
        },
        {
            key = 'maxStones',
            editor = 'slider',
            label = 'IGUI_EmberRoutesProbe_Policy_forager_maxStones',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_forager_maxStones_tip',
            min = 0,
            max = 100,
            step = 5,
            unit = 'items',
        },
        {
            key = 'maxHerbs',
            editor = 'slider',
            label = 'IGUI_EmberRoutesProbe_Policy_forager_maxHerbs',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_forager_maxHerbs_tip',
            min = 0,
            max = 100,
            step = 5,
            unit = 'items',
        },
        {
            key = 'autoRefillZone',
            editor = 'toggle',
            label = 'IGUI_EmberRoutesProbe_Policy_forager_autoRefill',
            tooltip = 'IGUI_EmberRoutesProbe_Policy_forager_autoRefill_tip',
        },
    }
end

function ForagerPolicyDef.validate(draft)
    if type(draft) ~= 'table' then return false, 'POLICY_INVALID_TYPE' end
    if draft.maxStones ~= nil and (type(draft.maxStones) ~= 'number' or draft.maxStones < 0 or draft.maxStones > 500) then
        return false, 'INVALID_MAX_STONES'
    end
    if draft.maxHerbs ~= nil and (type(draft.maxHerbs) ~= 'number' or draft.maxHerbs < 0 or draft.maxHerbs > 500) then
        return false, 'INVALID_MAX_HERBS'
    end
    return true
end

Registry.register(ForagerPolicyDef)

return ForagerPolicyDef
