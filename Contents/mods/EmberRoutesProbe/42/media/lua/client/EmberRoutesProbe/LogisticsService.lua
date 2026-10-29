local Probe=require "EmberRoutesProbe/Boot"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"
local Store=require "EmberRoutesProbe/LogisticsStore"
local Work=require "EmberRoutesProbe/Work"
local Driver=require "EmberRoutesProbe/Driver"
local Companion=require "EmberRoutesProbe/Companion"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Sort=require "EmberRoutesProbe/SortPolicy"
local Planner=require "EmberRoutesProbe/LogisticsPlanner"
local Schedule=require "EmberRoutesProbe/LaborSchedule"
local Log=require "EmberRoutesProbe/Log"
local Signals=require "EmberRoutesProbe/LaborSignals"
local Service={BUDGET=64}
local contexts,schedule={},Schedule.new()
local watchers,dirty={},{}
local function changed(id)
    if id and watchers[id] then dirty[id]=true
    elseif not id then for key in pairs(watchers) do dirty[key]=true end end
end
Signals.watch(function() changed() end)
local replanReasons={DESTINATION_FULL=true,CAPACITY_RESERVED=true,PRODUCER_RULE_CHANGED=true,FILTER_REJECTED=true,
    CONTAINER_REMOVED=true,CONTAINER_CHANGED=true,CONTAINER_PRIVATE=true,CONTAINER_UNLOADED=true}
local function log(value) Log.write("LOGISTICS",value) end
local function members(entry,record)
    for _,id in ipairs({record.source,record.destination}) do
        local position=Registry.describe(id)
        if not position or not Geometry.inside(entry,position.x,position.y) then return false end
    end
    return true
end
local function check(context)
    local record=context.job local ctx=contexts[record.settlementId]
    if not ctx or not ctx.running then return false,"LOGISTICS_STOPPED" end
    local entry=Ledger.get(record.settlementId)
    if not entry or entry.factionId~=Ledger.data().factionId or record.format~=2 and not members(entry,record) then return false,"SETTLEMENT_CHANGED" end
    if not ctx.public and not Store.get(entry.id).workers[record.npcId] then return false,"WORKER_REMOVED" end
    if record.format~=2 and Registry.logistics(context.destination)~="STORAGE" then return false,"PRODUCER_RULE_CHANGED" end
    return true
