local Config=require "EmberRoutesProbe/Warehouse/ContainerConfiguration"
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Panel=require "EmberRoutesProbe/UI/StorageFilterPanel"
local Text=require "EmberRoutesProbe/UI/Text"
local PlayerStashRoutine=require "EmberRoutesProbe/Warehouse/PlayerStashRoutine"
local Ledger=require "EmberRoutesProbe/Settlement/SettlementLedger"
local Geometry=require "EmberRoutesProbe/Settlement/SettlementGeometry"

local Menu={}

function Menu.copy(actor,object,container)
    local _,reason=Config.copy(actor,object,container)
    actor:Say(Config.text(reason))
end

function Menu.paste(actor,object,container)
    local ok,reason=Config.validate(actor,object,container)
    if not ok then actor:Say(Config.text(reason)) return end
    local rules,why=Config.paste(actor,Registry.filter(object,container))
    if not rules then actor:Say(Config.text(why)) return end
    Panel.open(actor,object,container,rules)
end

function Menu.getNearbyStorage(actor, maxDist)
    local list = {}
    local data = Registry.data()
    local px = actor.getX and actor:getX() or 0
    local py = actor.getY and actor:getY() or 0
    local pz = actor.getZ and actor:getZ() or 0

    local currentSettlement = nil
    local settlements = Ledger.at(px, py)
    if settlements and #settlements > 0 then
        currentSettlement = settlements[1]
    end

    local dMaxSq = (maxDist or PlayerStashRoutine.DEFAULT_MAX_DISTANCE) * (maxDist or PlayerStashRoutine.DEFAULT_MAX_DISTANCE)

    for id, rec in pairs(data.containers or {}) do
        if rec.z == pz then
            local isCandidate = false
            if currentSettlement then
                if Geometry.inside(currentSettlement, rec.x, rec.y) then
                    isCandidate = true
                end
            else
                local dx, dy = rec.x - px, rec.y - py
                if (dx * dx + dy * dy) <= dMaxSq then
                    isCandidate = true
                end
            end

            if isCandidate then
                local ep = Registry.resolve(id)
                if ep and ep.object and ep.container then
                    list[#list + 1] = {
                        object = ep.object,
                        container = ep.container,
                        square = ep.object:getSquare(),
                        filter = Registry.filter(ep.object, ep.container)
                    }
                end
            end
        end
    end
    return list
end

function Menu.stashRoutine(actor)
    local px = actor.getX and actor:getX() or 0
    local py = actor.getY and actor:getY() or 0
    local settlements = Ledger.at(px, py)
    local inSettlement = settlements and #settlements > 0

    local containers = Menu.getNearbyStorage(actor, inSettlement and PlayerStashRoutine.UNLIMITED_DISTANCE or PlayerStashRoutine.DEFAULT_MAX_DISTANCE)
    local plan, reason = PlayerStashRoutine.plan(actor, containers, {
        unlimitedDistance = inSettlement,
        maxDistance = inSettlement and PlayerStashRoutine.UNLIMITED_DISTANCE or PlayerStashRoutine.DEFAULT_MAX_DISTANCE
    })
    if not plan then
        local errKey = "IGUI_EmberRoutesProbe_Stash_" .. tostring(reason)
        local errText = getTextOrNull(errKey) or reason
        actor:Say(errText)
        return
    end
    local ok = PlayerStashRoutine.execute(actor, plan)
    if ok then
        actor:Say(getText("IGUI_EmberRoutesProbe_Stash_started") .. " (" .. plan.totalItems .. ")")
    end
end

function Menu.fill(actor,parent,object,container)
    local config=Registry.filter(object,container)
    parent:addOption(getText("IGUI_EmberRoutesProbe_Filter_title"),actor,Panel.open,object,container)
    parent:addOption(getText("IGUI_EmberRoutesProbe_Stash_action"),actor,Menu.stashRoutine)
    if config then
        parent:addOption(Config.text("configCopyRules"),actor,Menu.copy,object,container)
    end
    if Config.hasClipboard(actor) then
        parent:addOption(Config.text("configPasteEdit"),actor,Menu.paste,object,container)
    end
end

return Menu
