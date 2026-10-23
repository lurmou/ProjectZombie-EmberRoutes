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
local Carry=require "EmberRoutesProbe/ProductionCarry"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Log=require "EmberRoutesProbe/Log"
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Production={}
local contexts,candidates,pending={},{},{}
local requests={}
local waiting,inventoryDirty,inventoryRevision={},false,0
local function inventoryChanged() inventoryDirty=true inventoryRevision=inventoryRevision+1 end
if Registry.inventoryListeners then Registry.inventoryListeners[#Registry.inventoryListeners+1]=inventoryChanged end
if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(inventoryChanged) end
local function record(id)
    return require('EmberRoutesProbe/BusinessJobs').crafts()[id]
end
function Production.handles(id)
    local request=requests[id]
    if request and request.root==Registry.data() then
        local state=request.runtime:inspect(request.handle)
        if state and (state.state=='PENDING' or state.state=='QUEUED' or state.state=='ACTIVE' or state.state=='STOPPING') then return true end
        requests[id]=nil
    end
    local r=record(id) return contexts[id]~=nil or (r and r.format==3)
end
function Production.busy(id) return contexts[id]~=nil end
local function rejectUncollected(c,fact)
    local r=c.record
    if fact.bodyStopped~=true or fact.effects~='KNOWN' or r.reason~='CAPACITY_UNAVAILABLE'
        or r.uncertain or r.unitMade or r.produced~=0 or r.delivered~=0
        or (r.chain and r.chain.index>1) then return end
    local containers,seen={c.npc:getInventory()},{[c.npc:getInventory()]=true}
    local assets={}
    for _,name in ipairs({'materials','tools','outputs','held'}) do
        for _,asset in ipairs(r[name] or {}) do
            local location=c.plan and c.plan.locations[asset.id]
            if not location or not location.endpoint then return end
            local endpoint=Supply.endpoint(c.entry,location.endpoint.id,'take')
            if not endpoint or endpoint.container~=location.endpoint.container
                or Registry.logistics(endpoint)~='STORAGE' then return end
            if not seen[endpoint.container] then seen[endpoint.container]=true containers[#containers+1]=endpoint.container end
            assets[asset.id]=endpoint.container
        end
    end
    local View=require 'EmberRoutesProbe/InventoryView'
    local index=View.index(containers)
    if not index then return end
    for id,container in pairs(assets) do
        local item=View.find(index,id)
        if not item or item:getContainer()~=container then return end
    end
    -- No original left its verified warehouse and no product was made. Release
    -- only this Job's claims AFTER confirmed stop, never erase unknown cargo.
    Store.finishNative(r) r.released=true r.state='CANCELLED' r.phase='CANCELLED'
    c.completed=true c.closedGeneration=r.generation
    Log.write('PRODUCTION','npc='..r.npcId..' order='..r.id..' REJECTED_UNCOLLECTED CAPACITY_UNAVAILABLE')
end
function Production.stopAdapter(id,controller,ticket)
    local c=contexts[id]
    if not c then return nil,'NO_ACTIVE_PRODUCTION' end
    local r,root,generation=c.record,c.root,c.record.generation
    return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,npc=c.npc,npcId=id,jobId=r.id,
        same=function(paused)
            if root~=Registry.data() or record(id)~=r then return false end
            if c.completed then return r.generation==c.closedGeneration end
            if c.stopped then return r.generation==c.stoppedGeneration and r.state=='PAUSED' end
            return not paused and not r.released and r.generation==generation and contexts[id]==c
        end,
        pause=function(reason)
            if c.completed then return true end
            return Production.pause(reason,id,c)
        end,
        effects=function() return r.uncertain and 'UNKNOWN' or 'KNOWN' end,
        persist=function(fact)
            if fact.effects=='UNKNOWN' then r.uncertain=true r.phase='RECONCILE_REQUIRED' end
            rejectUncollected(c,fact)
            Signals.changed(id)
            return c.completed or r.state=='PAUSED'
        end})
end
local function releaseBench(c)
    if c.ownsBench and c.object and c.object:getUsingPlayer()==c.npc then c.object:setUsingPlayer(nil) end c.ownsBench=false