end
Producers.register("LOGISTICS",{
    check=check,
    transfer=function(context,item,from)
        if not check(context) then return false end
        if context.job.format==2 and from==context.npc:getInventory() then return true end
        if not context.source then return false end
        if from~=context.source.container then return true end -- Held originals may finish delivery after a mode change.
        if Producers.freeCarry(context.npc)<item:getUnequippedWeight() then return false end
        local mode=Sort.source(Registry.logistics(context.source),Store.get(context.job.settlementId),
            Registry.filter(context.source.object,context.source.container),item)
        return mode~=nil and mode==context.job.sourceMode
    end,
})
local function roster(ctx)
    ctx.workers={}
    for id in pairs(Store.get(ctx.id).workers) do ctx.workers[#ctx.workers+1]=id end
    table.sort(ctx.workers) ctx.cursor=0 ctx.plan=nil
end
function Service.running(id) return contexts[id] and contexts[id].running or false end
function Service.invalidate(id)
    changed()
    local position=id and Registry.describe(id)
    for key,ctx in pairs(contexts) do
        local entry=Ledger.get(key)
        if not id or ctx.members[id] or (position and entry and Geometry.inside(entry,position.x,position.y)) then
            ctx.plan=nil ctx.publicPlans={} ctx.publicWait={} ctx.cache=nil ctx.nextTick=0 ctx.dirty=true
        end
        if key==id then roster(ctx) ctx.publicPlans={} ctx.publicWait={} ctx.cache=nil ctx.nextTick=0 end
    end
end
function Service.stop(actor,id)
    local entry,reason=Ledger.view(actor,id)
    if not entry then return reason end
    if Probe.publicDispatch then Store.get(id).suspended=true end
    local ctx=contexts[id]
    if ctx then ctx.running=false ctx.plan=nil ctx.cache=nil ctx.members={} ctx.actor=nil schedule:remove(id) end
    for npcId in pairs(Store.get(id).workers) do
        local record=Work.record(npcId)
        if record and record.producer=="LOGISTICS" and record.settlementId==id then Work.pause("LOGISTICS_STOPPED",npcId) end
    end
    changed(id) log("STOP settlement="..id) return "STOPPED"
end
function Service.start(actor,id)
    local entry,reason=Ledger.view(actor,id)
    if not entry then return reason end
    if Probe.publicDispatch then Store.get(id).suspended=false changed(id) return 'STARTED' end
    if not Probe.ready or Probe.enabled==false or not Probe.hasJava() then return "DRIVER_UNAVAILABLE" end
    local settings=Store.get(id)
    if not settings.intake and not settings.tidy then return "MODES_DISABLED" end
    local ctx={id=id,actor=actor,running=true,nextTick=0,reason="SCANNING",members={},attempts={},dirty=true}
    roster(ctx)
    if #ctx.workers==0 then return "NO_WORKERS" end
    for _,npcId in ipairs(ctx.workers) do Work.allowAutomation(npcId) end
    contexts[id]=ctx schedule:add(id)
    changed(id) log("START settlement="..id.." workers="..#ctx.workers) return "STARTED"
end
function Service.addNearby(actor,id)
    local entry,reason=Ledger.view(actor,id)
    if not entry then return reason end
    local added=0
    for i=0,EmberRoutesProbeJava.workerCount()-1 do
        local npcId=EmberRoutesProbeJava.workerIdAt(i) local binding=Driver.bindId(actor,npcId)
        if binding and Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) and not Work.busy(npcId)
            and not Work.hasCargo(actor,npcId) and binding.handle:getCharacterActions():isEmpty()
            and require('EmberRoutesProbe/MembershipService').check(npcId,'WORK',
                {x=binding.handle:getX(),y=binding.handle:getY(),z=binding.handle:getZ(),scopeId=id}).allowed then
            local record=Work.record(npcId)
            if not record or record.state=="DONE" or record.producer=="LOGISTICS" then
                local result=Store.worker(actor,id,npcId,true)
                if result then added=added+1 end
            end
        end
    end
    Service.invalidate(id) log("POOL settlement="..id.." added="..added)
    return added>0 and "WORKERS_ADDED" or "NO_IDLE_WORKERS"
end
function Service.removeWorker(actor,id,npcId)
    local result,reason=Store.worker(actor,id,npcId,false)
    if not result then return reason end
    local record=Work.record(npcId)
    if record and record.producer=="LOGISTICS" and record.settlementId==id then Work.pause("WORKER_REMOVED",npcId) end
    Service.invalidate(id) return "WORKER_REMOVED"
end
local function advance(ctx)
    local now=getTimestampMs()
    if now<ctx.nextTick then return end ctx.nextTick=now+100
    local entry=Ledger.get(ctx.id)
    if not entry or ctx.actor:isDead() or entry.factionId~=Ledger.data().factionId then
        ctx.running=false ctx.plan=nil schedule:remove(ctx.id) ctx.reason="SETTLEMENT_CHANGED" return
    end
    local settings=Store.get(ctx.id)
    if #ctx.workers==0 then ctx.reason="NO_WORKERS" return end
    local npcId=ctx.planNpc
    if not ctx.plan then ctx.cursor=ctx.cursor%#ctx.workers+1 npcId=ctx.workers[ctx.cursor] end
    local binding=Driver.bindId(ctx.actor,npcId)
    if not binding or not settings.workers[npcId] or not Work.automationAllowed(npcId) or Work.busy(npcId)
        or not require('EmberRoutesProbe/MembershipService').check(npcId,'WORK',
            {x=binding.handle:getX(),y=binding.handle:getY(),z=binding.handle:getZ(),scopeId=ctx.id}).allowed
        or not binding.handle:getCharacterActions():isEmpty()
        or binding.handle:getBodyDamage():getOverallBodyHealth()<95 then ctx.plan=nil ctx.reason="WAITING_WORKER" return end
    local record=Work.record(npcId)
    if record and record.state~="DONE" then
        ctx.plan=nil
        if record.producer=="LOGISTICS" and record.settlementId==ctx.id and replanReasons[record.reason]
            and Work.discardAutomatic(ctx.actor,npcId) then
            ctx.nextTick=now+2000 ctx.reason="REPLANNING" return
        end
        local attempt=record.id..":"..tostring(record.generation)
        if record.producer=="LOGISTICS" and record.settlementId==ctx.id
            and (ctx.attempts[npcId]==nil or (record.reason=="SAVE" and ctx.attempts[npcId]~=attempt)) then
            local result=Work.resumeFor(ctx.actor,npcId)
            ctx.attempts[npcId]=record.id..":"..tostring(record.generation) ctx.reason=result
        else ctx.reason="TASK_REQUIRES_ATTENTION" end
        return
    end
    if record and Work.hasCargo(ctx.actor,npcId) then ctx.plan=nil ctx.reason="CARGO_RETAINED_RESUME_FIRST" return end
    if not Geometry.inside(entry,binding.handle:getX(),binding.handle:getY()) then ctx.plan=nil ctx.reason="NPC_OUTSIDE_SETTLEMENT" return end
    if not ctx.plan then
        if ctx.cache and now-(ctx.cacheAt or 0)>10000 then ctx.cache=nil end
        local plan,reason=Planner.new(entry,settings,binding.handle,ctx.cache)
        if not plan then ctx.reason=reason return end
        ctx.plan=plan ctx.planNpc=npcId ctx.members={}
        for _,containerId in ipairs(plan.ids) do ctx.members[containerId]=true end
    end
    local intent,state,_,reason=ctx.plan:step(Service.BUDGET)
    if ctx.plan.compiled and ctx.cache~=ctx.plan.compiled then ctx.cache=ctx.plan.compiled ctx.cacheAt=now end
    if intent then
        ctx.plan=nil
        local result=Work.assign(ctx.actor,npcId,intent) ctx.reason=result
        local assigned=Work.record(npcId)
        ctx.attempts[npcId]=assigned and (assigned.id..":"..tostring(assigned.generation)) or "attempted"
        if result~='QUEUED' and not string.find(result,"^STARTED") then ctx.nextTick=now+2000 end
    elseif state=="DONE" then
        if ctx.lastWait~=reason then
            local s=ctx.plan.stats
            log("WAIT settlement="..ctx.id.." npc="..npcId.." reason="..reason
                .." accessible="..s.accessible.." inputs="..s.inputs.." storage="..s.storage
                .." scanned="..ctx.plan.read.." candidates="..s.candidates.." protected="..s.protected.." claimed="..s.claimed)
            ctx.lastWait=reason
        end
        ctx.plan=nil ctx.reason=reason ctx.nextTick=now+2000
    elseif state=="CHANGED" then ctx.plan=nil ctx.reason=reason ctx.nextTick=now+500
    elseif state=="FAILED" then ctx.running=false ctx.plan=nil ctx.reason=reason schedule:remove(ctx.id)
    else ctx.reason="SCANNING" end
end
function Service.preparePublic(actor,entry,recovery)
    local settings=Store.get(entry.id)
    if settings.suspended or not recovery and not settings.intake and not settings.tidy then return nil end
    local ctx=contexts[entry.id]
    if not ctx or not ctx.public then
        ctx={id=entry.id,actor=actor,running=true,public=true,publicPlans={},publicWait={},members={}} contexts[entry.id]=ctx
    end
    ctx.running=true ctx.actor=actor
    return ctx
end
function Service.publicOffer(actor,entry,npc)
    local ctx=Service.preparePublic(actor,entry) if not ctx then return nil end
    local settings=Store.get(entry.id)
    local id=EmberRoutesProbeJava.carrierId(npc)
    local now=getTimestampMs()
    if now<(ctx.publicWait[id] or 0) then return nil end
    local plan=ctx.publicPlans[id]
    if not plan then plan=Planner.new(entry,settings,npc) ctx.publicPlans[id]=plan end
    if not plan then ctx.publicWait[id]=now+2000 return nil end
    local intent,state=plan:step(Service.BUDGET)
    if intent or state~='WAIT' then
        ctx.publicPlans[id]=nil
        -- An exhausted search is not new work. Events wake it immediately;
        -- bounded retry also detects vanilla/other-mod inventory changes.
        if not intent then ctx.publicWait[id]=now+(state=='CHANGED' and 500 or 2000) end
    end
    return intent
end
local recoveryWorld,recoveryIds,recoveryCursor,recoveryAt,recoveryRefresh=nil,{},0,0,0
local recoveryWait={}
function Service.recover()
    if not Probe.ready or Probe.enabled==false or not Probe.hasJava() or isClient() or isServer() then return end
    local now=getTimestampMs() if now<recoveryAt then return end recoveryAt=now+100
    local world=Registry.data()
    if world~=recoveryWorld then recoveryWorld=world recoveryWait={} recoveryRefresh=0 end
    local rt=require('EmberRoutesProbe/TaskRuntime').current()
    if rt and not rt:accepting() or world.executionSave and world.executionSave.state=='BLOCKED' then return end
    if now>=recoveryRefresh then
        recoveryIds={} for id in pairs(require('EmberRoutesProbe/BusinessJobs').hauls().byNpc) do recoveryIds[#recoveryIds+1]=id end
        table.sort(recoveryIds) recoveryRefresh=now+2000
    end
    local actor=getSpecificPlayer(0) if not actor then return end
    local wake=require 'EmberRoutesProbe/PlanningWake'
    for _=1,math.min(2,#recoveryIds) do
        recoveryCursor=recoveryCursor%#recoveryIds+1 local id=recoveryIds[recoveryCursor]
        local r=Work.record(id)
        if r and r.producer=='LOGISTICS' and r.state=='PAUSED' and not r.controlUncertain and not r.manualPaused
            and not Work.busy(id) and (not rt or not rt:owns(id)) then
            local reason=r.reason or ''
            local system=r.format==2 and (reason=='ROUTING_WAIT' or reason=='SAVE' or reason=='LOAD_RECOVERY')
                or r.format==1 and (reason=='SAVE' or reason=='LOAD_RECOVERY' or reason=='NATIVE_TRANSFER_STOPPED'
                    or string.find(reason,'^FILTER_REJECTED') or replanReasons[reason])
            local entry=Ledger.get(r.settlementId) local b=system and entry and Driver.bindId(actor,id)
            local wait=recoveryWait[id]
            if b and (not wait or wait.job~=r.id or now>=wait.due or wake.changed(wait.watch))
                and require('EmberRoutesProbe/MembershipService').check(id,'WORK',
                    {x=b.handle:getX(),y=b.handle:getY(),z=b.handle:getZ(),scopeId=entry.id}).allowed then
                local ctx=contexts[entry.id]
                if Probe.publicDispatch then ctx=Service.preparePublic(actor,entry,true) end
                if ctx and ctx.running then
                    recoveryWait[id]={job=r.id,due=now+5000+recoveryCursor%7*137,watch=wake.capture(entry)}
                    Work.resumeFor(actor,id)
                end
            end
        end
    end
end
function Service.tick()
    Service.recover()
    if Probe.publicDispatch then
        local pending=false for _ in pairs(dirty) do pending=true break end
        if not pending then return end
    end
    if not Probe.ready or Probe.enabled==false or not Probe.hasJava() or isClient() or isServer() then return end
    if not Probe.publicDispatch then schedule:step(1,function(id)
        local ctx=contexts[id] local before=ctx.reason local ok,reason=pcall(advance,ctx)
        if before~=ctx.reason then changed(id) end
        if not ok then
            ctx.running=false ctx.plan=nil ctx.reason="ERROR" schedule:remove(id)
            changed(id)
            log("ERROR settlement="..id.." "..tostring(reason))
            for npcId in pairs(Store.get(id).workers) do
                local record=Work.record(npcId)
                if record and record.producer=="LOGISTICS" and record.settlementId==id then Work.pause("LOGISTICS_ERROR",npcId) end
            end
        end
    end)
    end
    local pending=dirty dirty={}
    for id in pairs(pending) do
        local snapshot=Service.status(id)
        local list=watchers[id] or {}
        for callback in pairs(list) do
            local ok=pcall(callback,snapshot)
            if not ok then list[callback]=nil end
        end
    end
end
function Service.report(id)
    local ctx=contexts[id] local settings=Store.get(id) local count=0
    for npcId in pairs(settings.workers) do
        count=count+1 local record=Work.record(npcId)
        log("WORKER settlement="..id.." npc="..npcId.." task="..(record and record.id or "none")
            .." state="..(record and record.state or "IDLE").." reason="..(record and record.reason or ""))
    end
    local reason=ctx and ctx.reason or "STOPPED"
    log("REPORT settlement="..id.." workers="..count.." intake="..tostring(settings.intake).." tidy="..tostring(settings.tidy).." reason="..reason)
    return reason
end
-- Detached status for an explicit user request; no inventory scan or UI polling.
function Service.status(id)
    local settings=Store.view(id)
    local result={reason=contexts[id] and contexts[id].reason or "STOPPED",running=Service.running(id),
        intake=settings.intake,tidy=settings.tidy,workers={}}
    for npcId in pairs(Store.get(id).workers) do
        local record=Work.record(npcId)
        local completed=Work.lastCompleted(npcId)
        if completed and completed.settlementId~=id then completed=nil end
        local reason=result.reason
        if Work.busy(npcId) then reason="WORKING"
        elseif not Work.automationAllowed(npcId) then reason="MANUAL_OVERRIDE"
        elseif record and record.state~="DONE" then
            reason=record.producer=="LOGISTICS" and record.reason or "MANUAL_TASK_PENDING"
        else
            local m=require('EmberRoutesProbe/MembershipService').view(npcId)
            if not m or m.pending or m.context~='SETTLEMENT' or m.settlementId~=id then reason='MEMBERSHIP_UNAVAILABLE' end
        end
        result.workers[#result.workers+1]={id=npcId,reason=reason,state=record and record.state or "IDLE",
            taskId=record and record.id or "",producer=record and record.producer or "",
            delivered=record and record.delivered or 0,total=record and #record.items or 0,
            source=record and record.source or "",destination=record and record.destination or "",
            phase=record and record.phase or "",sourceMode=record and record.sourceMode or "",lastCompleted=completed}
    end
    table.sort(result.workers,function(a,b) return a.id<b.id end)
    return result
end
function Service.watch(id,callback)
    watchers[id]=watchers[id] or {} watchers[id][callback]=true changed(id)
    return function()
        local list=watchers[id]
        if list then
            list[callback]=nil
            local empty=true for _ in pairs(list) do empty=false break end
            if empty then watchers[id]=nil dirty[id]=nil end
        end
    end
end
function Service.workerCommand(actor,id,npcId,command)
    local entry,reason=Ledger.view(actor,id)
    if not entry then return reason end
    if not Store.get(id).workers[npcId] then return "WORKER_REMOVED" end
    if command=="remove" then return Service.removeWorker(actor,id,npcId) end
    if command~="retry" then return "INVALID_COMMAND" end
    if Work.busy(npcId) then return "BUSY" end
    local record=Work.record(npcId)
    if record and record.state~="DONE" and (record.producer~="LOGISTICS" or record.settlementId~=id) then
        return "MANUAL_TASK_PENDING"
    end
    local member=require('EmberRoutesProbe/MembershipService').view(npcId)
    if not member or member.pending or member.context~='SETTLEMENT' or member.settlementId~=id then return 'MEMBERSHIP_UNAVAILABLE' end
    local ctx=contexts[id]
    if not ctx or not ctx.running then return "STOPPED" end
    Work.allowAutomation(npcId)
    ctx.attempts[npcId]=nil ctx.nextTick=0 ctx.plan=nil changed(id)
    return "RETRY_REQUESTED"
end
function Service.reset()
    for _,list in pairs(watchers) do for callback in pairs(list) do pcall(callback,{reason="WORLD_RESET",workers={}}) end end
    contexts,schedule,watchers,dirty={},Schedule.new(),{},{}
end
Registry.listeners[#Registry.listeners+1]=Service.invalidate
Registry.inventoryListeners[#Registry.inventoryListeners+1]=function(id)
    for _,ctx in pairs(contexts) do
        if ctx.public then ctx.publicWait={} end
        if ctx.members[id] then ctx.nextTick=0 ctx.dirty=true end
    end
end
Ledger.listeners[#Ledger.listeners+1]=function(id) Service.invalidate(id) end
Probe.tickLogistics,Probe.resetLogistics=Service.tick,Service.reset
return Service
