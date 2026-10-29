local Probe=require "EmberRoutesProbe/Boot"
local Driver=require "EmberRoutesProbe/Driver"
local Factory=require "EmberRoutesProbe/CompanionAgent"
local Schedule=require "EmberRoutesProbe/LaborSchedule"
local Runtime=require "EmberRoutesProbe/TaskRuntime"
local Companion={}
local agents,schedule={},Schedule.new()
local function selected(id)
    return id or Driver.selected(getSpecificPlayer(0))
end
local function agent(id)
    id=selected(id)
    if not agents[id] then agents[id]=Factory.new() end
    return agents[id],id
end
local function enroll(worker,id)
    if worker.binding then schedule:add(id) else schedule:remove(id) end
end
local function request(actor,worker,binding,command,intent)
    local runtime=Runtime.current()
    if not runtime then return nil,'CONTROL_UNAVAILABLE' end
    if not binding then return nil,'CARRIER_UNAVAILABLE' end
    if not intent and command~='follow' and command~='hold' and command~='sethome' and command~='home' then
        return nil,'INVALID_COMMAND'
    end
    if command=='home' and not worker.home then return nil,'HOME_NOT_SET' end
    if intent then intent.id=binding.id end
    local Registry=require 'EmberRoutesProbe/ContainerRegistry'
    local root=Registry.data()
    local jobId=intent and intent.jobId or Registry.id()
    if type(jobId)~='string' or jobId=='' then return nil,'JOB_ID_REQUIRED' end
    local function persist(data,fact,reason)
        if Registry.data()~=root then return false end
        local store=root.companionIntents
        if store and store.format~=1 then return false end
        if not store then store={format=1,byNpc={}} root.companionIntents=store end
        -- Scalar intent only. This is a recovery record, not a disk-save receipt.
        store.byNpc[binding.id]={jobId=jobId,mode=data.mode,hasHome=data.hasHome==true,
            homeX=data.homeX,homeY=data.homeY,homeZ=data.homeZ,membershipRevision=worker.membershipRevision,effects=fact.effects,reason=reason}
        return true
    end
    return runtime:submit({npcId=binding.id,jobId=jobId,kind='COMPANION',binding=binding,
        nonPreemptive=intent~=nil,
        validate=function()
            if not Probe.ready or Registry.data()~=root or not actor or actor:isDead() then return false end
            if worker.membershipRevision then
                local member=require('EmberRoutesProbe/MembershipService').view(binding.id)
                return member and not member.pending and member.context=='FOLLOW'
                    and member.revision==worker.membershipRevision
                    and member.leaderId==require('EmberRoutesProbe/MembershipService').character(actor)
            end
            return true
        end,
        start=function(body)
            worker.jobId=jobId
            if intent then return worker.restoreState(actor,intent,body) end
            local value=worker.execute(actor,command,body,binding)
            return value=='FOLLOW' or value=='RETURNING' or value=='HOLD' or value=='HOME_SET',value
        end,
        tick=function() worker.tick() end,
        finished=function() return worker.mode~='FOLLOW' and worker.mode~='RETURNING' end,
        stopAdapter=function(controller,ticket)
            return worker.stopAdapter(controller,ticket,function(data,fact) return persist(data,fact) end,jobId)
        end,
        persistFailure=function(fact,reason) return persist(worker.exportState(),fact,reason) end})
end
function Companion.execute(actor,command)
    if command~='status' then
        local M=require 'EmberRoutesProbe/MembershipService'
        local id=Driver.selected(actor) local row=M.view(id)
        if not row then return false,'NO_MEMBERSHIP' end
        local kinds={follow='FOLLOW',hold='WAIT',home='RETURN'}
        if not kinds[command] then return false,'INVALID_COMMAND' end
        local c=M.request(actor,id,{requestId=require('EmberRoutesProbe/ContainerRegistry').id(),
            expectedRevision=row.revision,kind=kinds[command]})
        actor:Say(getText('IGUI_EmberRoutesProbe_Membership_'..(c.reason or c.state)))
        return c.state~='REJECTED',c.reason or c.state
    end
    return Companion.debugExecute(actor,command)
