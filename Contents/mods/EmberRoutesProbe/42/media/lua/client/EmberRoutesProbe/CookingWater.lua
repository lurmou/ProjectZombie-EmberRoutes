-- One progressive native action per attempt. Never writes fluid itself or checkpoints every frame.
require 'TimedActions/ISTakeWaterAction'
local Context=require 'EmberRoutesProbe/CookingContext'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Sources=require 'EmberRoutesProbe/CookingWaterSources'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Carry=require 'EmberRoutesProbe/ProductionCarry'
local Store=require 'EmberRoutesProbe/LaborStore'
local W={}
local function near(a,b) return math.abs(a-b)<=.00001 end
function W.take(c,sequence,item,object)
    if not Context.active(c) then return nil,'COOKING_CONTROL_REQUIRED' end
    local id=item:getID() local root=c.npc:getInventory()
    local function target()
        local asset=Inventory.asset(c.job,id)
        if not asset or asset.custody~='HELD' or asset.fullType~=item:getFullType()
            or not Store.validCooking(c.job,c.token,'item:'..id) or not Inventory.contains(item,root,id) then return nil end
        return Fluids.water(item:getFluidContainer())
    end
    local previous=c.job.payload.attempt
    if sequence==c.job.payload.sequence then
        if not previous or previous.kind~='WATER' or previous.itemIds[1]~=id or not previous.spec
            or object:getModData().EmberRoutesWaterSourceId~=previous.spec.sourceId then return nil,'COOKING_INTENT_CHANGED' end
        -- Restored dispatches are never reconstructed. Only a known receipt is readable.
        return {kind='Action',run=function()
            return Context.current(c,previous.id) and previous.state=='APPLIED' and 'Success' or 'Failure'
        end}
    end
    if sequence~=c.job.payload.sequence+1 then return nil,'STALE_COOKING_SEQUENCE' end
    local before=target() if not before then return nil,'PURE_WATER_REQUIRED' end
    if before.amount>=before.capacity then return nil,'WATER_CONTAINER_FULL' end
    local endpoint={object=object}
    if not Transfer.reachable(c.npc,endpoint) then return nil,'WATER_NOT_REACHABLE' end
    local source,why=Sources.read(c.actor,c.job.scopeId,object) if not source then return nil,why end
    local action=ISTakeWaterAction:new(c.npc,item,object,false)
    if type(action.waterUnit)~='number' or action.waterUnit~=action.waterUnit or action.waterUnit<=0
        or action.waterUnit==math.huge or not Carry.fits(c.npc,action.waterUnit) then return nil,'CAPACITY_UNAVAILABLE' end
    source,why=Sources.reserve(c,object) if not source then return nil,why end
    local spec={sourceId=source.id,sourceKey=source.key,mode=source.mode,before=before,maximum=action.waterUnit,
        sourceBefore=source.backing and source.backing.snapshot}
    local job,reason=Record.begin(c.job,'WATER',{id},spec) if not job then return nil,reason end
    if not Context.publish(c,job) then return nil,c.reason end
    local attemptId=c.job.payload.attempt.id local body=c.body
    local last=before local added=0 local failed=false local busy=false local queued=false local finishing=false
    local lastSupply=source.backing and source.backing.snapshot or source.amount
    local stopped=false local completed=false local callbackStopped=false
    local function same() return c.body==body and Context.current(c,attemptId) end
    local function active() return same() and not stopped and Context.active(c,attemptId) and not failed end
    local function state() return same() and c.job.payload.attempt.state end
    local function unknown(message)
        failed=true c.progressive=nil
        Context.unknown(c,attemptId,message or 'WATER_EFFECT_UNKNOWN')
        return false
    end
    local function settle()
        if not same() or busy then return false end
        local fact=target()
        if failed or not fact or not Fluids.equal(fact,last) then unknown('WATER_PROGRESS_CHANGED') return true end
        if state()=='PREPARED' then
            local j=Record.abort(c.job,attemptId)
            return j and Context.publish(c,j) or false
        end
        if state()=='APPLIED' or state()=='ABORTED' then return true end
        if state()~='COMMITTING' then return true end
        local observed=Sources.progress(c,source)
        if not observed then unknown('WATER_SOURCE_CHANGED') return true end
        local receipt={attemptId=attemptId,observed=true,itemId=id,sourceKey=source.key,
            nativeObserved=true,stopped=true,before=before,after=fact,added=added,
            partial=not completed or added<spec.maximum-.00001,exhausted=observed.amount<=.000001,
            sourceBefore=spec.sourceBefore,sourceAfter=observed.backing and observed.backing.snapshot}
        local j=Record.confirm(c.job,attemptId,receipt)
        if not j or not Context.publish(c,j) then unknown('WATER_RESULT_UNCONFIRMED') return true end
        c.progressive=nil return true
    end
    c.settleStopped=settle
    local nativeTransfer=action.transferFluid
    action.transferFluid=function(self,amount)
        if not active() or busy or (state()~='PREPARED' and state()~='COMMITTING') then return end
        if type(amount)~='number' or amount~=amount or amount<=0 or amount==math.huge then return end
        local current=target()
        if not current or not Fluids.equal(current,last) then unknown('WATER_PROGRESS_CHANGED') return end
        local input=Sources.valid(c,source,true)
        if not input or input.amount<=0 or not Transfer.reachable(c.npc,endpoint) then stopped=true return end
        if source.mode=='FINITE' and not near(input.amount,lastSupply)
            or source.mode=='PLUMBED' and not Fluids.equal(input.backing.snapshot,lastSupply) then
            unknown('WATER_SOURCE_CHANGED') return
        end
        local maximum=math.min(amount,input.amount,current.capacity-current.amount)
        if maximum<=0 then return end
        if added+maximum>spec.maximum+.00001 then unknown('WATER_NATIVE_PLAN_CHANGED') return end
        if not Carry.fits(c.npc,maximum) then stopped=true c.reason='CAPACITY_UNAVAILABLE' return end
        if state()=='PREPARED' then
            local j=Record.committing(c.job,attemptId)
            if not j or not Context.publish(c,j) then failed=true return end
            c.progressive=attemptId
        end
        if not active() then unknown('WATER_AUTHORITY_CHANGED') return end
        busy=true
        local ok,err=pcall(nativeTransfer,self,amount)
        busy=false
        local after=target() local output=Sources.progress(c,source)
        if not ok or not after or not output then unknown(ok and 'WATER_SOURCE_CHANGED' or tostring(err)) return end
        local delta=after.amount-current.amount
        if delta<0 or delta>maximum+.00001 or not Fluids.waterAdded(current,after,delta)
            or (source.mode=='FINITE' or source.mode=='PLUMBED') and not near(input.amount-output.amount,delta)
            or source.mode=='PLUMBED' and not (delta<=.000001 and Fluids.equal(input.backing.snapshot,output.backing.snapshot)
                or Fluids.consumed(input.backing.snapshot,output.backing.snapshot,delta)) then
            unknown('WATER_FLOW_UNCONFIRMED') return
        end
        last=after added=added+delta lastSupply=output.backing and output.backing.snapshot or output.amount
    end
    local nativeStart,nativeUpdate,nativeValid=action.start,action.update,action.isValid
    local nativeStop,nativePerform,nativeComplete=action.stop,action.perform,action.complete
    action.useProgressBar,action.forceProgressBar=false,false
    action.isValid=function(self)
        return active() and target()~=nil and Sources.valid(c,source)~=nil and nativeValid(self) or false
    end
    action.isValidStart=function(self) return self:isValid() end
    action.start=function(self) if self:isValidStart() then nativeStart(self) end end
    action.update=function(self) if active() and self:isValid() then nativeUpdate(self) end end
    action.complete=function(self)
        if completed or not active() then return false end
        local ok,err=pcall(nativeComplete,self)
        if not ok then return unknown(tostring(err)) end
        completed=true return not failed
    end
    action.perform=function(self)
        if finishing or stopped or not same() or not body.retained() then return end
        finishing=true
        local ok,err=pcall(nativePerform,self)
        if not ok then unknown(tostring(err)) end
        stopped=true
    end
    action.stop=function(self)
        if callbackStopped or not same() or not body.retained() or busy then return end
        callbackStopped=true stopped=true
        nativeStop(self) -- Only presentation/queue cleanup; partial water is never undone.
    end
    return {kind='Action',run=function()
        if not same() then return 'Failure' end
        if not queued then
            if c.job.payload.attempt.dispatched then unknown('WATER_RESTORED_DISPATCH') return 'Failure' end
            if not active() then return 'Failure' end
            local j=Record.copy(c.job) j.payload.attempt.dispatched=true
            if not Context.publish(c,j) then return 'Failure' end
            queued=true if not body.add(action) then stopped=true return 'Failure' end
        end
        if ISTimedActionQueue.hasAction(action) then return failed and 'Failure' or 'Running' end
        local fact=body.snapshot()
        if not fact.available or not fact.nativeStopped then return 'Running' end
        if not settle() or not Sources.release(c,true) then return 'Running' end
        return state()=='APPLIED' and 'Success' or 'Failure'
    end,halt=function() return body.retained() and body.clear() end}
