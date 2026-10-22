-- Per-instance adapters for the same native action validated by the haul probe.
local Rules = require "EmberRoutesProbe/HaulRules"
local Driver = require "EmberRoutesProbe/Driver"
local Producers = require "EmberRoutesProbe/LaborProducers"
require "TimedActions/ISInventoryTransferAction"
local Transfer = {}

function Transfer.reachable(npc, endpoint)
    local square, current = endpoint.object:getSquare(), npc:getCurrentSquare()
    return square and current and Rules.near(npc:getX(), npc:getY(), npc:getZ(),
        square:getX()+0.5, square:getY()+0.5, square:getZ()) and current:canReachTo(square)
end

function Transfer.move(context, endpoint)
    local requested = false
    return {
        timeout=185000,
        start = function()
            if Transfer.reachable(context.npc, endpoint) then return end
            local square = luautils.getCorrectSquareForWall(context.npc, endpoint.object:getSquare())
            if not square then return "FAILED", "CONTAINER_UNAVAILABLE" end
            local excluded, adjacent = {}, nil
            for _ = 1, 8 do
                local candidate = AdjacentFreeTileFinder.Find(square, context.npc, excluded)
                if not candidate then break end
                local cell = getCell()
                if cell and cell:getGridSquare(candidate:getX(), candidate:getY(), candidate:getZ()) == candidate
                        and candidate:TreatAsSolidFloor() and not candidate:isSolid() and not candidate:isSolidTrans() then
                    adjacent = candidate break
                end
                excluded[#excluded+1] = candidate
            end
            if not adjacent then return "FAILED", "NO_WALKABLE_ADJACENT_TILE" end
            local result = Driver.move({handle=context.npc,id=context.job.npcId},context.actor,
                {x=adjacent:getX()+0.5,y=adjacent:getY()+0.5,z=adjacent:getZ()})
            if not string.find(result, "^MOVE_REQUESTED") then return "FAILED", result end
            requested = true
        end,
        poll = function()
            if not requested then return "PASSED" end
            local result = EmberRoutesProbeJava.motionResult(context.npc)
            if result == "MOVING" then return "WAIT" end
            if result ~= "REACHED" or not Transfer.reachable(context.npc, endpoint) then return "FAILED", "PATH_" .. result end
            return "PASSED"
        end,
    }
end

function Transfer.item(context, item, from, to, endpoint)
    local action, performed, stopped, notified
    local function valid()
        return context.valid() and EmberRoutesProbeJava.carrierActive(context.npc)
            and Transfer.reachable(context.npc, endpoint) and item:getContainer() == from
            and from:getItems():contains(item) and to:hasRoomFor(context.npc, item)
            and context.eligible(item) and Producers.transfer(context,item,from,to)
    end
    return {
        start = function()
            if not valid() then return "FAILED", "TRANSFER_PRECONDITION" end
            if not context.npc:getCharacterActions():isEmpty() then return "FAILED", "NATIVE_ACTION_BUSY" end
            action = ISInventoryTransferAction:new(context.npc, item, from, to, 90)
            action.useProgressBar, action.forceProgressBar = false, false
            local nativeValid, nativePerform, nativeStop = action.isValid, action.perform, action.stop
            local nativeAnim, nativeUpdate = action.startActionAnim, action.update
            action.isValid = function(self) return valid() and nativeValid(self) end
            action.startActionAnim = function(self) nativeAnim(self) self.selectedContainer = nil end
            action.update = function(self) nativeUpdate(self) self.character:faceThisObject(endpoint.object) end
            action.perform = function(self)
                if not self:isValid() then self:stop() return end
                nativePerform(self)
                performed = true
                if context.transferred then context.transferred(item, from, to) end
            end
            action.stop = function(self) nativeStop(self) stopped = true end
            ISTimedActionQueue.add(action)
        end,
        poll = function()
            if ISTimedActionQueue.hasAction(action) then return "WAIT" end
            if not performed or stopped then return "FAILED", "NATIVE_TRANSFER_STOPPED" end
            if item:getContainer() ~= to or not to:getItems():contains(item) or from:getItems():contains(item) then
                return "FAILED", "INSTANCE_TRANSFER_MISMATCH"
            end
            if not notified then
                local registry=require "EmberRoutesProbe/ContainerRegistry"
                registry.inventoryChanged(from) registry.inventoryChanged(to) notified=true
            end
            return "PASSED"
        end,
    }
end

return Transfer
