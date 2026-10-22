local Probe=require "EmberRoutesProbe/Boot"
local Work=require "EmberRoutesProbe/Work"
local Store=require "EmberRoutesProbe/LaborStore"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Driver=require "EmberRoutesProbe/Driver"
local Recipe=require "EmberRoutesProbe/ProductionRecipe"
local Plan=require "EmberRoutesProbe/ProductionSupply"
local Supply=require "EmberRoutesProbe/CraftSupply"
local Transfer=require "EmberRoutesProbe/WorkTransfer"
local Actions=require "EmberRoutesProbe/ProductionActions"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Log=require "EmberRoutesProbe/Log"
local Production={}
local contexts,candidates,pending={},{},{}
local function record(id)
    local root=Registry.data() local data=root.craftProbes
    return data and data.byNpc[id]
end
function Production.handles(id) local r=record(id) return contexts[id]~=nil or (r and r.format==3) end
function Production.busy(id) return contexts[id]~=nil end
local function releaseBench(c)
    if c.ownsBench and c.object and c.object:getUsingPlayer()==c.npc then c.object:setUsingPlayer(nil) end c.ownsBench=false
end
local function changed(c,message)
    Signals.changed(c.record.npcId)
    if message then Log.write("PRODUCTION","npc="..c.record.npcId.." order="..c.record.id.." "..message) end
end
function Production.pause(reason,id)
    if reason~="SAVE" then candidates[id]=nil pending[id]=nil end
    local c=contexts[id] local r=record(id)
    if not c then
        if r and not r.released and reason=="USER" then r.generation=r.generation+1 r.state="PAUSED" r.reason=reason Signals.changed(id) end
        return
    end
    r=c.record c.cancelled=true r.generation=r.generation+1 r.state="PAUSED" r.reason=reason
    if r.phase=="COMMITTING" then r.uncertain=true r.phase="RECONCILE_REQUIRED" end
    if c.action and ISTimedActionQueue.hasAction(c.action) then ISTimedActionQueue.clear(c.npc) end
    releaseBench(c) Driver.stop(c.binding) contexts[id]=nil
    if reason=="SAVE" and not r.uncertain then
        candidates[id]={actor=c.actor,record=r,root=c.root,generation=r.generation,command=c.returnOnly and "return" or "resume"}
    end
    changed(c,"PAUSED "..tostring(reason))