end
-- Dynamic continuation: each new source gets a fresh attempt and native residual plan.
function W.ensure(c,recipe,item)
    local request,move,leaf,source
    local portableRequest,portable,pour,fetch,portableMove,portableMode
    local tried={}
    local function portableStep(water)
        local Cargo=require 'EmberRoutesProbe/CookingCargo'
        if pour then
            local state=pour.run() if state=='Running' then return state end
            if c.job.effects~='KNOWN' then return state end
            local current=Fluids.water(portable.item:getFluidContainer())
            local receipt=c.job.payload.attempt and c.job.payload.attempt.receipt
            if not current then c.reason='PURE_WATER_REQUIRED' return 'Failure' end
            if state=='Failure' or current.amount<=.000001 or not receipt or (receipt.moved or 0)<=.000001 then
                tried[portable.id]=current.amount
                if portableRequest then portable.amount=current.amount portableRequest:skip(portable) end
            end
            pour=nil portable=nil portableMove=nil fetch=nil
            return 'Running'
        end
        if not portable then
            -- A resumed partial pour continues the already-claimed original.
            -- It cannot substitute another bottle of the same type for it.
            for _,input in ipairs(c.job.payload.liquidInputs or {}) do
                local a=Inventory.asset(c.job,input.id) local value=c.items[input.id]
                local fluid=value and Fluids.water(value:getFluidContainer())
                if a and a.custody=='HELD' and fluid and fluid.amount>.000001
                    and (not tried[input.id] or fluid.amount>tried[input.id]+.000001) then
                    portable={id=input.id,item=value,amount=fluid.amount,adopted=true} break
                end
            end
        end
        if not portable then
            if not portableRequest then
                local why
                portableRequest,why=require('EmberRoutesProbe/CookingPortableWater').new(c,item:getID())
                if not portableRequest then c.reason=why return 'Failure' end
            end
            local allowance=math.min(32,c.budget.scan) c.budget.scan=c.budget.scan-allowance
            local why
            portable,why=portableRequest:step(allowance)
            if not portable then c.reason=why return why=='SITE_OBSERVING' and 'Running' or 'Failure' end
        end
        if not portable.adopted then
            local ok,why=require('EmberRoutesProbe/CookingPortableWater').adopt(c,portable)
            if not ok then c.reason=why return 'Failure' end
            portable.adopted=true
        end
        local asset=Inventory.asset(c.job,portable.id)
        if asset.custody=='SOURCE' then
            if not portableMove then portableMove=Cargo.move(c,portable.endpoint,function()
                return require('EmberRoutesProbe/ContainerRegistry').revalidate(portable.endpoint,'take','local-world')~=nil
            end) end
            local state=portableMove.run() if state~='Success' then return state end
            if not fetch then fetch=Cargo.transfer(c,portable.id,portable.endpoint,'TAKE') end
            state=fetch.run() if state~='Success' then return state end
        end
        local why
        pour,why=require('EmberRoutesProbe/CookingFluidTransfer').new(c,c.job.payload.sequence+1,
            portable.item,item,math.max(0,water.capacity*recipe:getMinimumWater()-water.amount))
        if not pour then c.reason=why return 'Failure' end
        c.reason=nil return 'Running'
    end
    return {kind='Action',run=function()
        if not Context.current(c) then return 'Failure' end
        if pour then return portableStep() end
        if leaf then
            local state=leaf.run() if state=='Running' then return state end
            local current=Sources.read(c.actor,c.job.scopeId,source.object,true)
            if state=='Failure' and (c.job.effects~='KNOWN' or not current or current.amount>0) then return state end
            request:skip(source.object,current and current.amount or 0,source.backing and source.backing.object)
            leaf=nil move=nil source=nil
        end
        local water=Fluids.water(item:getFluidContainer())
        if not water then c.reason='PURE_WATER_REQUIRED' return 'Failure' end
        if recipe:hasMinimumWater(item) then return 'Success' end
        if not Context.active(c) then return 'Failure' end
        if portableMode then return portableStep(water) end
        if not request then request=Sources.search(c) end
        if not source then
            local allowance=c.budget.scan c.budget.scan=0
            local why
            source,why=request:step(allowance)
            if not source then
                c.reason=why
                if why=='SITE_OBSERVING' or why=='SITE_UNLOADED' or why=='FACILITIES_SCANNING' then return 'Running' end
                if why=='PURE_WATER_UNAVAILABLE' or why=='WATER_SOURCE_UNSUPPORTED' or why=='WATER_BACKING_UNAVAILABLE' then
                    portableMode=true return portableStep(water)
                end
                return 'Failure'
            end
        end
        if not move then move=require('EmberRoutesProbe/CookingCargo').move(c,{object=source.object},function()
            return Sources.read(c.actor,c.job.scopeId,source.object)~=nil
        end) end
        local result=move.run()
        if result~='Success' then
            local current=result=='Failure' and Sources.read(c.actor,c.job.scopeId,source.object,true)
            if current and current.amount<=0 then
                request:skip(source.object,0,source.backing and source.backing.object) source=nil move=nil c.reason=nil return 'Running'
            end
            return result
        end
        local why
        leaf,why=W.take(c,c.job.payload.sequence+1,item,source.object)
        if not leaf then
            if why=='WATER_SOURCE_EMPTY' then request:skip(source.object,0,source.backing and source.backing.object) source=nil move=nil return 'Running' end
            c.reason=why return 'Failure'
        end
        return 'Running'
    end}
end
return W
