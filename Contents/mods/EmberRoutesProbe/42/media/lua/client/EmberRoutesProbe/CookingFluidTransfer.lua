-- Native item-to-item pouring. A progressive operation owns both originals in
-- the existing Job; stop observes partial transfer and never restores liquids.
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Store=require 'EmberRoutesProbe/LaborStore'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local M={}
function M.new(c,sequence,source,target,amount)
    require 'Fluids/ISFluidContainer'
    require 'Fluids/ISFluidUtil'
    require 'Fluids/ISFluidTransferAction'
    if not Context.active(c) or source==target or not Policy.finite(amount) or amount<=0 then return nil,'FLUID_INTENT_INVALID' end
    local sourceId,targetId=source:getID(),target:getID()
    local root=c.npc:getInventory()
    local function facts()
        for _,item in ipairs({source,target}) do
            local id=item:getID() local a=Inventory.asset(c.job,id)
            if not a or a.custody~='HELD' or a.fullType~=item:getFullType()
                or not Store.validCooking(c.job,c.token,'item:'..id) or not Inventory.contains(item,root,id) then return nil end
        end
        local a=Fluids.read(source:getFluidContainer()) local b=Fluids.read(target:getFluidContainer())
        return a,b
    end
    if sequence==c.job.payload.sequence then
        local a=c.job.payload.attempt
        if not a or a.kind~='FLUID' or a.itemIds[1]~=sourceId or a.itemIds[2]~=targetId then return nil,'COOKING_INTENT_CHANGED' end
        return {kind='Action',run=function() return Context.current(c,a.id) and a.state=='APPLIED' and 'Success' or 'Failure' end}
    end
    if sequence~=c.job.payload.sequence+1 then return nil,'STALE_COOKING_SEQUENCE' end
    local beforeSource,beforeTarget=facts()
    if not beforeSource or not beforeTarget then return nil,'FLUID_READ_UNAVAILABLE' end
    local maximum=math.min(amount,beforeSource.amount,beforeTarget.capacity-beforeTarget.amount)
    if maximum<=Policy.epsilon then return nil,'WATER_SOURCE_EMPTY' end
    local sourceWrapper=ISFluidContainer:new(source:getFluidContainer())
    local targetWrapper=ISFluidContainer:new(target:getFluidContainer())
    if not sourceWrapper:isValid() or not targetWrapper:isValid()
        or sourceWrapper:getOwner()~=source or targetWrapper:getOwner()~=target then return nil,'FLUID_OWNER_CHANGED' end
    if not FluidContainer.CanTransfer(source:getFluidContainer(),target:getFluidContainer()) then return nil,'FLUID_TRANSFER_UNAVAILABLE' end
    -- The vanilla constructor/validator delegates to a UI helper that checks
    -- getPlayer()'s inventory. Build this native action with the same fields,
    -- while the owning NPC's exact-original claims replace that UI-only gate.
    -- Update/complete/stop/perform remain the installed native implementation.
    local action=ISBaseTimedAction.new(ISFluidTransferAction,c.npc)
    action.source,action.target=sourceWrapper,targetWrapper
    action.sourceFluidObject,action.targetFluidObject=sourceWrapper:getFluidObject(),targetWrapper:getFluidObject()
    action.sourceOwner,action.targetOwner=source,target
    action.sourceStartAmount=beforeSource.amount action.amount=maximum
    action.maxTime=math.max(ISFluidUtil.getMinTransferActionTime(),maximum*ISFluidUtil.getTransferActionTimePerLiter())
    if c.npc:isTimedActionInstant() then action.maxTime=1 end
    local prepared,why=Record.begin(c.job,'FLUID',{sourceId,targetId},
        {sourceBefore=beforeSource,targetBefore=beforeTarget,maximum=maximum})
    if not prepared then return nil,why end
    if not Context.publish(c,prepared) then return nil,c.reason end
    local attemptId=c.job.payload.attempt.id local body=c.body
    local lastSource,lastTarget,moved=beforeSource,beforeTarget,0
    local queued,stopped,busy,failed,completed,performed,stopCalled=false,false,false,false,false,false,false
    local function same() return c.body==body and Context.current(c,attemptId) end
    local function active() return same() and not stopped and not failed and Context.active(c,attemptId) end
    local function state() return same() and c.job.payload.attempt.state end
    local function unknown(reason)
        failed=true c.progressive=nil Context.unknown(c,attemptId,reason or 'FLUID_EFFECT_UNKNOWN') return false
    end
    local function equalCurrent()
        local a,b=facts()
        return a and b and Fluids.equal(a,lastSource) and Fluids.equal(b,lastTarget) and a or nil,b
    end
    local function stepNative(native,self)
        if not active() or busy then return false end
        local a,b=equalCurrent() if not a then return unknown('FLUID_PROGRESS_CHANGED') end
        if state()=='PREPARED' then
            local j=Record.committing(c.job,attemptId)
            if not j or not Context.publish(c,j) then failed=true return false end
            c.progressive=attemptId
        end
        if state()~='COMMITTING' then return false end
        busy=true local ok,err=pcall(native,self) busy=false
        local afterSource,afterTarget=facts()
        local delta=afterSource and a.amount-afterSource.amount
        if not ok or not afterSource or not afterTarget or delta<0 or moved+delta>maximum+Policy.epsilon
            or not Fluids.transferred(a,afterSource,b,afterTarget,delta) then
            return unknown(ok and 'FLUID_FLOW_UNCONFIRMED' or tostring(err))
        end
        lastSource,lastTarget=afterSource,afterTarget moved=moved+delta return true
    end
    local function settle()
        if not same() or busy then return false end
        if failed or not equalCurrent() then unknown('FLUID_PROGRESS_CHANGED') return true end
        if state()=='APPLIED' or state()=='ABORTED' then return true end
        if state()=='PREPARED' then
            local j=Record.abort(c.job,attemptId) return j and Context.publish(c,j) or false
        end
        if state()~='COMMITTING' then return true end
        local j=Record.confirm(c.job,attemptId,{attemptId=attemptId,observed=true,nativeObserved=true,stopped=true,
            sourceId=sourceId,targetId=targetId,sourceBefore=beforeSource,sourceAfter=lastSource,
            targetBefore=beforeTarget,targetAfter=lastTarget,moved=moved,partial=not completed or moved+Policy.epsilon<maximum})
        if not j or not Context.publish(c,j) then unknown('FLUID_RESULT_UNCONFIRMED') return true end
        c.progressive=nil return true
    end
    c.settleStopped=settle
    local nativeUpdate=action.update
    local function nativeStart(self)
        self:setActionAnim('MixFluids')
        if target:getItemHeat()>1 then target:setItemHeat(1) end
        self:setOverrideHandModels('BottleCrafted_Ground','JarCrafted_Ground')
        self.sound=self.character:playSound('TransferLiquid')
    end
    local nativeComplete,nativePerform,nativeStop=action.complete,action.perform,action.stop
    action.useProgressBar,action.forceProgressBar=false,false
    action.isValid=function()
        return active() and equalCurrent()~=nil
            and FluidContainer.CanTransfer(source:getFluidContainer(),target:getFluidContainer()) or false
    end
    action.isValidStart=function(self) return self:isValid() end
    action.start=function(self) if self:isValidStart() then nativeStart(self) end end
    action.update=function(self) if self:isValid() then stepNative(nativeUpdate,self) end end
    action.complete=function(self)
        if completed or not active() then return false end
        if not stepNative(nativeComplete,self) then return false end completed=true return true
    end
    action.perform=function(self)
        if performed or stopped or not same() or not body.retained() then return end
        performed=true nativePerform(self) stopped=true
    end
    action.stop=function(self)
        if stopCalled or not same() or not body.retained() or busy then return end
        stopCalled=true stopped=true nativeStop(self)
    end
    return {kind='Action',run=function()
        if not same() then return 'Failure' end
        if not queued then
            if c.job.payload.attempt.dispatched then unknown('FLUID_RESTORED_DISPATCH') return 'Failure' end
            if not active() then return 'Failure' end
            local j=Record.copy(c.job) j.payload.attempt.dispatched=true
            if not Context.publish(c,j) then return 'Failure' end
            queued=true if not body.add(action) then stopped=true return 'Failure' end
        end
        if ISTimedActionQueue.hasAction(action) then return failed and 'Failure' or 'Running' end
        local fact=body.snapshot()
        if not fact.available or not fact.nativeStopped then return 'Running' end
        if not settle() then return 'Running' end
        return state()=='APPLIED' and 'Success' or 'Failure'
    end,halt=function() return body.retained() and body.clear() end}
end
return M
