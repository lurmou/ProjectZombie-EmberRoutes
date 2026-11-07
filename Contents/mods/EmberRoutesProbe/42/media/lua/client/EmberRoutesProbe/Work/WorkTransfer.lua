-- Per-instance adapters for the same native action validated by the haul probe.
local Rules = require "EmberRoutesProbe/Hauling/HaulRules"
local Driver = require "EmberRoutesProbe/Runtime/Driver"
local Producers = require "EmberRoutesProbe/Work/LaborProducers"
require "TimedActions/ISInventoryTransferAction"
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
        timeout=185000,
        start = function()
            if Transfer.reachable(context.npc, endpoint) then return end
            return request(prepared)
        end,
        poll = function()
            if not requested then return "PASSED" end
            local result = EmberRoutesProbeJava.motionResult(context.npc)
            if result == "MOVING" then return "WAIT" end
            if require('EmberRoutesProbe/Runtime/Driver').suspended(context.npc) then return "WAIT" end
            if result=='REACHED' and Transfer.reachable(context.npc,endpoint) then return 'PASSED' end
            -- A locally free neighbour can still be unreachable from the worker.
            -- Keep the same owner; let vanilla choose another, excluding failed tiles.
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
    local action, performed, stopped, notified,attempted,lastCheck,diagnosed
    local progressAt=getTimestampMs()
    local function notify()
	local registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
	registry.inventoryChanged(from) registry.inventoryChanged(to)
	notified=true
    end
    -- Same conjunction and order as before; each clause records its own bucket
    -- so a mid-action stop can name the failing precondition in diagnostics.
    local function valid()
        local own=context.npc:getInventory()
        local ownTransfer=not endpoint and (from==own or from.isInCharacterInventory and from:isInCharacterInventory(context.npc))
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
        local job=context.job
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
    return {
	progressAt=function() return progressAt end,
        start = function()
            if not valid() then return "FAILED", "TRANSFER_PRECONDITION" end
            if not context.npc:getCharacterActions():isEmpty() then return "FAILED", "NATIVE_ACTION_BUSY" end
            action = ISInventoryTransferAction:new(context.npc, item, from, to, 90)
            action.useProgressBar, action.forceProgressBar = false, false
            local nativeValid, nativePerform, nativeStop = action.isValid, action.perform, action.stop
            local nativeAnim, nativeUpdate = action.startActionAnim, action.update
	    local nativeTransfer=action.transferItem
	    local continuous=context.nextTransfer and nativeTransfer and action.queueList~=nil
	    if continuous then
		-- Own this action's internal queue. Never absorb another owner's
		-- queued action (vanilla merging wipes that action and its hooks).
		action.canMergeAction=function() return false end
		action.transferItem=function(self,value)
		    nativeTransfer(self,value)
		    local moved=value:getContainer()==to and to:getItems():contains(value)
			and not from:getItems():contains(value)
		    local acknowledged=not context.transferred or context.transferred(value,from,to)
		    if acknowledged==false then error('TRANSFER_RECEIPT_FAILED') end
		    performed=moved progressAt=getTimestampMs()
		    if moved then notify() end
		    local nextPart=moved and context.nextTransfer and context.nextTransfer() or nil
		    if not nextPart then return end
		    if nextPart.from~=from or nextPart.to~=to or nextPart.endpoint~=endpoint then
			error('TRANSFER_CONTINUATION_ENDPOINT_CHANGED')
		    end
		    -- Vanilla perform() sees this entry before it decides whether
		    -- to end the animation. Only its next item has an active intent.
		    local seed=ISInventoryTransferAction:new(context.npc,nextPart.item,from,to,90)
		    self.queueList[#self.queueList+1]=seed.queueList[1]
		    context,item=nextPart.context,nextPart.item
		    performed,notified,lastCheck=false,false,nil
		end
	    end
            action.isValid = function(self)
                if not valid() then return false end
                local ok = nativeValid(self)
                if not ok then lastCheck='NATIVE_ISVALID' end
                return ok
            end
            action.startActionAnim = function(self)
                if context.body and not context.body.current() then return end
                nativeAnim(self) self.selectedContainer = nil
            end
            action.update = function(self)
                if context.body and not context.body.current() then return end
                nativeUpdate(self)
                if endpoint then self.character:faceThisObject(endpoint.object) end
            end
            action.perform = function(self)
                if context.body and attempted then return end
                attempted=true
                if not self:isValid() then self:stop() return end
                nativePerform(self)
		if continuous then
		    if #self.queueList>0 then attempted=false end
		else
		    performed = true progressAt=getTimestampMs()
		    if context.transferred and context.transferred(item,from,to)==false then error('TRANSFER_RECEIPT_FAILED') end
		end
            end
            action.stop = function(self)
                if context.body and (stopped or performed) then return end
                stopped = true
                if not context.body or context.body.retained() then nativeStop(self) end
            end
            if context.body then
                if not context.body.add(action) then return 'FAILED','CONTROL_REQUIRED' end
            else ISTimedActionQueue.add(action) end
        end,
        poll = function()
            if ISTimedActionQueue.hasAction(action) then return "WAIT" end
            if not performed or stopped then
                if not diagnosed then
                    diagnosed=true
                    diagnose(lastCheck and 'PRECONDITION' or stopped and 'EXTERNAL_STOP' or 'UNPERFORMED')
                end
                return "FAILED", "NATIVE_TRANSFER_STOPPED"
            end
            if item:getContainer() ~= to or not to:getItems():contains(item) or from:getItems():contains(item) then
                return "FAILED", "INSTANCE_TRANSFER_MISMATCH"
            end
            if not notified then
		notify()
            end
            return "PASSED"
        end,
    }
end

return Transfer
