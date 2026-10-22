-- Single-unit native crafting from classified shared storage. Never reads player inventory for new orders.
local Probe=require "EmberRoutesProbe/Boot"
local Work=require "EmberRoutesProbe/Work"
local Store=require "EmberRoutesProbe/LaborStore"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Driver=require "EmberRoutesProbe/Driver"
local Adapter=require "EmberRoutesProbe/CraftRecipeAdapter"
local Log=require "EmberRoutesProbe/Log"
local Record=require "EmberRoutesProbe/CraftRecord"
local Supply=require "EmberRoutesProbe/CraftSupply"
local Transfer=require "EmberRoutesProbe/WorkTransfer"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Production=require "EmberRoutesProbe/Production"
require "Entity/TimedActions/ISHandcraftAction"
require "TimedActions/ISInventoryTransferAction"
---@class EmberRoutesCraftProbeTransfer: ISInventoryTransferAction
---@field probeAttempted boolean
---@field probeError string|nil
---@field probeStopped boolean
---@field probePerformed boolean
---@field probeReason string|nil
---@field probeLogged boolean|nil
---@class EmberRoutesCraftProbeHandcraft: ISHandcraftAction
---@field probeAttempted boolean
---@field probePerformEntered boolean
---@field probeError string|nil
---@field probeStopped boolean
---@field probePerformed boolean
---@field probeReason string|nil
---@field probeLogged boolean|nil
local Craft={}
local contexts,root,records={},nil,nil
local drafts={}
local saveCandidates,autoPending={},{}
local function log(record,message)
    Log.write("CRAFT","npc="..record.npcId.." order="..record.id.." "..message) Signals.changed(record.npcId)
end
local function data()
    local current=Registry.data()
    if current~=root then
        drafts={}
        local saved=current.craftProbes or {format=1,byNpc={}}
        if saved.format~=1 or type(saved.byNpc)~="table" then error("CRAFT_RECORD_INVALID") end
        Record.records(current)
        for _,record in pairs(saved.byNpc) do
            if record.phase=="COMMITTING" then record.uncertain=true end
            if record.state=="RUNNING" then
                if record.phase=="COMMITTING" then record.uncertain=true end
                record.state="PAUSED" record.reason="LOAD_RECOVERY" record.generation=record.generation+1
            end
        end
        current.craftProbes=saved root,records=current,saved.byNpc
    end
    return records
end
function Craft.record(id) return data()[id] end
function Craft.busy(id) return contexts[id]~=nil or Production.busy(id) end
function Craft.retains(id) local record=Craft.record(id) return record and not record.released or false end
local function releaseBench(context)
    local object=context.object
    if context.ownsBench and object and object:getUsingPlayer()==context.npc then object:setUsingPlayer(nil) end
    context.ownsBench=false
end
function Craft.pause(reason,id)
    if Production.handles(id) then Production.pause(reason,id) return end
    if reason~="SAVE" then saveCandidates[id]=nil autoPending[id]=nil end
    local context=contexts[id]
    if not context then
        if reason=="USER" then
            local saved=Craft.record(id)
            if saved and not saved.released then
                saved.generation=saved.generation+1 saved.state="PAUSED" saved.reason=reason Signals.changed(id)
            end
        end
        return
    end
    local record=context.record
    -- Fence effects before stopping; native stop also calls the completion callback.
    context.cancelled=true record.generation=record.generation+1 record.state="PAUSED" record.reason=reason
    if record.phase=="COMMITTING" then record.uncertain=true end
    if context.action and ISTimedActionQueue.hasAction(context.action) then ISTimedActionQueue.clear(context.npc) end
    releaseBench(context) Driver.stop(context.binding) contexts[id]=nil
    if context.planning and not context.resumeOnly and not context.returnOnly then drafts[id]=record end
    if reason=="SAVE" then
        saveCandidates[id]={actor=context.actor,object=context.object,record=record,generation=record.generation,
            root=Registry.data(),quiet=context.quiet,command=context.returnOnly and "return" or
                ((context.planning and not context.resumeOnly) and "run" or "resume")}
    end
    log(record,"PAUSED reason="..tostring(reason).." uncertain="..tostring(record.uncertain==true))
    if not context.quiet and context.actor and not context.actor:isDead() then context.actor:Say(getText("IGUI_EmberRoutesProbe_CraftResult",tostring(reason))) end
end
function Craft.pauseAll(reason)
    Production.pauseAll(reason)
    if reason~="SAVE" then saveCandidates,autoPending={},{} end
    local ids={} for id in pairs(contexts) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do Craft.pause(reason,id) end
