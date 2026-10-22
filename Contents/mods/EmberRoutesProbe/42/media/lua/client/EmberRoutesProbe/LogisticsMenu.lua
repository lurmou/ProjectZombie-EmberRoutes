local Service
local function service()
    if not Service then Service=require "EmberRoutesProbe/LogisticsService" end
    return Service
end
local Store=require "EmberRoutesProbe/LogisticsStore"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Driver=require "EmberRoutesProbe/Driver"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Menu={}
function Menu.initialize() service() end
local text=require("EmberRoutesProbe/LogisticsText").get
function Menu.command(actor,command,id,quiet)
    local entry,reason=Ledger.view(actor,id)
    if not entry then if not quiet then actor:Say(text(reason)) end return reason end
    local Service=service()
    local result
    if command=="start" then result=Service.start(actor,id)
    elseif command=="stop" then result=Service.stop(actor,id)
    elseif command=="addAll" then result=Service.addNearby(actor,id)
    elseif command=="intake" or command=="tidy" then
        local updated,why=Store.mode(actor,id,command) Service.invalidate(id)
        result=updated and "MODE_CONFIGURED" or why
    elseif command=="refresh" then Service.invalidate() result="RESCAN_REQUESTED"
    elseif command=="report" then
        Service.report(id)
        local snapshot=Service.status(id)
        local lines={text(snapshot.reason)}
        for _,worker in ipairs(snapshot.workers) do
            lines[#lines+1]=string.sub(worker.id,1,8)..": "..text(worker.reason)
        end
        if not quiet then actor:Say(table.concat(lines,"\n")) end return snapshot.reason
    elseif command=="add" or command=="remove" then
        local npcId=Driver.selected(actor) local binding=Driver.bindId(actor,npcId)
        if command=="remove" then result=Service.removeWorker(actor,id,npcId)
        elseif not binding or not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then result="NPC_OUTSIDE_SETTLEMENT"
        else
            local updated,why=Store.worker(actor,id,npcId,true)
            if updated then Service.invalidate(id) result="WORKERS_ADDED" else result=why end
        end
    end
    if not quiet then actor:Say(text("result").." "..text(result or "ERROR")) end
    return result or "ERROR"
end
function Menu.open(actor,id)
    local panel,reason=require("EmberRoutesProbe/LogisticsDashboard").open(actor,id)
    if not panel then actor:Say(text(reason)) end
end
function Menu.fill(actor,parent,entry)
    if not Geometry.inside(entry,actor:getX(),actor:getY()) then return end
    parent:addOption(text("page").." - "..entry.name,actor,Menu.open,entry.id)
end
function Menu.role(actor,role,object,container)
    local result=Registry.configureLogistics(actor,object,container,role)
    actor:Say(text("result").." "..text(result))
end
function Menu.container(actor,parent,object,container)
    local option=parent:addOption(text("role"),nil,nil)
    local menu=ISContextMenu:getNew(parent) parent:addSubMenu(option,menu)
    local configured=Registry.metadata(object,container)
    local selected=configured and Registry.logistics({object=object,container=container})
    local hint=menu:addOption(text(configured and "ROLE_HINT" or "UNTAGGED_HINT"),nil,nil)
    hint.notAvailable=true
    for _,role in ipairs({"INPUT","STORAGE","EXCLUDED"}) do
        local choice=menu:addOption(text(role),actor,Menu.role,role,object,container)
        menu:setOptionChecked(choice,role==selected)
    end
end
return Menu