end
-- Explicit low-level diagnostic adapter; normal product commands always enter MembershipService.
function Companion.debugExecute(actor,command)
    local binding=Driver.bind(actor)
    local worker,id=agent(binding and binding.id)
    if Probe.controlledExecution==true and command~='status' then
        local handle,why=request(actor,worker,binding,command)
        if handle and Probe.invalidateCare then Probe.invalidateCare(id,'COMPANION_COMMAND') end
        if not handle then actor:Say(getText('IGUI_EmberRoutesProbe_CompanionResult')..' '..tostring(why)) end
        return handle~=nil,why
    end
    local result=worker.execute(actor,command) enroll(worker,id) return result
end
function Companion.startFor(actor,id,revision)
    local binding=Driver.bindId(actor,id) if not binding then return nil,'CARRIER_UNAVAILABLE' end
    local worker=agent(id) worker.membershipRevision=revision
    return request(actor,worker,binding,'follow')
end
function Companion.cancel(reason,id)
    id=selected(id) local worker=agents[id]
    local runtime=Runtime.current()
    if runtime and runtime:owns(id) then runtime:stop(id,reason or 'USER') schedule:remove(id) return end
    if worker then worker.cancel(reason) schedule:remove(id) end
end
function Companion.cancelAll(reason)
    for id in pairs(agents) do Companion.cancel(reason,id) end
end
function Companion.exportState(id)
    local worker=agent(id) local value=worker.exportState() value.membershipRevision=worker.membershipRevision return value
end
function Companion.stopAdapter(id,controller,ticket,persistIntent,jobId)
    local worker=agents[id]
    if not worker then return nil,'NO_COMPANION_INTENT' end
    return worker.stopAdapter(controller,ticket,persistIntent,jobId)
end
function Companion.restoreState(actor,data)
    local worker,id=agent(data.id)
    local member=require('EmberRoutesProbe/MembershipService').view(id)
    if not member or member.pending or member.context~='FOLLOW' or data.membershipRevision~=member.revision
        or member.leaderId~=require('EmberRoutesProbe/MembershipService').character(actor) then return false,'STALE_MEMBERSHIP' end
    worker.membershipRevision=member.revision
    return Companion.debugRestoreState(actor,data)
end
function Companion.debugRestoreState(actor,data)
    local worker,id=agent(data.id)
    if Probe.controlledExecution==true then
        -- Capture scalars now: selection and the caller's table may change before grant.
        local copy={id=data.id,jobId=data.jobId,mode=data.mode,hasHome=data.hasHome,
            homeX=data.homeX,homeY=data.homeY,homeZ=data.homeZ,membershipRevision=data.membershipRevision}
        local handle,why=request(actor,worker,Driver.bindId(actor,id),nil,copy)
        return handle~=nil,why
    end
    local result=worker.restoreState(actor,data) enroll(worker,id) return result
end
function Companion.report() local worker=agent() return worker.report() end
function Companion.tick()
    schedule:step(4,function(id)
        local worker=agents[id]
        if not worker.body then worker.tick() end
        enroll(worker,id)
    end)
end
function Companion.reset()
    Companion.cancelAll("WORLD_RESET") agents,schedule={},Schedule.new()
end
-- Read-only compatibility for existing diagnostic consumers.
setmetatable(Companion,{__index=function(_,key) local worker=agent() return worker[key] end})
Probe.cancelCompanion,Probe.tickCompanion,Probe.resetCompanion=Companion.cancel,Companion.tick,Companion.reset
Probe.cancelEveryCompanion=Companion.cancelAll
Probe.tickTasks,Probe.resetTasks,Probe.beginTasks=Runtime.tick,Runtime.reset,Runtime.begin
return Companion