end
local function changed(c,message)
    Signals.changed(c.record.npcId)
    if message then Log.write("PRODUCTION","npc="..c.record.npcId.." order="..c.record.id.." "..message) end
end
local function fits(c,added,consumed,output)
    local ok,fact=Carry.fits(c.npc,added,consumed,output)
    if not ok then
        local fields={}
        for _,key in ipairs({'weight','maximum','capacity','added','consumed','output','peak','limit'}) do
            fields[#fields+1]=key..'='..tostring(fact[key])
        end
        changed(c,'CAPACITY_CHECK '..table.concat(fields,' '))
    end
    return ok
end
function Production.pause(reason,id,owned)
    local c=owned or contexts[id]
    if c and c.body and not owned then return c.body.requestStop(reason or 'USER') end
    local request=requests[id]
    if not owned and request and request.root==Registry.data() then request.runtime:stopJob(id,request.jobId,reason or 'USER') end
    waiting[id]=nil
    if reason~="SAVE" then candidates[id]=nil pending[id]=nil end
    local r=record(id)
    if not c then
        if r and not r.released and reason=="USER" then r.generation=r.generation+1 r.state="PAUSED" r.reason=reason Signals.changed(id) end
        return
    end
    r=c.record
    if not c.stopped then
        c.stopped=true c.cancelled=true r.generation=r.generation+1 r.state="PAUSED" r.reason=reason
        c.stoppedGeneration=r.generation
        if c.chainRequest then c.chainRequest:cancel() end
        if r.phase=="COMMITTING" then r.uncertain=true r.phase="RECONCILE_REQUIRED" end
    end
    if c.body then
        if not c.body.clear() then return false end
    elseif c.action and ISTimedActionQueue.hasAction(c.action) then ISTimedActionQueue.clear(c.npc) end
    releaseBench(c)
    if c.body and not Driver.stop(c.binding,c.body) then return false end
    if not c.body then Driver.stop(c.binding) end
    if contexts[id]==c then contexts[id]=nil end
    if reason=="SAVE" and not r.uncertain then
        candidates[id]={actor=c.actor,record=r,root=c.root,generation=r.generation,command=c.returnOnly and "return" or "resume"}
    end
    if r.chain and not r.uncertain and (reason=="MATERIALS_UNAVAILABLE" or reason=="TOOLS_UNAVAILABLE"
        or reason=="CHAIN_INVENTORY_UNKNOWN" or reason=="ITEM_RESERVED" or reason=="INVENTORY_CHANGED") then
        waiting[id]={actor=c.actor,record=r,root=c.root,generation=r.generation,revision=inventoryRevision}
    end
    changed(c,"PAUSED "..tostring(reason))
    return true
end
function Production.pauseAll(reason)
    if reason~="SAVE" then candidates,pending={},{} end
    local ids={} for id in pairs(contexts) do ids[id]=true end
    for id in pairs(requests) do ids[id]=true end
    for id in pairs(ids) do Production.pause(reason,id) end
end
function Production.reset() Production.pauseAll("WORLD_RESET") contexts,candidates,pending,requests={},{},{},{} waiting={} inventoryDirty=false end
local function context(actor,binding,r,entry,object,body)
    local c={actor=actor,npc=binding.handle,binding=binding,record=r,entry=entry,object=object,root=Registry.data(),generation=r.generation,body=body}
    c.valid=function()
        return (not body or body.current()) and contexts[r.npcId]==c and not c.cancelled and c.root==Registry.data() and record(r.npcId)==r
            and r.generation==c.generation and r.state=="RUNNING" and not actor:isDead()
            and actor:getUsername()==r.requester and Driver.valid(binding)
            and c.npc:getBodyDamage():getOverallBodyHealth()>=95
            and Supply.entry(actor,c.npc,c.object,r.settlementId)~=nil and Store.validNative(r,c.token)
    end
    c.changed=function(message) changed(c,message) end
    return c
end
local function makePlan(c,select)
    if c.record.chain and c.record.chain.index==0 and not c.returnOnly then
        local r=c.record
        c.chainRequest=require("EmberRoutesProbe/ProductionChain").new(c.actor,c.npc,c.entry,r.recipeId,r.requested,c.object,r.id)
        c.planning=true return true
    end
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
-- Every stage shares one task/token. No child completion releases intermediate originals.
local function activateNode(c,index)
    local r=c.record local node=r.chain.nodes[index]
    if not node then return nil,"CHAIN_RECORD_INVALID" end
    local spec,reason=Recipe.read(node.recipeId)
    if not spec or spec.signature~=node.signature then return nil,reason or "RECIPE_CHANGED" end
    local object
    if spec.surface then
        object,reason=Surfaces.resolve(node.location,node.benchId)
        if not object then return nil,reason or "CRAFT_SURFACE_REQUIRED" end
    end
    local entry,why=Supply.entry(c.actor,c.npc,object,r.settlementId) if not entry then return nil,why end
    local proposed={} for k,v in pairs(r) do proposed[k]=v end
    proposed.recipeId=node.recipeId proposed.signature=node.signature proposed.product=spec.product proposed.recipeName=spec.name
    proposed.requested=node.requested proposed.target=node.requested proposed.unitYield=spec.yield proposed.produced=0 proposed.delivered=0
    proposed.benchId=node.benchId proposed.surface=node.location proposed.phase="PLANNING" proposed.unitMade=false
    local ok,failed=Store.replaceNative(r,c.token,proposed) if not ok then return nil,failed end
    for _,key in ipairs({"recipeId","signature","product","recipeName","requested","target","unitYield","produced","delivered","phase","unitMade"}) do r[key]=proposed[key] end
    r.benchId=proposed.benchId r.surface=proposed.surface r.chain.index=index
    c.entry=entry c.object=object c.returned=nil c.route=nil c.inputs=nil
    return makePlan(c,true)
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
    local item,reason,source=find(c,asset)
    if not item then
        changed(c,'ASSET_BLOCKED item='..tostring(asset.id)..' source='..tostring(asset.source)
            ..' destination='..tostring(asset.destination)..' reason='..tostring(reason))
        return nil,reason
    end
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
    local r=c.record releaseBench(c)
    if r.uncertain then r.state="RECONCILE_REQUIRED" r.phase=r.state r.reason="RECONCILE_REQUIRED"
    else
        r.state=c.returnOnly and "CANCELLED" or "DONE" r.phase=r.state
        if not c.returnOnly and r.reason~="TARGET_REACHED" then r.reason=nil end
        Store.finishNative(r)
        r.released=true
        inventoryChanged()
    end
    r.generation=r.generation+1 c.completed=true c.closedGeneration=r.generation contexts[r.npcId]=nil changed(c,r.state)
end
local function prepare(c)
    if c.chainRequest then
        local result,reason=c.chainRequest:step()
        if not result then
            if reason then c.record.chain.blocker=c.chainRequest.blocker end
            return nil,reason
        end
        c.chainRequest=nil
        local r=c.record local proposed={} for k,v in pairs(r) do proposed[k]=v end
        proposed.held=result.assets
        local ok,why=Store.replaceNative(r,c.token,proposed) if not ok then return nil,why end
        r.chain.nodes=result.nodes
        r.chain.blocker=nil
        return activateNode(c,1)
    end
    local ready,reason=c.plan:step(32)
    if not ready then return nil,reason end
    local r=c.record
    if r.phase=="PLANNING" and not c.returnOnly then
        local proposed={} for key,value in pairs(r) do proposed[key]=value end
        proposed.materials,proposed.tools,proposed.outputs=c.plan.materials,c.plan.tools,{}
        if r.chain then
            local active={} for _,name in ipairs({"materials","tools"}) do for _,asset in ipairs(proposed[name]) do active[asset.id]=true end end
            proposed.held={}
            for _,asset in ipairs(r.held) do if not active[asset.id] then proposed.held[#proposed.held+1]=asset end end
        end
        local weight,consumed=0,0
        local bySlot={} for _,input in ipairs(c.spec.inputs) do bySlot[input.slot]=input end
        for _,name in ipairs({"materials","tools"}) do
            for _,asset in ipairs(proposed[name]) do
                local location=c.plan.locations[asset.id]
                if not location or not location.item or Store.owner(asset.id) and Store.owner(asset.id).taskId~=r.id then return nil,"ITEM_RESERVED" end
                if location.endpoint and not Actions.inRoot(location.item,location.endpoint.container,asset.id) then return nil,"INVENTORY_CHANGED" end
                if location.item:getContainer()~=c.npc:getInventory() then weight=weight+location.item:getUnequippedWeight() end
                consumed=consumed+Carry.consumed(location.item,bySlot[asset.slot])
            end
        end
        if not fits(c,weight,consumed,c.spec.outputWeight) then return nil,"CAPACITY_UNAVAILABLE" end
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
        for _,name in ipairs({"materials","outputs","tools","held"}) do
            if name~="materials" or not r.unitMade then
                for _,asset in ipairs(r[name] or {}) do
                    if not c.returned[asset.id] and not (name=='outputs' and asset.delivered) then
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
    if Production.earlySettleCheck and Production.earlySettleCheck(c) then
        r.reason="TARGET_REACHED"
    elseif r.produced<r.target then
        local proposed={} for key,value in pairs(r) do proposed[key]=value end
        proposed.materials,proposed.outputs={},{}
        if r.chain and r.chain.index<#r.chain.nodes then
            proposed.held={} for _,asset in ipairs(r.held) do proposed.held[#proposed.held+1]=asset end
            for _,asset in ipairs(r.outputs) do proposed.held[#proposed.held+1]=asset end
        end
        local ok,why=Store.replaceNative(r,c.token,proposed) if not ok then return nil,why end
        r.unitMade=false r.phase="PLANNING" changed(c,"NEXT_UNIT")
        local ready,reason=makePlan(c,true) if not ready then return nil,reason end return nil
    end
    if r.delivered~=r.target and r.reason~="TARGET_REACHED" then return nil,"RECONCILE_REQUIRED" end
    c.returned=c.returned or {}
    for _,tool in ipairs(r.tools) do
        if not c.returned[tool.id] then
            local action,reason,movement=deliver(c,tool,function() c.returned[tool.id]=true end)
            if action~=false then return action,reason,movement end
        end
    end
    if r.reason~="TARGET_REACHED" and r.chain and r.chain.index<#r.chain.nodes then
        local proposed={} for k,v in pairs(r) do proposed[k]=v end
        proposed.held={} for _,asset in ipairs(r.held) do proposed.held[#proposed.held+1]=asset end
        for _,name in ipairs({"outputs","tools"}) do
            for _,asset in ipairs(r[name]) do
                local item,reason=find(c,asset) if not item then return nil,reason end
                proposed.held[#proposed.held+1]={id=asset.id,fullType=item:getFullType(),destination=asset.destination}
            end
        end
        proposed.materials,proposed.tools,proposed.outputs={},{},{}
        local ok,reason=Store.replaceNative(r,c.token,proposed) if not ok then return nil,reason end
        local ready,why=activateNode(c,r.chain.index+1) if not ready then return nil,why end
        changed(c,"CHAIN_NEXT") return nil
    end
    finish(c) return nil
end
local function tick(c)
    if not c.valid() then return "CARRIER_OR_OWNER_CHANGED" end
    if not c.returnOnly and not fits(c) then return "CAPACITY_UNAVAILABLE" end
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
        c.moving=Transfer.move({npc=c.npc,actor=c.actor,job=c.record,body=c.body},movement) c.started=now
        local state,why=c.moving.start() if state=="FAILED" then return why or "MOVE_FAILED" end
    elseif action then
        c.action=action c.started=now
        if c.body then
            if not c.body.add(action) then return 'CONTROL_REQUIRED' end
        else ISTimedActionQueue.add(action) end
    end
end
function Production.tick(id)
    local c=contexts[id] if not c then return end
    local ok,reason=pcall(tick,c)
    if not ok then changed(c,"ERROR "..tostring(reason)) reason="ERROR" end
    if reason then Production.pause(reason,id) end
end
local function execute(actor,command,object,id,options,body,validateOnly)
    if not Probe.ready or not Probe.hasJava() then return Probe.unavailableCode() end
    if isClient() or isServer() then return "SP_ONLY" end
    options=options or {recipeId="Base.CarveWoodenFork",quantity=1}
    if command=="stop" then Work.pause("USER",id) return "PAUSED" end
    if Work.executing(id) then return "BUSY" end
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
        local entry,reason=Supply.entry(actor,npc,object,options.settlementId) if not entry then return reason end
        if options.settlementId and entry.id~=options.settlementId then return "SETTLEMENT_MISMATCH" end
        if validateOnly then return true end
        if options.nonPreemptive then
            if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
        else
            if not body then Probe.cancelAll("ACTION_ORDER",id) end
            if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
        end
        local benchId
        if object then local data=object:getModData() data.EmberRoutesCraftProbeBenchId=data.EmberRoutesCraftProbeBenchId or Registry.id() benchId=data.EmberRoutesCraftProbeBenchId end
        local taskId=options.taskId or Registry.id()
        r={format=3,id=taskId,npcId=id,requester=actor:getUsername(),generation=1,state="RUNNING",phase="PLANNING",
            recipeId=spec.id,signature=spec.signature,product=spec.product,recipeName=spec.name,unitYield=spec.yield,
            requested=n,target=math.ceil(n/spec.yield)*spec.yield,produced=0,delivered=0,materials={},tools={},outputs={},
            settlementId=entry.id,benchId=benchId,surface=object and Surfaces.location(object) or nil,released=false}
        if options.origin then r.origin=options.origin end
        if options.orderId then r.orderId=options.orderId end
        if options.chain then
            local goal={} for _,key in ipairs({"recipeId","recipeName","product","signature","requested","target","unitYield","produced","delivered"}) do goal[key]=r[key] end
            r.chain={format=1,index=0,nodes={},goal=goal} r.held={}
        end
        local token,reason=Store.claimNative(r) if not token then return reason end
        local published,why=require('EmberRoutesProbe/BusinessJobs').publishCraft(r)
        if not published then Store.finishNative(r) return why end
        local c=context(actor,binding,r,entry,object,body) c.token=token contexts[id]=c
        local ready,why=makePlan(c,true)
        if not ready then Production.pause(why,id) return why end
        if not body then Work.wake(id) end
        changed(c,"STARTED "..r.recipeId.." target="..r.target) return "STARTED"
    end
    if not r or r.format~=3 or r.released then return "NO_CARGO" end
    if r.requester~=actor:getUsername() then return "OWNER_CHANGED" end
    if command~="resume" and command~="return" then return "INVALID_COMMAND" end
    if command=="resume" and (r.uncertain or r.phase=="COMMITTING") then return "RECONCILE_REQUIRED" end
    if command=="resume" and not r.unitMade and r.surface then
        local resolved,why=Surfaces.resolve(r.surface,r.benchId) if not resolved then return why end object=resolved
    else object=nil end
    local entry,reason=Supply.entry(actor,npc,object,r.settlementId) if not entry then return reason end
    if validateOnly then return true end
    if not body then Probe.cancelAll("ACTION_ORDER",id) end
    if not npc:getCharacterActions():isEmpty() then return "NATIVE_ACTION_BUSY" end
    r.generation=r.generation+1 r.state="RUNNING" r.reason=nil
    local token,why=Store.claimNative(r)
    if not token then r.state="PAUSED" r.reason=why return why end
    local c=context(actor,binding,r,entry,object,body) c.token=token c.returnOnly=command=="return" contexts[id]=c
    local ready,failed=makePlan(c,r.phase=="PLANNING" and not c.returnOnly)
    if not ready then Production.pause(failed,id) return failed end
    if not body then Work.wake(id) end
    changed(c,"RESUME "..command) return command=="return" and "RETURN_STARTED" or "RESUME_STARTED"
end
function Production.execute(actor,command,object,id,options)
    if Probe.controlledExecution~=true or (command~='run' and command~='resume' and command~='return') then
        return execute(actor,command,object,id,options)
    end
    local runtime=Runtime.current()
    if not runtime then return 'ADMISSION_CLOSED' end
    local root=Registry.data()
    local previous=record(id)
    local generation=previous and previous.generation
    local copy={} for key,value in pairs(options or {recipeId='Base.CarveWoodenFork',quantity=1}) do copy[key]=value end
    if copy.origin then local origin={} for key,value in pairs(copy.origin) do origin[key]=value end copy.origin=origin end
    local jobId=command=='run' and (copy.taskId or Registry.id()) or previous and previous.id
    if not jobId then return 'NO_CARGO' end
    if command=='run' then copy.taskId=jobId end
    local c
    local handle,why=runtime:submit({npcId=id,jobId=jobId,kind='PRODUCTION',binding=Driver.bindId(actor,id),
        nonPreemptive=copy.nonPreemptive==true,captureStop=true,reconcileErrors=true,
        validate=function()
            return Registry.data()==root and record(id)==previous and (not previous or previous.generation==generation)
                and execute(actor,command,object,id,copy,nil,true)==true
        end,
        start=function(body)
            local value=execute(actor,command,object,id,copy,body)
            c=contexts[id]
            if c and c.record.id==jobId then return true end
            return false,value,'UNCHANGED'
        end,
        tick=function() Production.tick(id) end,
        finished=function() return c and contexts[id]~=c end,
        stopAdapter=function(controller,ticket) return Production.stopAdapter(id,controller,ticket) end,
        persistFailure=function(fact,reason)
            local r=record(id)
            if Registry.data()~=root then return false end
            if fact.effects=='UNKNOWN' then
                if not r or r.id~=jobId then return false end
                r.uncertain=true r.phase='RECONCILE_REQUIRED' r.reason=reason Signals.changed(id)
            end
            return true
        end})
    if handle then requests[id]={handle=handle,runtime=runtime,root=root,jobId=jobId} end
    return handle and 'QUEUED' or why,handle
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
            local ok,why=pcall(Production.execute,candidate.actor,candidate.command,nil,id,{nonPreemptive=true})
            if not ok then r.reason="ERROR" Log.write("PRODUCTION",tostring(why)) Signals.changed(id) end
        end
        return true
    end
    if inventoryDirty then
        for id,candidate in pairs(waiting) do
            if candidate.revision~=inventoryRevision then
                waiting[id]=nil local r=candidate.record
                if candidate.root==Registry.data() and record(id)==r and r.generation==candidate.generation and not r.uncertain then
                    Production.execute(candidate.actor,"resume",nil,id,{nonPreemptive=true})
                end
                return true
            end
        end
        inventoryDirty=false
    end
    return false
end
function Production.status(r)
    local result={id=r.id,npcId=r.npcId,settlementId=r.settlementId,state=r.state,phase=r.phase,reason=r.reason,released=r.released,
        uncertain=r.uncertain==true,made=r.unitMade==true,resumable=not r.released and not r.uncertain and r.phase~="COMMITTING",
        recipeId=r.recipeId,recipeName=r.recipeName,product=r.product,requested=r.requested,target=r.target,produced=r.produced,delivered=r.delivered,
        surfaceRequired=r.surface~=nil,surface=r.surface and {x=r.surface.x,y=r.surface.y,z=r.surface.z} or nil}
    if r.chain then
        local goal=r.chain.goal
        result.chainIndex=r.chain.index result.chainTotal=#r.chain.nodes result.stepName=r.recipeName
        if r.chain.blocker then result.stepName=r.chain.blocker.recipeName end
        for _,key in ipairs({"recipeId","recipeName","product","requested","target"}) do result[key]=goal[key] end
        result.produced=r.chain.index==#r.chain.nodes and r.produced or 0
        result.delivered=r.chain.index==#r.chain.nodes and r.delivered or 0
    end
    return result
end
function Production.findRootOrders(settlementId,fullType)
    local probes=require('EmberRoutesProbe/BusinessJobs').crafts()
    if not probes then return {hasManualOrder=false,orders={}} end
    local orders={}
    local hasManual=false
    for npcId,r in pairs(probes) do
        if r.format==3 and not r.released and not r.uncertain and (not settlementId or r.settlementId==settlementId) then
            local product=r.chain and r.chain.goal and r.chain.goal.product or r.product
            if product==fullType then
                orders[#orders+1]=r
                if not r.origin or r.origin.kind~="MAINTAIN_STOCK" then
                    hasManual=true
                end
            end
        end
    end
    return {hasManualOrder=hasManual,orders=orders}
end
return Production
