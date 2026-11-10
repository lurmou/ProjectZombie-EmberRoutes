-- Per-instance adapters for native BaseAction transfer.
local Rules = require "EmberRoutesProbe/Hauling/HaulRules"
local Driver = require "EmberRoutesProbe/Runtime/Driver"
local Producers = require "EmberRoutesProbe/Work/LaborProducers"
local Constants = require 'EmberRoutesProbe/Kernel/Constants'
local TransferDuration = require "EmberRoutesProbe/Work/TransferDuration"
local Transfer = {}

function Transfer.reachable(npc, endpoint)
    local square=endpoint.playerId and endpoint.object:getCurrentSquare() or endpoint.object:getSquare()
    local current=npc:getCurrentSquare()
    return square and current and Rules.near(npc:getX(), npc:getY(), npc:getZ(),
        square:getX()+0.5, square:getY()+0.5, square:getZ()) and current:canReachTo(square)
end

function Transfer.prepareMove(context,endpoint,excluded)
    local square=luautils.getCorrectSquareForWall(context.npc,endpoint.object:getSquare())
    if not square then return nil,'CONTAINER_UNAVAILABLE' end
    excluded=excluded or {}
    if EmberRoutesProbeJava and EmberRoutesProbeJava.resolveInteractionTile then
        local fast=EmberRoutesProbeJava.resolveInteractionTile(square,context.npc,excluded)
        if fast and fast.square then
            return {object=endpoint.object,square=fast.square,x=fast.x,y=fast.y,z=fast.z,at=getTimestampMs()}
        end
    end
    for _=1,8 do
        if #excluded>=8 then break end
        local candidate=AdjacentFreeTileFinder.Find(square,context.npc,excluded)
        if not candidate then break end
        local cell=getCell()
        if cell and cell:getGridSquare(candidate:getX(),candidate:getY(),candidate:getZ())==candidate
            and candidate:TreatAsSolidFloor() and not candidate:isSolid() and not candidate:isSolidTrans() then
            return {object=endpoint.object,square=candidate,x=candidate:getX()+0.5,y=candidate:getY()+0.5,
                z=candidate:getZ(),at=getTimestampMs()}
        end
        excluded[#excluded+1]=candidate
    end
    return nil,'NO_WALKABLE_ADJACENT_TILE'
end

local function preparedValid(endpoint,p)
    if not p or p.object~=endpoint.object or getTimestampMs()-p.at>2000 then return false end
    local s=p.square local cell=getCell()
    return cell and cell:getGridSquare(s:getX(),s:getY(),s:getZ())==s
        and s:TreatAsSolidFloor() and not s:isSolid() and not s:isSolidTrans()
end

function Transfer.move(context, endpoint,prepared)
    local requested = false
    local excluded,point,attempts={},nil,0
    local function request(candidate)
        if attempts>=8 then return 'FAILED','NO_REACHABLE_ADJACENT_TILE' end
        local why
        if not preparedValid(endpoint,candidate) then candidate,why=Transfer.prepareMove(context,endpoint,excluded) end
        if not candidate then return 'FAILED',why end
        point=candidate attempts=attempts+1
        local result=Driver.move({handle=context.npc,id=context.job.npcId},context.actor,
            {x=point.x,y=point.y,z=point.z},context.body)
        if not string.find(result,'^MOVE_REQUESTED') then return 'FAILED',result end
        requested=true
    end
    return {
        timeout=Constants.Timeout.MOVE_MS,
        start = function()
            if Transfer.reachable(context.npc, endpoint) then return end
            local targetSq = endpoint.playerId and endpoint.object:getCurrentSquare() or (endpoint.object and endpoint.object:getSquare())
            local currentSq = context.npc and context.npc.getCurrentSquare and context.npc:getCurrentSquare()
            if currentSq and targetSq and EmberRoutesProbeJava and EmberRoutesProbeJava.macroReachable then
                if not EmberRoutesProbeJava.macroReachable(currentSq, targetSq) then
                    return 'FAILED', 'MACRO_UNREACHABLE'
                end
            end
            return request(prepared)
        end,
        poll = function()
            if not requested then return "PASSED" end
            local result = EmberRoutesProbeJava.motionResult(context.npc)
            if result == "MOVING" then return "WAIT" end
            if require('EmberRoutesProbe/Runtime/Driver').suspended(context.npc) then return "WAIT" end
            if result=='REACHED' and Transfer.reachable(context.npc,endpoint) then return 'PASSED' end
            if result=='FAILED' or result=='PATH_ENDED' or result=='REACHED' then
                excluded[#excluded+1]=point.square
                local state,why=request()
                if state=='FAILED' then return state,why end
                return 'WAIT'
            end
            return 'FAILED','PATH_'..result
        end,
    }
end

function Transfer.item(context, item, from, to, endpoint)
    local started, performed, stopped, notified, lastCheck, diagnosed
    local progressAt = getTimestampMs()
    local function notify()
        local registry = require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
        registry.inventoryChanged(from) registry.inventoryChanged(to)
        notified = true
    end

    local function valid()
        local own = context.npc:getInventory()
        local ownTransfer = not endpoint and (from==own or from.isInCharacterInventory and from:isInCharacterInventory(context.npc))
            and (to==own or to.isInCharacterInventory and to:isInCharacterInventory(context.npc))
        if not context.valid() then lastCheck='CONTEXT_INVALID'
        elseif not EmberRoutesProbeJava.carrierActive(context.npc) then lastCheck='CARRIER_INACTIVE'
        elseif not (ownTransfer or endpoint and Transfer.reachable(context.npc, endpoint)) then lastCheck='NOT_REACHABLE'
        elseif item:getContainer() ~= from then lastCheck='ITEM_MOVED'
        elseif not from:getItems():contains(item) then lastCheck='ITEM_ABSENT_SOURCE'
        elseif not to:hasRoomFor(endpoint and endpoint.playerId and endpoint.object or context.npc, item) then lastCheck='DESTINATION_FULL'
        elseif not context.eligible(item) then lastCheck='ELIGIBILITY_REJECTED'
        elseif not Producers.transfer(context,item,from,to) then lastCheck='PRODUCER_REJECTED'
        else return true end
        return false
    end

    local function diagnose(what)
        local job = context.job
        require "EmberRoutesProbe/Kernel/Log".write("TRANSFER",
            "STOP npc="..(job and job.npcId or "?").." job="..(job and job.id or "?")
            .." item="..tostring(item and item.getID and item:getID() or "?")
            .." cause="..what.." check="..tostring(lastCheck)
            .." from="..tostring(from and from.getType and from:getType() or "?")
            .." to="..tostring(to and to.getType and to:getType() or "?")
            .." source="..tostring(job and job.source or "?")
            .." destination="..tostring(job and job.destination or "?")
            .." performed="..tostring(performed==true).." stopped="..tostring(stopped==true))
    end

    local function startPresentation()
        if context.body and not context.body.current() then return 'FAILED','CONTROL_REQUIRED' end
        if not valid() then return "FAILED", "TRANSFER_PRECONDITION" end
        if endpoint and endpoint.object and context.npc.faceThisObject then
            context.npc:faceThisObject(endpoint.object)
        end
        -- Presentation only: the physical transfer is done by Lua in poll().
        -- Duration is the vanilla transfer formula (TransferDuration),
        -- replacing the old weight-banded 15..60 estimate.
        local duration = TransferDuration.forTransfer(context.npc, item, from, to)
        if EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionStart then
            EmberRoutesProbeJava.nativeActionStart(context.npc, "Loot", duration, true)
        end
        started = true
    end

    local function stopPresentation()
        if EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionStop then
            EmberRoutesProbeJava.nativeActionStop(context.npc)
        end
    end

    return {
        progressAt = function() return progressAt end,
        start = function()
            local state, why = startPresentation()
            if state == 'FAILED' then return state, why end
        end,
        cancel = function()
            stopped = true
            stopPresentation()
        end,
        poll = function()
            if stopped then return "FAILED", "NATIVE_TRANSFER_STOPPED" end
            if not started then return "FAILED", "NOT_STARTED" end
            if EmberRoutesProbeJava and EmberRoutesProbeJava.nativeActionFinished then
                if not EmberRoutesProbeJava.nativeActionFinished(context.npc) then
                    return "WAIT"
                end
            end

            -- Presentation complete; check validity before physical mutation
            if not valid() then
                stopped = true
                stopPresentation()
                if not diagnosed then diagnosed = true diagnose('PRECONDITION') end
                return "FAILED", "NATIVE_TRANSFER_STOPPED"
            end

            -- Atomic physical transfer
            if from.DoRemoveItem then from:DoRemoveItem(item)
            elseif from.removeItem_NoBroadcast then from:removeItem_NoBroadcast(item)
            elseif from.transferItem then from:transferItem(item) end

            if to.AddItem then to:AddItem(item) end

            local moved = item:getContainer() == to
                and (not to.getItems or to:getItems():contains(item))
                and (not from.getItems or not from:getItems():contains(item))

            if not moved then
                stopped = true
                stopPresentation()
                return "FAILED", "INSTANCE_TRANSFER_MISMATCH"
            end

            performed = true
            progressAt = getTimestampMs()

            local acknowledged = not context.transferred or context.transferred(item, from, to)
            if acknowledged == false then error('TRANSFER_RECEIPT_FAILED') end
            if not notified then notify() end

            -- Check continuous transfer continuation
            if context.nextTransfer then
                local nextPart = context.nextTransfer()
                if nextPart then
                    if nextPart.from ~= from or nextPart.to ~= to or nextPart.endpoint ~= endpoint then
                        error('TRANSFER_CONTINUATION_ENDPOINT_CHANGED')
                    end
                    context, item = nextPart.context, nextPart.item
                    started, performed, notified, lastCheck = false, false, false, nil
                    local state, why = startPresentation()
                    if state == 'FAILED' then return state, why end
                    return "WAIT"
                end
            end

            stopPresentation()
            return "PASSED"
        end,
    }
end

return Transfer