end
function Production.pauseAll(reason)
    if reason~="SAVE" then candidates,pending={},{} end
    local ids={} for id in pairs(contexts) do ids[#ids+1]=id end
    for _,id in ipairs(ids) do Production.pause(reason,id) end
end
function Production.reset() Production.pauseAll("WORLD_RESET") contexts,candidates,pending={},{},{} end
local function context(actor,binding,r,entry,object)
    local c={actor=actor,npc=binding.handle,binding=binding,record=r,entry=entry,object=object,root=Registry.data(),generation=r.generation}
    c.valid=function()
        return contexts[r.npcId]==c and not c.cancelled and c.root==Registry.data() and record(r.npcId)==r
            and r.generation==c.generation and r.state=="RUNNING" and not actor:isDead()
            and actor:getUsername()==r.requester and Driver.valid(binding)
            and c.npc:getBodyDamage():getOverallBodyHealth()>=95
            and Supply.entry(actor,c.npc,c.object,r.settlementId)~=nil and Store.validNative(r,c.token)
    end
    c.changed=function(message) changed(c,message) end
    return c
end
local function makePlan(c,select)
    local spec,reason
    if not c.returnOnly and not c.record.unitMade then
        if c.record.surface and not c.object then
            local object,why=Surfaces.resolve(c.record.surface,c.record.benchId)
            if not object then return nil,why end c.object=object
        end
        spec,reason=Recipe.inspect(c.actor,c.npc,c.object,c.record.recipeId,true,false)
        if not spec then return nil,reason end
        if spec.signature~=c.record.signature then return nil,"RECIPE_CHANGED" end
    end
    local plan,why=Plan.new(c.entry,c.npc,spec,c.record,select)
    if not plan then return nil,why end
    c.spec=spec c.plan=plan c.planning=true c.inputs=nil return true
end
local function find(c,asset)
    local root=c.npc:getInventory() local location=c.plan.locations[asset.id]
    if location and location.endpoint then
        local current=Supply.endpoint(c.entry,location.endpoint.id,"take")
        if not current or current.container~=location.endpoint.container then return nil,"CONTAINER_CHANGED" end
        if Actions.inRoot(location.item,current.container,asset.id) then return location.item,nil,current end
    end
    local items=root:getItems() if items:size()>512 then return nil,"INVENTORY_LIMIT" end
    local found
    for i=0,items:size()-1 do
        if items:get(i):getID()==asset.id then if found then return nil,"ITEM_ID_CONFLICT" end found=items:get(i) end
    end
    return found,found and nil or "ITEM_MISSING"
end
local function moved(c,item,from,to,endpoint,callback)
    if not Transfer.reachable(c.npc,endpoint) then return nil,nil,endpoint end
    return Actions.transfer(c,item,from,to,endpoint,callback)
end
local function deliver(c,asset,callback)
    local item,reason,source=find(c,asset) if not item then return nil,reason end
    if asset.fullType and item:getFullType()~=asset.fullType then return nil,"INPUT_CHANGED" end
    if source and Registry.accepts(source,item) and Registry.logistics(source)=="STORAGE" then
        asset.destination=source.id if callback then callback() end return false
    end
    if not c.route then c.route=Supply.route(c.plan,item) end
    local target,done=c.route:step(32) if not done then return nil end c.route=nil
    if not target then return nil,"NO_CLASSIFIED_STORAGE_TARGET" end
    asset.destination=target.id
    local root=c.npc:getInventory()
    if item:getContainer()~=root then
        if not source then return nil,"ITEM_LOCATION_CHANGED" end
        return moved(c,item,source.container,root,source)
    end
    return moved(c,item,root,target.container,target,callback)
end
local function finish(c)
    local r=c.record releaseBench(c) contexts[r.npcId]=nil
    if r.uncertain then r.state="RECONCILE_REQUIRED" r.phase=r.state r.reason="RECONCILE_REQUIRED"
    else
        r.state=c.returnOnly and "CANCELLED" or "DONE" r.phase=r.state r.reason=nil r.released=true
        Store.finishNative(r)
    end
    r.generation=r.generation+1 changed(c,r.state)
end
local function prepare(c)
    local ready,reason=c.plan:step(32)
    if not ready then return nil,reason end
    local r=c.record
    if r.phase=="PLANNING" and not c.returnOnly then
        local proposed={} for key,value in pairs(r) do proposed[key]=value end
        proposed.materials,proposed.tools,proposed.outputs=c.plan.materials,c.plan.tools,{}
        local weight=c.spec.outputWeight
        for _,name in ipairs({"materials","tools"}) do
            for _,asset in ipairs(proposed[name]) do
                local location=c.plan.locations[asset.id]
                if not location or not location.item or Store.owner(asset.id) and Store.owner(asset.id).taskId~=r.id then return nil,"ITEM_RESERVED" end
                if location.endpoint and not Actions.inRoot(location.item,location.endpoint.container,asset.id) then return nil,"INVENTORY_CHANGED" end
                if location.item:getContainer()~=c.npc:getInventory() then weight=weight+location.item:getUnequippedWeight() end
            end
        end
        if Producers.freeCarry(c.npc)<weight then return nil,"CAPACITY_UNAVAILABLE" end
        local ok,why=Store.replaceNative(r,c.token,proposed) if not ok then return nil,why end
        r.phase="COLLECTING" changed(c,"COLLECTING")
    end
    if not c.returnOnly and not r.unitMade then
        local bySlot={} for _,input in ipairs(c.spec.inputs) do bySlot[input.slot]=input end
        c.inputs={}
        for _,name in ipairs({"materials","tools"}) do
            for _,asset in ipairs(r[name]) do
                local item,why=find(c,asset) local input=bySlot[asset.slot]
                if not item then return nil,why end
                if not input or input.keep~=(name=="tools") or not input.io:canUseItem(item,c.npc) then return nil,"INPUT_CHANGED" end
                c.inputs[#c.inputs+1]={id=asset.id,slot=asset.slot,item=item,io=input.io,keep=input.keep,asset=asset}
            end
        end
        if #c.inputs~=c.spec.inputCount then return nil,"NATIVE_INPUT_SET_CHANGED" end
    elseif not c.returnOnly then
        for _,asset in ipairs(r.outputs) do
            if asset.delivered then
                local item,_,endpoint=find(c,asset)
                if not item or not endpoint or Registry.logistics(endpoint)~="STORAGE" or not Registry.accepts(endpoint,item) then
                    r.uncertain=true return nil,"RECONCILE_REQUIRED"
                end
            end
        end
    end
    c.planning=false return true
end
local function advance(c)
    local r=c.record local root=c.npc:getInventory()
    if c.returnOnly then
        c.returned=c.returned or {}
        for _,name in ipairs({"materials","outputs","tools"}) do
            if name~="materials" or not r.unitMade then
                for _,asset in ipairs(r[name]) do
                    if not c.returned[asset.id] then
                        local item=find(c,asset)
                        if not item and r.uncertain then c.returned[asset.id]=true
                        else
                            local action,reason,movement=deliver(c,asset,function()
                                c.returned[asset.id]=true
                                if name=="outputs" and r.unitMade and not asset.delivered then
                                    asset.delivered=true if asset.fullType==r.product then r.delivered=r.delivered+1 end
                                end
                            end)
                            if action~=false then return action,reason,movement end
                        end
                    end
                end
            end
        end
        finish(c) return nil
    end
    if not r.unitMade then
        for _,input in ipairs(c.inputs) do
            if not Actions.inRoot(input.item,root,input.id) then
                local item,reason,source=find(c,input.asset) if not item then return nil,reason end
                if not source then return nil,"ITEM_LOCATION_CHANGED" end
                return moved(c,item,source.container,root,source)
            end
        end
        r.phase="CRAFTING"
        if c.spec.surface and not require("EmberRoutesProbe/CraftRecipeAdapter").atBench(c.npc,c.object) then return nil,nil,{object=c.object} end
        return Actions.craft(c)
    end
    releaseBench(c)
    if r.phase~="RETURNING" then r.phase="RETURNING" changed(c,"RETURNING") end
    for _,asset in ipairs(r.outputs) do
        if not asset.delivered then
            local action,reason,movement=deliver(c,asset,function()
                if not asset.delivered then
                    asset.delivered=true if asset.fullType==r.product then r.delivered=r.delivered+1 end changed(c,"DELIVERED "..r.delivered.."/"..r.target)
                end
            end)
            if action~=false then return action,reason,movement end
        end
    end
    if r.produced<r.target then
        local proposed={} for key,value in pairs(r) do proposed[key]=value end
        proposed.materials,proposed.outputs={},{}
        local ok,why=Store.replaceNative(r,c.token,proposed) if not ok then return nil,why end
        r.unitMade=false r.phase="PLANNING" changed(c,"NEXT_UNIT")
        local ready,reason=makePlan(c,true) if not ready then return nil,reason end return nil
    end
    if r.delivered~=r.target then return nil,"RECONCILE_REQUIRED" end
    c.returned=c.returned or {}
    for _,tool in ipairs(r.tools) do
        if not c.returned[tool.id] then
            local action,reason,movement=deliver(c,tool,function() c.returned[tool.id]=true end)
            if action~=false then return action,reason,movement end
        end
    end
    finish(c) return nil
end
local function tick(c)
    if not c.valid() then return "CARRIER_OR_OWNER_CHANGED" end
    local now=getTimestampMs() if now<(c.nextTick or 0) then return end c.nextTick=now+100
    if c.planning then local _,reason=prepare(c) return reason end
    if c.moving then
        local state,reason=c.moving.poll()
        if state=="FAILED" or now-c.started>185000 then return reason or "MOVE_TIMEOUT" end
        if state=="PASSED" then c.moving=nil end return
    end
    if c.action then
        if c.action.failure then return c.action.failure end
        if ISTimedActionQueue.hasAction(c.action) then if now-c.started>180000 then return "ACTION_TIMEOUT" end return end
        if c.action.stopped or not c.action.performed then return "NATIVE_ACTION_STOPPED" end c.action=nil
    end
    if not c.npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
    local action,reason,movement=advance(c) if reason then return reason end
    if movement then
        c.moving=Transfer.move({npc=c.npc,actor=c.actor,job=c.record},movement) c.started=now
        local state,why=c.moving.start() if state=="FAILED" then return why or "MOVE_FAILED" end
    elseif action then c.action=action c.started=now ISTimedActionQueue.add(action) end
end
function Production.tick(id)
    local c=contexts[id] if not c then return end
    local ok,reason=pcall(tick,c)
    if not ok then changed(c,"ERROR "..tostring(reason)) reason="ERROR" end
    if reason then Production.pause(reason,id) end
end
function Production.execute(actor,command,object,id,options)
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    if isClient() or isServer() then return "SP_ONLY" end
    options=options or {recipeId="Base.CarveWoodenFork",quantity=1}
    if command=="stop" then Work.pause("USER",id) return "PAUSED" end
    if Work.busy(id) then return "BUSY" end
    local binding=Driver.bindId(actor,id) if not binding then return "CARRIER_UNAVAILABLE" end
    local npc=binding.handle local r=record(id) local spec
    if npc:getBodyDamage():getOverallBodyHealth()<95 then return "INJURED" end
    if command=="run" or command=="teach" then
        if r and not r.released then return "RETURN_OR_RECONCILE_FIRST" end
        if Work.hasCargo(actor,id) then return "CARGO_RETAINED_RESUME_FIRST" end
        local why
        spec,why=Recipe.inspect(actor,npc,object,options.recipeId,command=="run",false)
        if not spec then return why end
        if command=="teach" then npc:learnRecipe(spec.recipe:getName(),true) return npc:isRecipeKnown(spec.recipe,true) and "RECIPE_TAUGHT" or "TEACH_FAILED" end
        local n=options.quantity
        if type(n)~="number" or n~=math.floor(n) or n<1 or n>9999 then return "INVALID_QUANTITY" end
        if not spec.surface then object=nil end
        local entry,reason=Supply.entry(actor,npc,object) if not entry then return reason end
        Probe.cancelAll("ACTION_ORDER",id)
        if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
        local benchId
        if object then local data=object:getModData() data.EmberRoutesCraftProbeBenchId=data.EmberRoutesCraftProbeBenchId or Registry.id() benchId=data.EmberRoutesCraftProbeBenchId end
        r={format=3,id=Registry.id(),npcId=id,requester=actor:getUsername(),generation=1,state="RUNNING",phase="PLANNING",
            recipeId=spec.id,signature=spec.signature,product=spec.product,recipeName=spec.name,unitYield=spec.yield,
            requested=n,target=math.ceil(n/spec.yield)*spec.yield,produced=0,delivered=0,materials={},tools={},outputs={},
            settlementId=entry.id,benchId=benchId,surface=object and Surfaces.location(object) or nil,released=false}
        local token,reason=Store.claimNative(r) if not token then return reason end
        Registry.data().craftProbes.byNpc[id]=r
        local c=context(actor,binding,r,entry,object) c.token=token contexts[id]=c
        local ready,why=makePlan(c,true)
        if not ready then Production.pause(why,id) return why end
        Work.wake(id) changed(c,"STARTED "..r.recipeId.." target="..r.target) return "STARTED"
    end
    if not r or r.format~=3 or r.released then return "NO_CARGO" end
    if r.requester~=actor:getUsername() then return "OWNER_CHANGED" end
    if command~="resume" and command~="return" then return "INVALID_COMMAND" end
    if command=="resume" and (r.uncertain or r.phase=="COMMITTING") then return "RECONCILE_REQUIRED" end
    if command=="resume" and not r.unitMade and r.surface then
        local resolved,why=Surfaces.resolve(r.surface,r.benchId) if not resolved then return why end object=resolved
    else object=nil end
    local entry,reason=Supply.entry(actor,npc,object,r.settlementId) if not entry then return reason end
    Probe.cancelAll("ACTION_ORDER",id)
    if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
    r.generation=r.generation+1 r.state="RUNNING" r.reason=nil
    local token,why=Store.claimNative(r)
    if not token then r.state="PAUSED" r.reason=why return why end
    local c=context(actor,binding,r,entry,object) c.token=token c.returnOnly=command=="return" contexts[id]=c
    local ready,failed=makePlan(c,r.phase=="PLANNING" and not c.returnOnly)
    if not ready then Production.pause(failed,id) return failed end
    Work.wake(id) changed(c,"RESUME "..command) return command=="return" and "RETURN_STARTED" or "RESUME_STARTED"
end
function Production.afterSave(results)
    if not results then
        for _,candidate in pairs(pending) do if candidate.record.reason=="SAVE" then candidate.record.reason="SAVE_FAILED" Signals.changed(candidate.record.npcId) end end
        pending={}
    end
    for id,candidate in pairs(candidates) do
        if results and results[id] and string.find(results[id],"^CHECKPOINT_SAVED") then pending[id]=candidate
        else candidate.record.reason="SAVE_FAILED" Signals.changed(id) end
    end
    candidates={}
end
function Production.tickPending()
    for id,candidate in pairs(pending) do
        pending[id]=nil local r=candidate.record
        if candidate.root==Registry.data() and record(id)==r and r.generation==candidate.generation and r.reason=="SAVE" and not r.uncertain then
            local ok,why=pcall(Production.execute,candidate.actor,candidate.command,nil,id)
            if not ok then r.reason="ERROR" Log.write("PRODUCTION",tostring(why)) Signals.changed(id) end
        end
        return true
    end
    return false
end
function Production.status(r)
    return {id=r.id,npcId=r.npcId,settlementId=r.settlementId,state=r.state,phase=r.phase,reason=r.reason,released=r.released,
        uncertain=r.uncertain==true,made=r.unitMade==true,resumable=not r.released and not r.uncertain and r.phase~="COMMITTING",
        recipeId=r.recipeId,recipeName=r.recipeName,product=r.product,requested=r.requested,target=r.target,produced=r.produced,delivered=r.delivered,
        surfaceRequired=r.surface~=nil,surface=r.surface and {x=r.surface.x,y=r.surface.y,z=r.surface.z} or nil}
end
return Production