end
function Craft.reset() Craft.pauseAll("WORLD_RESET") Production.reset() contexts={} drafts={} root,records=nil,nil end
local function current(context)
    local record=context.record
    return contexts[record.npcId]==context and not context.cancelled
        and ((context.planning and not context.resumeOnly and not context.returnOnly) or Craft.record(record.npcId)==record)
        and record.generation==context.generation and (context.planning or record.state=="RUNNING")
        and not context.actor:isDead() and context.actor:getUsername()==record.requester
        and Driver.valid(context.binding)
        and context.npc:getBodyDamage():getOverallBodyHealth()>=95
        and (record.format~=2 or Supply.entry(context.actor,context.npc,context.object,record.settlementId)~=nil)
        and (context.planning or Store.validNative(record,context.token))
end
local function nearby(context)
    local a,n=context.actor,context.npc
    return a:getZ()==n:getZ() and math.abs(a:getX()-n:getX())<=1.6 and math.abs(a:getY()-n:getY())<=1.6
        and a:getCurrentSquare() and n:getCurrentSquare() and a:getCurrentSquare():canReachTo(n:getCurrentSquare())
end
local function inRoot(item,container,id)
    return item and item:getID()==id and item:getContainer()==container and container:getItems():contains(item)
end
local function find(context,id)
    local found,endpoint
    local containers={context.npc:getInventory()}
    if context.record.format==1 then containers[#containers+1]=context.actor:getInventory() end -- old loans: explicit recovery only
    local location=context.supply and context.supply.locations[id]
    if location then
        local currentEndpoint=Registry.revalidate(location.endpoint,"take","local-world")
        if not currentEndpoint then return nil,"CONTAINER_CHANGED" end
        containers[#containers+1]=currentEndpoint.container endpoint=currentEndpoint
    end
    for _,container in ipairs(containers) do
        local items=container:getItems()
        if items:size()>2000 then return nil,"INVENTORY_LIMIT" end
        for i=0,items:size()-1 do
            local item=items:get(i)
            if item:getID()==id then
                if found or item:getContainer()~=container then return nil,"ITEM_ID_CONFLICT" end found=item
            end
        end
    end
    return found,found and nil or "ITEM_MISSING",endpoint
end
local function endpointValid(context,endpoint,intent,item)
    if context.record.format==1 then return nearby(context) end
    local entry=Supply.entry(context.actor,context.npc,context.object,context.record.settlementId)
    local currentEndpoint=entry and Supply.endpoint(entry,endpoint.id,intent)
    local recovering=intent=="take" and context.returnOnly
    return currentEndpoint and currentEndpoint.object==endpoint.object and currentEndpoint.container==endpoint.container
        and Transfer.reachable(context.npc,endpoint) and (recovering or Registry.accepts(currentEndpoint,item))
        and (recovering or Registry.logistics(currentEndpoint)=="STORAGE")
end
local function snapshot(context)
    local ids={} local items=context.npc:getInventory():getItems()
    if items:size()>Adapter.limit then return nil end
    for i=0,items:size()-1 do
        local id=items:get(i):getID() if ids[id] then return nil end ids[id]=true
    end
    return ids
end
-- One bounded snapshot on failure, not a per-frame trace or an extra effect.
local function rejected(context,action,kind,reason)
    action.probeReason=action.probeReason or reason
    if action.probeLogged then return end action.probeLogged=true
    local npc,record=context.npc,context.record
    local square=context.object and context.object:getSquare()
    local material,tool=context.material,context.tool
    local spec=context.spec
    local inputs={}
    if action.logic and record.phase=="CRAFTING" then
        local items=action.logic:getRecipeData():getAllInputItems()
        for i=0,math.min(items:size(),8)-1 do inputs[#inputs+1]=tostring(items:get(i):getID()) end
    end
    log(record,"ACTION_REJECTED kind="..kind.." phase="..record.phase.." step="..context.index
        .." reason="..action.probeReason.." started="..tostring(action.craftStarted)
        .." npc="..npc:getX()..","..npc:getY()..","..npc:getZ()
        .." surface="..(square and (square:getX()..","..square:getY()..","..square:getZ()) or "none")
        .." materialInNpc="..tostring(material and inRoot(material,npc:getInventory(),record.materialId))
        .." toolInNpc="..tostring(tool and inRoot(tool,npc:getInventory(),record.toolId))
        .." tool="..tostring(tool and tool:getFullType()).." condition="..tostring(tool and tool:getCondition())
        .." sharpness="..tostring(tool and tool:getSharpness()).." freeCarry="..Producers.freeCarry(npc)
        .." materialAllowed="..tostring(spec and material and spec.material:canUseItem(material,npc))
        .." toolAllowed="..tostring(spec and tool and spec.tool:canUseItem(tool,npc))
        .." active="..tostring(EmberRoutesProbeJava.carrierActive(npc))
        .." appliedIds="..table.concat(inputs,","))
end
---@return EmberRoutesCraftProbeTransfer?, string?
local function transfer(context,item,from,to,id,endpoint)
    local function valid()
        return current(context) and EmberRoutesProbeJava.carrierActive(context.npc) and inRoot(item,from,id) and Store.validNative(context.record,context.token,"item:"..id)
            and endpointValid(context,endpoint,to==context.npc:getInventory() and "take" or "put",item)
            and not item:getIsCraftingConsumed() and to:hasRoomFor(context.npc,item)
            and (to~=context.npc:getInventory() or Producers.freeCarry(context.npc)>=item:getUnequippedWeight())
            and (context.record.format==1 or to==context.npc:getInventory()
                or Store.availableCapacity(endpoint.id,to:getFreeCapacity(context.npc))>=item:getUnequippedWeight())
    end
    if not valid() then return nil,"TRANSFER_PRECONDITION" end
    local action=ISInventoryTransferAction:new(context.npc,item,from,to,90)
    ---@cast action EmberRoutesCraftProbeTransfer
    local nativeValid,nativePerform,nativeAnim=action.isValid,action.perform,action.startActionAnim
    local nativeStop=action.stop
    action.useProgressBar,action.forceProgressBar=false,false
    action.isValid=function(self)
        local ok=valid()
        if not ok or not nativeValid(self) then
            rejected(context,self,"TRANSFER",ok and "NATIVE_TRANSFER_REJECTED" or "TRANSFER_PRECONDITION") return false
        end
        return true
    end
    action.startActionAnim=function(self) nativeAnim(self) self.selectedContainer=nil end
    action.perform=function(self)
        if self.probeAttempted then return end self.probeAttempted=true
        if not self:isValid() then self:stop() return end
        local ok,err=pcall(nativePerform,self)
        if not ok then self.probeError=tostring(err) log(context.record,"TRANSFER_ERROR "..self.probeError) end
        self.probePerformed=ok and inRoot(item,to,id) and not from:getItems():contains(item)
        if not self.probePerformed then rejected(context,self,"TRANSFER","TRANSFER_POSTCONDITION") end
        if self.probePerformed then
            if context.supply then
                if to==context.npc:getInventory() then context.supply.locations[id]=nil
                else context.supply.locations[id]={item=item,endpoint=endpoint} end
            end
            Registry.inventoryChanged(from) Registry.inventoryChanged(to)
        end
    end
    action.stop=function(self)
        self.probeStopped=true rejected(context,self,"TRANSFER","TRANSFER_INTERRUPTED") nativeStop(self)
    end
    return action
end
---@return EmberRoutesCraftProbeHandcraft?, string?
local function craftAction(context)
    local record,npc=context.record,context.npc
    local spec,reason=Adapter.inspect(context.actor,npc,context.object,true)
    if not spec then return nil,reason end
    if context.object:getModData().EmberRoutesCraftProbeBenchId~=record.benchId then return nil,"BENCH_CHANGED" end
    local material,tool=context.material,context.tool
    local inventory=npc:getInventory()
    local before=snapshot(context) if not before then return nil,"INVENTORY_LIMIT" end
    local function invalidReason()
        if not current(context) then return "CRAFT_CONTEXT_CHANGED" end
        if not EmberRoutesProbeJava.carrierActive(npc) then return "CARRIER_MOVING" end
        if record.phase~="CRAFTING" or record.uncertain then return "CRAFT_PHASE_CHANGED" end
        if not inRoot(material,inventory,record.materialId) then return "MATERIAL_NOT_IN_NPC" end
        if not inRoot(tool,inventory,record.toolId) then return "TOOL_NOT_IN_NPC" end
        if not Store.validNative(record,context.token,"item:"..record.materialId)
            or not Store.validNative(record,context.token,"item:"..record.toolId) then return "INPUT_CLAIM_CHANGED" end
        local inspected,why=Adapter.inspect(context.actor,npc,context.object,true)
        if not inspected then return why end
        if not context.object:isUsingPlayer(npc) then return "SURFACE_OCCUPANCY_CHANGED" end
        if context.object:getModData().EmberRoutesCraftProbeBenchId~=record.benchId then return "BENCH_CHANGED" end
        if inventory:getCapacityWeight()+spec.outputWeight>inventory:getEffectiveCapacity(npc)
            or Producers.freeCarry(npc)<spec.outputWeight then return "OUTPUT_CAPACITY_UNAVAILABLE" end
    end
    context.spec=spec record.phase="CRAFTING"
    -- Exact identities, no floor/container auto-selection and no force flag.
    local action=ISHandcraftAction:new(npc,spec.recipe,Adapter.list(inventory),context.object,spec.bench,
        Adapter.manual(spec,material,tool),nil,nil,1,0)
    ---@cast action EmberRoutesCraftProbeHandcraft
    local nativeValid,nativeStart,nativeStop=action.isValid,action.start,action.stop
    local nativePerform=action.perform
    local nativeRecipe=action.performRecipe
    action.useProgressBar,action.forceProgressBar=false,false
    action.isValid=function(self)
        local why=invalidReason()
        if not why and not nativeValid(self) then why="NATIVE_ACTION_INVALID" end
        if why then rejected(context,self,"CRAFT",why) return false end return true
    end
    action.start=function(self)
        if not self:isValid() then self:forceStop() return end
        nativeStart(self)
        if not self.craftStarted then
            rejected(context,self,"CRAFT",self.logic and "NATIVE_RECIPE_REJECTED" or "NATIVE_START_INCOMPLETE")
            self:forceStop() return
        end
        local applied,why=Adapter.applied(self.logic,material,tool)
        if not applied then
            rejected(context,self,"CRAFT",why) self:forceStop()
        else log(record,"CRAFT_STARTED material="..record.materialId.." tool="..record.toolId) end
    end
    action.stop=function(self)
        self.probeStopped=true
        local why=invalidReason()
        if not why and not self.craftStarted then
            why=self.logic and "NATIVE_RECIPE_REJECTED" or "NATIVE_START_INCOMPLETE"
        end
        if not why and record.phase=="CRAFTING" then local _,inputReason=Adapter.applied(self.logic,material,tool) why=inputReason end
        rejected(context,self,"CRAFT",why or "CRAFT_INTERRUPTED") nativeStop(self)
    end
    action.perform=function(self)
        if self.probePerformEntered then return end self.probePerformEntered=true
        if not self:isValid() then self:stop() return end
        local applied,why=Adapter.applied(self.logic,material,tool)
        if not applied then rejected(context,self,"CRAFT",why) self:stop() return end
        local ok,err=pcall(nativePerform,self)
        if not ok then
            self.probeError=tostring(err)
            if self.probeAttempted then record.uncertain=true end
            log(record,"PERFORM_ERROR "..self.probeError)
        end
    end
    action.performRecipe=function(self)
        if self.probeAttempted then return end self.probeAttempted=true
        local logic=self.logic
        if not self:isValid() then self:stop() return end
        if not logic then rejected(context,self,"CRAFT","NATIVE_LOGIC_MISSING") self:stop() return end
        local applied,why=Adapter.applied(logic,material,tool)
        if not applied then rejected(context,self,"CRAFT",why) self:stop() return end
        record.phase="COMMITTING" record.conditionBefore=tool:getCondition() record.sharpnessBefore=tool:getSharpness()
        log(record,"COMMITTING material="..record.materialId.." tool="..record.toolId)
        -- One explicit native-effect boundary: any exception is visible and forbids replay.
        local ok,err=pcall(nativeRecipe,self)
        local outputs=ArrayList.new() logic:getCreatedOutputItems(outputs)
        record.outputIds={}
        for i=0,math.min(outputs:size(),8)-1 do record.outputIds[#record.outputIds+1]=outputs:get(i):getID() end
        ---@type InventoryItem|nil
        local output=outputs:size()==1 and outputs:get(0) or nil
        local consumed=logic:getRecipeData():getAllConsumedItems():contains(material)
            and material:getContainer()==nil and not inventory:getItems():contains(material)
            and (record.format==2 or not context.actor:getInventory():getItems():contains(material))
        local claimed,claimReason=Store.extendNative(record,context.token)
        if not claimed then ok=false err=claimReason end
        local kept=inRoot(tool,inventory,record.toolId)
        local identity=output~=nil and output:getFullType()=="Base.WoodenFork" and not before[output:getID()]
        local produced=output~=nil and identity and inRoot(output,inventory,output:getID())
        record.nativeReturned=ok record.consumptionVerified=consumed==true
        record.outputVerified=identity==true record.toolVerified=kept==true
        record.conditionAfter=tool:getCondition() record.sharpnessAfter=tool:getSharpness()
        if output and ok and consumed and kept and produced and current(context) then
            record.made=true record.phase="CONFIRMED" self.probePerformed=true context.output=output
            log(record,"CONFIRMED output="..output:getID().." toolCondition="..record.conditionBefore.."->"..record.conditionAfter
                .." sharpness="..record.sharpnessBefore.."->"..record.sharpnessAfter)
        else
            record.uncertain=true record.phase="RECONCILE_REQUIRED" self.probeError=tostring(err or "ASSET_POSTCONDITION")
            log(record,"RECONCILE_REQUIRED "..self.probeError.." outputs="..outputs:size())
        end
    end
    context.object:setUsingPlayer(npc) context.ownsBench=true
    if not context.object:isUsingPlayer(npc) then releaseBench(context) return nil,"BENCH_OCCUPIED" end
    return action
end
local function finish(context)
    local record=context.record
    releaseBench(context) contexts[record.npcId]=nil
    -- An output dropped by native capacity handling can be picked up manually.
    -- Only the proven original result, with verified native consumption, may close that gap.
    if context.returnOnly and record.nativeReturned and record.consumptionVerified and record.outputVerified
        and record.toolVerified and #record.outputIds==1 then record.uncertain=false record.made=true end
    record.state=record.uncertain and "RECONCILE_REQUIRED" or (record.made and "DONE" or "CANCELLED")
    record.phase=record.state record.released=not record.uncertain record.reason=nil
    record.generation=record.generation+1
    if record.released then Store.finishNative(record) end
    log(record,record.state.." original items delivered")
    if not context.quiet then context.actor:Say(getText("IGUI_EmberRoutesProbe_CraftResult",record.state)) end
end
local function movedTransfer(context,item,from,to,id,endpoint)
    if context.record.format==2 and not Transfer.reachable(context.npc,endpoint) then return nil,nil,endpoint end
    return transfer(context,item,from,to,id,endpoint)
end
local function deliver(context,item,id,field)
    if not item then return nil,"ITEM_MISSING" end
    if item:getContainer()~=context.npc:getInventory() then
        local location=context.supply.locations[id]
        if location then
            local entry=Supply.entry(context.actor,context.npc,context.object,context.record.settlementId)
            local endpoint=entry and Supply.endpoint(entry,location.endpoint.id,"put")
            if endpoint and Registry.logistics(endpoint)=="STORAGE" and Registry.accepts(endpoint,item) then
                context.record[field]=endpoint.id return false
            end
        end
    end
    if not context.route then context.route=Supply.route(context.supply,item) end
    local endpoint,done=context.route:step(32)
    if not done then return nil end
    context.route=nil
    if not endpoint then return nil,"NO_CLASSIFIED_STORAGE_TARGET" end
    context.record[field]=endpoint.id
    if item:getContainer()==endpoint.container then return false end
    if item:getContainer()~=context.npc:getInventory() then
        local location=context.supply.locations[id]
        if not location or location.item~=item then return nil,"ITEM_LOCATION_CHANGED" end
        return movedTransfer(context,item,item:getContainer(),context.npc:getInventory(),id,location.endpoint)
    end
    return movedTransfer(context,item,context.npc:getInventory(),endpoint.container,id,endpoint)
end
local function nextAction(context)
    local record=context.record local npcRoot=context.npc:getInventory()
    if context.returnOnly then
        local proven=record.nativeReturned and record.consumptionVerified and record.outputVerified and record.toolVerified
        local ids={record.toolId}
        if not record.made and not proven then ids[#ids+1]=record.materialId end
        for _,id in ipairs(record.outputIds) do ids[#ids+1]=id end
        context.returned=context.returned or {}
        for _,id in ipairs(ids) do
            if not context.returned[id] then
                local item,reason=find(context,id) if not item then return nil,reason end
                if record.format==1 then
                    if item:getContainer()==npcRoot then return transfer(context,item,npcRoot,context.actor:getInventory(),id) end
                    context.returned[id]=true
                else
                    local field=id==record.toolId and "toolDestination" or (id==record.materialId and "materialReturn" or "destination")
                    local action,why,movement=deliver(context,item,id,field)
                    if action==false then context.returned[id]=true
                    else context.repeatStep=true return action,why,movement end
                end
            end
        end
        finish(context) return nil
    end
    local index=context.index
    if index<=2 then
        local item=index==1 and context.material or context.tool
        local endpoint=index==1 and context.materialSource or context.toolSource
        if inRoot(item,npcRoot,item:getID()) then context.index=context.index+1 return nil end
        if not endpoint then return nil,"ITEM_LOCATION_CHANGED" end
        return movedTransfer(context,item,endpoint.container,npcRoot,item:getID(),endpoint)
    elseif index==3 then
        if not Adapter.atBench(context.npc,context.object) then return nil,nil,{object=context.object} end
        return craftAction(context)
    elseif index==4 or index==5 then
        releaseBench(context)
        if record.phase~="RETURNING" then record.phase="RETURNING" Signals.changed(record.npcId) end
        local item=index==4 and context.output or context.tool
        local action,reason,movement=deliver(context,item,item:getID(),index==4 and "destination" or "toolDestination")
        if action==false then context.index=context.index+1 return nil end
        -- A collected misplaced recovery item must still be delivered next tick.
        context.repeatStep=item:getContainer()~=npcRoot
        return action,reason,movement
    end
    finish(context)
end
local function resumeInputs(context)
    local record=context.record
    local tool,why,toolEndpoint=find(context,record.toolId)
    if not tool then return nil,why end
    context.tool,context.toolSource=tool,toolEndpoint
    if record.made then
        if #record.outputIds~=1 then return nil,"NATIVE_INPUT_SET_CHANGED" end
        local output,reason=find(context,record.outputIds[1])
        if not output then return nil,reason end
        context.output=output context.index=4 return true
    end
    if record.uncertain or #record.outputIds~=0 or record.consumptionVerified then return nil,"RECONCILE_REQUIRED" end
    local material,reason,source=find(context,record.materialId)
    if not material then return nil,reason end
    local spec,failed=Adapter.inspect(context.actor,context.npc,context.object,true,false)
    if not spec then return nil,failed end
    if not Producers.eligible(material) or not Producers.eligible(tool)
        or not spec.material:canUseItem(material,context.npc) or not spec.tool:canUseItem(tool,context.npc) then
        return nil,"INPUT_CHANGED"
    end
    context.material,context.materialSource,context.spec=material,source,spec
    return true
end
local function prepare(context)
    local ready,reason=context.supply:step(32)
    if not ready then if reason then Craft.pause(reason,context.record.npcId) end return end
    local record=context.record
    if context.resumeOnly then
        local ok,why=resumeInputs(context)
        if not ok then Craft.pause(why,record.npcId) return end
        record.generation=record.generation+1 record.state="RUNNING" record.reason=nil
        record.phase=record.made and "RETURNING" or "COLLECTING"
    elseif context.returnOnly then
        record.generation=record.generation+1 record.state="RUNNING" record.phase="RETURNING"
    else
        local plan=context.supply
        if not plan.material or not plan.tool then Craft.pause("MATERIALS_UNAVAILABLE",record.npcId) return end
        local source=Registry.revalidate(plan.materialSource,"take","local-world")
        local toolSource
        if not plan.toolFromNpc then toolSource=Registry.revalidate(plan.toolSource,"take","local-world") end
        local toolRoot=plan.toolFromNpc and context.npc:getInventory() or (toolSource and toolSource.container)
        if not source or Registry.logistics(source)~="STORAGE" or not Registry.accepts(source,plan.material)
            or not inRoot(plan.material,source.container,plan.material:getID()) or not toolRoot
            or not inRoot(plan.tool,toolRoot,plan.tool:getID()) or Store.owner(plan.material:getID()) or Store.owner(plan.tool:getID())
            or not Producers.eligible(plan.material) or not Producers.eligible(plan.tool)
            or (not plan.toolFromNpc and (Registry.logistics(toolSource)~="STORAGE" or not Registry.accepts(toolSource,plan.tool)))
            or not plan.spec.material:canUseItem(plan.material,context.npc) or not plan.spec.tool:canUseItem(plan.tool,context.npc) then
            Craft.pause("INPUT_CHANGED",record.npcId) return
        end
        record.materialId=plan.material:getID() record.toolId=plan.tool:getID()
        record.source=plan.materialSource.id record.toolFromNpc=plan.toolFromNpc==true
        record.toolSource=plan.toolSource and plan.toolSource.id or nil record.phase="COLLECTING"
        local total=plan.material:getActualWeight()+(plan.toolFromNpc and 0 or plan.tool:getActualWeight())+plan.spec.outputWeight
        if Producers.freeCarry(context.npc)<total then
            Craft.pause("CAPACITY_UNAVAILABLE",record.npcId) return
        end
        context.material,context.tool=plan.material,plan.tool
        context.materialSource,context.toolSource=plan.materialSource,plan.toolSource
    end
    local token,why=Store.claimNative(record)
    if not token then Craft.pause(why or "ITEM_RESERVED",record.npcId) return end
    context.token=token context.generation=record.generation context.planning=false
    data()[record.npcId]=record
    log(record,"CLAIMED material="..record.materialId.." tool="..record.toolId)
end
local function tick(context)
    if not current(context) then Craft.pause("CARRIER_OR_OWNER_CHANGED",context.record.npcId) return end
    local time=getTimestampMs()
    if time<(context.nextTick or 0) then return end context.nextTick=time+100
    if context.planning then prepare(context) return end
    if context.moving then
        local state,reason=context.moving.poll()
        if state=="FAILED" or time-context.started>185000 then Craft.pause(reason or "MOVE_TIMEOUT",context.record.npcId)
        elseif state=="PASSED" then context.moving=nil end
        return
    end
    if context.action then
        if context.action.probeError then Craft.pause(context.action.probeError,context.record.npcId) return end
        if ISTimedActionQueue.hasAction(context.action) then
            if time-context.started>180000 then Craft.pause("ACTION_TIMEOUT",context.record.npcId) end
            return
        end
        if context.action.probeError or context.action.probeStopped or not context.action.probePerformed then
            if not context.action.probeReason and not context.action.probeError then
                rejected(context,context.action,context.action.craftRecipe and "CRAFT" or "TRANSFER","ACTION_LEFT_QUEUE_WITHOUT_RESULT")
            end
            Craft.pause(context.action.probeError or context.action.probeReason or "NATIVE_ACTION_STOPPED",context.record.npcId) return
        end
        context.action=nil
        if not context.repeatStep then context.index=context.index+1 end context.repeatStep=false
    end
    if not context.npc:getCharacterActions():isEmpty() then Craft.pause("NATIVE_ACTION_BUSY",context.record.npcId) return end
    local action,reason,movement=nextAction(context)
    if reason then Craft.pause(reason,context.record.npcId) return end
    if movement then
        context.moving=Transfer.move({npc=context.npc,actor=context.actor,job=context.record},movement) context.started=time
        local state,why=context.moving.start() if state=="FAILED" then Craft.pause(why,context.record.npcId) end
    elseif action then context.action=action context.started=time ISTimedActionQueue.add(action) end
end
function Craft.tick(id)
    if Production.busy(id) then Production.tick(id) return end
    local context=contexts[id] if not context then return end
    local ok,err=pcall(tick,context)
    if not ok then log(context.record,"ERROR "..tostring(err)) Craft.pause("ERROR",id) end
end
local function execute(actor,command,object,npcId,quiet)
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    if isClient() or isServer() then return "SP_ONLY" end
    local id=npcId or Driver.selected(actor)
    local record=Craft.record(id) or (contexts[id] and contexts[id].record)
    if command=="report" then
        if not record then return "NO_REPORT" end
        log(record,"REPORT state="..record.state.." phase="..record.phase.." made="..tostring(record.made==true)
            .." released="..tostring(record.released==true).." uncertain="..tostring(record.uncertain==true)
            .." material="..tostring(record.materialId).." tool="..tostring(record.toolId).." reason="..tostring(record.reason))
        for _,outputId in ipairs(record.outputIds) do log(record,"REPORT output="..outputId) end
        return record.state.." / "..record.phase
    elseif command=="stop" then Work.pause("USER",id) return "PAUSED" end
    if Craft.busy(id) or Work.busy(id) then return "BUSY" end
    local binding=Driver.bindId(actor,id) if not binding then return "CARRIER_UNAVAILABLE" end
    local npc=binding.handle
    if npc:getBodyDamage():getOverallBodyHealth()<95 then return "INJURED" end
    if command=="resume" then
        if not record or record.released then return "NO_CARGO" end
        if record.format~=2 then return "RETURN_OR_RECONCILE_FIRST" end
        if record.requester~=actor:getUsername() then return "OWNER_CHANGED" end
        if record.uncertain or record.phase=="COMMITTING" then return "RECONCILE_REQUIRED" end
        if not record.made then
            if not object then
                local resolved,why=Surfaces.resolve(record.surface,record.benchId)
                if not resolved then return why end object=resolved
            end
            if object:getModData().EmberRoutesCraftProbeBenchId~=record.benchId then return "BENCH_CHANGED" end
            record.surface=Surfaces.location(object)
        else object=nil end
        local entry,reason=Supply.entry(actor,npc,object,record.settlementId)
        if not entry then return reason end
        local plan,why=Supply.new(entry,npc,nil,record)
        if not plan then return why end
        Probe.cancelAll("ACTION_ORDER",id)
        if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
        contexts[id]={record=record,binding=binding,npc=npc,actor=actor,object=object,index=1,
            generation=record.generation,resumeOnly=true,planning=true,supply=plan,quiet=quiet}
        Work.wake(id) log(record,"RESUME_PLANNING") return "RESUME_STARTED"
    elseif command=="return" then
        if not record or record.released then return "NO_CARGO" end
        if record.requester~=actor:getUsername() then return "OWNER_CHANGED" end
    elseif command=="run" or command=="teach" then
        if Craft.retains(id) then return "RETURN_OR_RECONCILE_FIRST" end
        if Work.hasCargo(actor,id) then return "CARGO_RETAINED_RESUME_FIRST" end
        local spec,reason=Adapter.inspect(actor,npc,object,command=="run",false)
        if not spec then return reason end
        if command=="teach" then
            npc:learnRecipe(spec.recipe:getName(),true)
            return npc:isRecipeKnown(spec.recipe,true) and "RECIPE_TAUGHT" or "TEACH_FAILED"
        end
        local entry,entryReason=Supply.entry(actor,npc,object)
        if not entry then return entryReason end
        local plan,planReason=Supply.new(entry,npc,spec)
        if not plan then return planReason end
        local benchData=object:getModData()
        benchData.EmberRoutesCraftProbeBenchId=benchData.EmberRoutesCraftProbeBenchId or Registry.id()
        record={format=2,id=Registry.id(),npcId=id,requester=actor:getUsername(),generation=1,state="RUNNING",
            phase="PLANNING",benchId=benchData.EmberRoutesCraftProbeBenchId,surface=Surfaces.location(object),
            settlementId=entry.id,outputIds={},released=false}
        local context={record=record,binding=binding,npc=npc,actor=actor,object=object,
            index=1,generation=record.generation,supply=plan,planning=true,quiet=quiet}
        Probe.cancelAll("ACTION_ORDER",id)
        if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
        drafts[id]=nil contexts[id]=context Work.wake(id) log(record,"PLANNING classified storage") return "STARTED"
    else return "INVALID_COMMAND" end
    Probe.cancelAll("ACTION_ORDER",id)
    if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
    local context={record=record,binding=binding,npc=npc,actor=actor,index=1,generation=record.generation,returnOnly=true,quiet=quiet}
    if record.format==1 then
        if not nearby(context) then return "STAND_BY_NPC" end
        record.generation=record.generation+1 record.state="RUNNING" record.phase="RETURNING" context.generation=record.generation
        local token,reason=Store.claimNative(record) if not token then record.state="PAUSED" return reason end context.token=token
    else
        local entry,reason=Supply.entry(actor,npc,nil,record.settlementId) if not entry then return reason end
        local plan,why=Supply.new(entry,npc,nil,record) if not plan then return why end
        context.supply=plan context.planning=true
    end
    contexts[id]=context Work.wake(id) return "RETURN_STARTED"
end
function Craft.execute(actor,command,object,npcId,quiet,options)
    local id=npcId or Driver.selected(actor)
    data() -- Normalize loaded records before the production branch can use them.
    if options or Production.handles(id) then
        local ok,result=pcall(Production.execute,actor,command,object,id,options)
        if not ok then Log.write("PRODUCTION","COMMAND_ERROR "..tostring(result)) Production.pause("ERROR",id) result="ERROR" end
        if not quiet then actor:Say(getText("IGUI_EmberRoutesProbe_CraftResult",tostring(result))) end
        return result
    end
    local ok,result=pcall(execute,actor,command,object,npcId,quiet)
    if not ok then
        local id=npcId or Driver.selected(actor) local record=Craft.record(id)
        if record then log(record,"COMMAND_ERROR "..tostring(result)) end
        Craft.pause("ERROR",id) result="ERROR"
    end
    if not quiet then actor:Say(getText("IGUI_EmberRoutesProbe_CraftResult",tostring(result))) end return result
end
-- Schedule only after every checkpoint was accepted; never resume inside OnSave.
function Craft.afterSave(results)
    Production.afterSave(results)
    local function failed(candidate)
        local record=candidate.record
        if candidate.root==Registry.data() and record.generation==candidate.generation and record.reason=="SAVE" then
            record.reason="SAVE_FAILED" Signals.changed(record.npcId)
        end
    end
    if not results then
        for _,candidate in pairs(autoPending) do failed(candidate) end autoPending={}
    end
    for id,candidate in pairs(saveCandidates) do
        if results and results[id] and string.find(results[id],"^CHECKPOINT_SAVED") then autoPending[id]=candidate
        else failed(candidate) end
    end
    saveCandidates={}
end
function Craft.tickPending()
    if Production.tickPending() then return end
    for id,candidate in pairs(autoPending) do
        autoPending[id]=nil
        local record=candidate.record
        if candidate.root==Registry.data() and record.generation==candidate.generation
            and record.state=="PAUSED" and record.reason=="SAVE" and not record.uncertain then
            Craft.execute(candidate.actor,candidate.command,candidate.object,id,candidate.quiet)
        end
        return -- one worker per normal tick; no automatic retry loop
    end
end
function Craft.status(id)
    local saved=Craft.record(id)
    local record=(contexts[id] and contexts[id].record) or drafts[id] or saved
    if not record then return nil end
    if record.format==3 then return Production.status(record) end
    local draft=drafts[id]==record
    return {id=record.id,npcId=id,settlementId=record.settlementId,state=record.state,phase=record.phase,
        reason=record.reason,released=record.released or draft,uncertain=record.uncertain==true,made=record.made==true,
        resumable=not draft and record.format==2 and not record.released and not record.uncertain and record.phase~="COMMITTING",
        surface=record.surface and {x=record.surface.x,y=record.surface.y,z=record.surface.z} or nil}
end
Probe.afterCraftSave=Craft.afterSave
Probe.tickCrafting=Craft.tickPending
Work.registerExecutor("CRAFT_PROBE",Craft)
return Craft
