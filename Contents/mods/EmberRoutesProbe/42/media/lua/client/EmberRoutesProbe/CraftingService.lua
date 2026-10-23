local Probe=require "EmberRoutesProbe/Boot"
local Craft=require "EmberRoutesProbe/CraftProbe"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Driver=require "EmberRoutesProbe/Driver"
local Work=require "EmberRoutesProbe/Work"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Recipes=require "EmberRoutesProbe/ProductionRecipe"
local Log=require "EmberRoutesProbe/Log"
local Service={}
local watchers,defaults,world,dirty={},{},nil,false
local browsers,previews={},{}
local function notify(token,collection,value)
    local ok,why=pcall(token.callback,value)
    if not ok then
        collection[token]=nil if token.request then token.request:cancel() end
        Log.write("CRAFTING_VIEW",tostring(why))
    end
end
local function changed() dirty=true end
Signals.watch(changed)
Registry.listeners[#Registry.listeners+1]=changed
Ledger.listeners[#Ledger.listeners+1]=changed
local function invalidate()
    for token in pairs(previews) do token.dirty=true end
end
Signals.watch(invalidate)
Registry.listeners[#Registry.listeners+1]=invalidate
if Registry.inventoryListeners then Registry.inventoryListeners[#Registry.inventoryListeners+1]=invalidate end
Ledger.listeners[#Ledger.listeners+1]=invalidate
local function currentWorld()
    local current=Registry.data()
    if current~=world then world=current defaults={} end
    return current
end
function Service.selectSurface(actor,object)
    currentWorld()
    local selected,reason=Surfaces.remember(actor,object)
    if not selected then return nil,reason end
    defaults[selected.settlementId]=selected.id changed() invalidate()
    return selected
end
-- Detached scalar snapshots only; this does not read inventories or scan furniture.
function Service.status(actor,id)
    currentWorld()
    local entry,reason=Ledger.view(actor,id)
    if not entry then return {workers={},surfaces={},reason=reason} end
    local result={workers={},surfaces=Surfaces.list(entry),surfaceId=defaults[id]}
    if not Probe.ready or not Probe.hasJava() then result.reason="DRIVER_UNAVAILABLE" return result end
    for i=0,EmberRoutesProbeJava.workerCount()-1 do
        local npcId=EmberRoutesProbeJava.workerIdAt(i)
        local binding=Driver.bindId(actor,npcId)
        local status=Craft.status(npcId)
        if (binding and Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()))
            or (status and status.settlementId==id) then
            result.workers[#result.workers+1]={id=npcId,name=binding and binding.handle:getFullName() or string.sub(npcId,1,8),
                order=status,busy=Work.busy(npcId),orderBusy=Craft.busy(npcId)}
        end
    end
    table.sort(result.workers,function(a,b) return a.id<b.id end)
    return result
end
function Service.recipes(actor,id)
    if not Ledger.view(actor,id) then return {} end
    if not Probe.ready or not Probe.hasJava() then return {} end
    return Recipes.examples()
end
function Service.describe(id) return require("EmberRoutesProbe/CraftingCatalog").describe(id) end
function Service.chooseSurface(actor,id,npcId)
    local entry=Ledger.view(actor,id) if not entry then return nil end
    local binding=type(npcId)=="string" and Driver.bindId(actor,npcId) or nil
    for _,surface in ipairs(Surfaces.list(entry)) do
        local object=Surfaces.resolve(surface,surface.id)
        if object and (not object:getUsingPlayer() or binding and object:getUsingPlayer()==binding.handle) then return surface.id end
    end
end
function Service.watchCatalog(actor,id,query,callback)
    local token={actor=actor,id=id,query=query,callback=callback,world=currentWorld()}
    browsers[token]=true
    return function() browsers[token]=nil end
end
function Service.preview(actor,id,npcId,recipeId,quantity,surfaceId,callback)
    local token={actor=actor,id=id,npcId=npcId,recipeId=recipeId,quantity=quantity,surfaceId=surfaceId,
        callback=callback,world=currentWorld(),dirty=true}
    previews[token]=true
    return function() if token.request then token.request:cancel() end previews[token]=nil end
end
function Service.readTick()
    if not Probe.ready or not Probe.hasJava() then return end
    local any=false for _ in pairs(browsers) do any=true break end
    if any then
            local catalog=require "EmberRoutesProbe/CraftingCatalog" catalog.step()
            for token in pairs(browsers) do
                if token.world~=currentWorld() or not Ledger.view(token.actor,token.id) then
                    browsers[token]=nil notify(token,browsers,{rows={},categories={},reason="WORLD_RESET",loading=false,page=1,pages=1})
                else
                    local q=token.query local result=catalog.query(q.search,q.category,q.unsupported,q.page,q.size)
                    local key=result.revision..":"..result.page
                    if token.key~=key then token.key=key notify(token,browsers,result) end
                end
            end
    end
    -- One globally bounded query slice per tick; dirty in-flight work completes before restarting.
    local token
    for candidate in pairs(previews) do if not candidate.delivered or candidate.dirty then token=candidate break end end
    if token then
        if token.world~=currentWorld() or not Ledger.view(token.actor,token.id) then
            if token.request then token.request:cancel() end previews[token]=nil
            notify(token,previews,{state="BLOCKED",conditions={"WORLD_RESET"},counts={}}) return
        end
        if token.dirty and (not token.request or token.delivered) then
            if token.request then token.request:cancel() end
            token.request=require("EmberRoutesProbe/CraftingPreview").new(token.actor,token.id,token.npcId,token.recipeId,token.quantity,token.surfaceId)
            token.dirty=false token.delivered=false notify(token,previews,{state="CHECKING",conditions={},counts={}})
        end
        if previews[token] then
            local result=token.request:step()
            if result then
                token.delivered=true
                if not token.dirty then notify(token,previews,result) end
            end
        end
    end
end
local function command(actor,id,npcId,command,surfaceId,recipeId,quantity)
    if type(npcId)~="string" or npcId=="" then return "NO_WORKER" end
    local entry,reason=Ledger.view(actor,id)
    if not entry then return reason end
    local status=Craft.status(npcId)
    if status and not status.released and status.settlementId~=id then return "OTHER_TASK_RETAINED" end
    local object
    if command=="run" or command=="teach" then
        local spec
        if recipeId then spec,reason=Recipes.read(recipeId) if not spec then return reason end end
        if not spec or spec.surface then
            local position=(Registry.data().craftSurfaces or {})[surfaceId]
            if not position or not Geometry.inside(entry,position.x,position.y) then return "CRAFT_SURFACE_REQUIRED" end
            object,reason=Surfaces.resolve(position,surfaceId)
            if not object then return reason end
        end
    elseif command=="resume" then
        -- A selected replacement is not permission to substitute an order's surface.
        local record=Craft.record(npcId)
        if record and not record.surface and record.benchId and surfaceId==record.benchId then
            object,reason=Surfaces.resolve((Registry.data().craftSurfaces or {})[surfaceId],surfaceId)
            if not object then return reason end
        end
    elseif command~="stop" and command~="return" then return "INVALID_COMMAND" end
    local options=recipeId and (command=="run" or command=="teach") and {recipeId=recipeId,quantity=quantity==nil and 1 or quantity,chain=true} or nil
    local result=Craft.execute(actor,command,object,npcId,true,options) changed() invalidate() return result
end
function Service.command(actor,id,npcId,action,surfaceId,recipeId,quantity)
    if Probe.publicDispatch and action=='run' then return 'PUBLIC_ORDER_ENTRY_REQUIRED' end
    if Probe.publicDispatch and action=='teach' then return 'READ_BOOK_REQUIRED' end
    local result=command(actor,id,npcId,action,surfaceId,recipeId,quantity)
    Log.write('CRAFTING_COMMAND','npc='..tostring(npcId)..' command='..tostring(action)..' result='..tostring(result))
    return result
end
function Service.watch(actor,id,callback)
    local token={actor=actor,id=id,callback=callback,world=currentWorld()}
    watchers[token]=true changed()
    return function() watchers[token]=nil end
end
function Service.tick()
    if not dirty then return end dirty=false
    for token in pairs(watchers) do
        local snapshot=token.world~=Registry.data() and {reason="WORLD_RESET",workers={},surfaces={}}
            or Service.status(token.actor,token.id)
        local ok=pcall(token.callback,snapshot)
        if not ok or snapshot.reason=="WORLD_RESET" then watchers[token]=nil end
    end
end
Probe.tickCraftView=Service.tick
local event=Events.OnTickEvenPaused or Events.OnTick
if event then event.Add(Service.readTick) end
if Events.OnContainerUpdate then Events.OnContainerUpdate.Add(invalidate) end
return Service
