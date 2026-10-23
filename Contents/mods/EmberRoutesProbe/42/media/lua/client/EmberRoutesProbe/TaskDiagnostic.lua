-- Compatibility adapter for optional Debug probes. TaskRuntime owns all scheduling.
local Probe=require 'EmberRoutesProbe/Boot'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Driver=require 'EmberRoutesProbe/Driver'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Stop=require 'EmberRoutesProbe/TaskBusinessStop'
local Log=require 'EmberRoutesProbe/Log'
local Diagnostic={}
local function sameIds(a,b)
    if type(a)~='table' or type(b)~='table' or #a~=#b or #a>32 then return false end
    local expected={} for _,id in ipairs(a) do expected[id]=true end
    for _,id in ipairs(b) do if not expected[id] then return false end expected[id]=nil end
    for _ in pairs(expected) do return false end
    return true
end
function Diagnostic.active(c)
    local state=c and c.runtime:inspect(c.handle)
    return state and (state.state=='PENDING' or state.state=='QUEUED' or state.state=='ACTIVE' or state.state=='STOPPING') or false
end
function Diagnostic.cancel(c,reason)
    if not Diagnostic.active(c) then return false end
    return c.runtime:stopJob(c.binding.id,c.jobId,reason or 'USER')
end
function Diagnostic.submit(actor,kind,provider)
    local runtime=Runtime.current()
    if not runtime then return 'ADMISSION_CLOSED' end
    local binding=Driver.bind(actor)
    if not binding then return 'CARRIER_UNAVAILABLE' end
    local world=Registry.data()
    local function validate()
        if not Probe.ready or isClient() or isServer() or actor:isDead() or Registry.data()~=world then return false end
        local recovery=world.diagnosticRecovery
        if recovery and (recovery.format~=1 or type(recovery.byNpc)~='table') then return false end
        local old=recovery and recovery.byNpc[binding.id]
        if old and (type(old)~='table' or type(old.kind)~='string' or type(old.jobId)~='string' or type(old.ids)~='table') then return false end
        if old and provider.assets and not (provider.recovery and old.kind==kind) then return false end
        return provider.validate(binding)==true
    end
    if not validate() then return 'DIAGNOSTIC_CONDITION_CHANGED' end
    local c={binding=binding,npc=binding.handle,actor=actor,world=world,runtime=runtime,jobId=Registry.id(),kind=kind}
    local function persist(fact,reason)
        if Registry.data()~=world then return false end
        local evidence=provider.evidence(c)
        if type(evidence)~='table' or type(evidence.ids)~='table' or #evidence.ids>32 then return false end
        local ids={}
        for i,id in ipairs(evidence.ids) do
            if type(id)~='number' or id~=id or math.abs(id)==math.huge or id~=math.floor(id) then return false end
            ids[i]=id
        end
        c.fact={effects=fact.effects,ids=ids,reason=reason or c.reason}
        local store=world.diagnosticRecovery
        if store and (store.format~=1 or type(store.byNpc)~='table') then return false end
        if fact.effects=='UNKNOWN' then
            if not store then store={format=1,byNpc={}} world.diagnosticRecovery=store end
            local old=store.byNpc[binding.id]
            if old and old.jobId~=c.jobId then
                -- A failed explicit cleanup may confirm the same unresolved set.
                -- Keep the older receipt instead of overwriting its identity.
                if (provider.assets and not provider.recovery) or old.kind~=kind or not sameIds(old.ids,ids) then return false end
                return true
            end
            local count=0 for _ in pairs(store.byNpc) do count=count+1 end
            if not old and count>=256 then return false end
            store.byNpc[binding.id]={jobId=c.jobId,kind=kind,ids=ids,reason=c.fact.reason or 'RECONCILE_REQUIRED'}
        elseif provider.recovery and c.recovered and store then
            local old=store.byNpc[binding.id]
            if old and old.kind==kind and sameIds(old.ids,c.beforeIds) then store.byNpc[binding.id]=nil end
        end
        return true
    end
    local handle,why=runtime:submit({npcId=binding.id,jobId=c.jobId,kind='DEBUG_'..kind,binding=binding,
        captureStop=true,reconcileErrors=true,validate=validate,
        start=function(body)
            c.body=body c.entered=true
            if provider.recovery then
                local before=provider.evidence(c) c.beforeIds={}
                for i,id in ipairs(before.ids) do c.beforeIds[i]=id end
            end
            local accepted,reason=provider.start(c)
            Log.write('DIAGNOSTIC','START npc='..binding.id..' job='..c.jobId..' kind='..kind..' result='..tostring(c.result or reason or accepted))
            return accepted,reason
        end,
        tick=function()
            if not c.body.current() then return end
            if actor:isDead() or not Driver.valid(binding) then c.body.requestStop('CARRIER_LIFECYCLE') return end
            provider.tick(c)
        end,
        finished=function() return provider.finished(c) end,
        stopAdapter=function(controller,ticket)
            return Stop.new({controller=controller,ticket=ticket,npc=c.npc,npcId=binding.id,jobId=c.jobId,
                same=function() return c.entered and Registry.data()==world end,
                pause=function(reason)
                    c.reason=reason
                    if not c.paused then provider.pause(c,reason) c.paused=true end
                    return c.body.clear() and c.body.stop()
                end,
                effects=function()
                    local evidence=provider.evidence(c)
                    return type(evidence)=='table' and evidence.effects=='KNOWN' and 'KNOWN' or 'UNKNOWN'
                end,
                persist=function(fact) return persist(fact) end})
        end,
        persistFailure=function(fact,reason)
            Log.write('DIAGNOSTIC','FAILED npc='..binding.id..' job='..c.jobId..' kind='..kind..' reason='..tostring(reason))
            return persist(fact,reason)
        end})
    if not handle then return why end
    c.handle=handle
    return 'QUEUED',c
end
return Diagnostic
