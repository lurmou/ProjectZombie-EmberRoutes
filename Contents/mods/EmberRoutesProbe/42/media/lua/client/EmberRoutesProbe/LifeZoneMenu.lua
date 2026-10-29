local Zones=require 'EmberRoutesProbe/SettlementZones'
local Selector=require 'EmberRoutesProbe/UI/LifeZoneSelector'
local Rules=require 'EmberRoutesProbe/UI/LifeZoneRules'
local Menu={}
local function text(key) return getText('IGUI_EmberRoutesProbe_LifeZone_'..key) end
local function notify(actor,why) actor:Say(text(why)) end
local function create(actor,scope) Selector.open(actor,scope) end
local function redraw(actor,id)
    local zone,why=Zones.get(id)
    if zone then Selector.open(actor,zone.settlementId,zone) else notify(actor,why) end
end
local function edit(actor,id)
    local zone,why=Zones.get(id)
    if zone then Rules.open(actor,zone) else notify(actor,why) end
end
local function toggle(actor,id)
    local zone,why=Zones.get(id)
    if not zone then notify(actor,why) return end
    zone.enabled=not zone.enabled
    local result,reason=Zones.save(actor,zone.settlementId,id,zone.revision,zone)
    if not result then notify(actor,reason) end
end
local function remove(actor,id)
    local zone,why=Zones.get(id)
    if not zone then notify(actor,why) return end
    local ok,reason=Zones.remove(actor,zone.settlementId,id,zone.revision)
    if not ok then notify(actor,reason) end
end
function Menu.fill(actor,menu,entry)
    local option=menu:addOption(text('menu'),nil,nil)
    local child=ISContextMenu:getNew(menu) menu:addSubMenu(option,child)
    child:addOption(text('create'),actor,create,entry.id)
    local zones,why=Zones.list(entry.id)
    if not zones then child:addOption(text(why),nil,nil) return end
    for _,zone in ipairs(zones) do
        local label=zone.name..' · '..getText('IGUI_EmberRoutesProbe_LifeZone_floor',zone.area.z)
        if not zone.enabled then label=label..' ('..text('disabled')..')' end
        local opt=child:addOption(label,nil,nil)
        local actions=ISContextMenu:getNew(child) child:addSubMenu(opt,actions)
        actions:addOption(text('rules'),actor,edit,zone.id)
        actions:addOption(text('redraw'),actor,redraw,zone.id)
        actions:addOption(text(zone.enabled and 'disable' or 'enable'),actor,toggle,zone.id)
        actions:addOption(text('remove'),actor,remove,zone.id)
    end
end
return Menu
