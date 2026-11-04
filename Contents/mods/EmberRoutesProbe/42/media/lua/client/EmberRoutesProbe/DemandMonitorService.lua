-- Read-only facts and their current handlers. Never creates Orders/Jobs or owns assets.
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Orders=require 'EmberRoutesProbe/OrderMonitorService'
local D={}
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Demand_'..key,...) end
local function reason(key)
    if not key or key=='' then return '' end
    for _,prefix in ipairs({'Monitor','Public','Stock','WorkCode','Crafting'}) do
        local value=getTextOrNull('IGUI_EmberRoutesProbe_'..prefix..'_'..key)
        if value then return value end
    end
    return key
end
local function finish(row,entry,handlers)
    row.kind='DEMAND' row.compact=true row.readOnly=true row.closed=false
    row.canPause,row.canResume,row.canCancel=false,false,false
    row.carrierAvailable=true row.assets={} row.children=handlers or {}
    row.urgency=row.urgency or 'normal'
    row.affected=row.affected or entry.name or entry.id
    row.handling=#row.children>0
    local active=false
    for _,child in ipairs(row.children) do
        if child.uncertain then row.uncertain=true end
        if child.bucket=='active' then active=true end
    end
    -- This is the admission result for additional work, not a reason to say
    -- that the already-running cleaner is blocked.
    if active and row.blocker=='FIELD_WORKER_BUSY' then row.blocker=nil row.blocked=false end
    if row.blocker=='FIELD_WORKER_BUSY' then row.blocked=false end
    row.bucket=row.uncertain and 'attention' or active and 'active' or row.blocked and 'attention' or 'waiting'
    row.state=row.bucket row.stateText=text(row.uncertain and 'review' or active and 'processing'
        or row.handling and 'assignedWaiting' or 'unhandled')
    row.summaryText=text('summary',text('urgency_'..row.urgency),row.affected,row.stateText)
    row.detailContext=text('context',text('urgency_'..row.urgency),row.affected)
    row.demandReason=row.blocker and text('blocker',reason(row.blocker)) or nil
    return row
end
function D.status(actor,scope)
    local entry,why=Ledger.view(actor,scope)
    if not entry then return {rows={},reason=why} end
    local root=Registry.data() local rows,seen={},{}
    local jobs=root.taskJobs and root.taskJobs.byId or {}
    local function append(row,handlers)
        if not seen[row.id] then seen[row.id]=true rows[#rows+1]=finish(row,entry,handlers) end
    end
    local cleaning={}
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    local probe=require 'EmberRoutesProbe/Boot'
    local context={runtime=runtime,bind=function(id)
        return probe.ready and probe.hasJava() and require('EmberRoutesProbe/Driver').bindId(actor,id) or nil
    end}
    for _,job in pairs(jobs) do
        if job.scopeId==scope and job.providerType=='FIELD_WORK' and job.payload.category=='cleaning'
            and not ((job.state=='DONE' or job.state=='CANCELLED') and job.effects=='KNOWN') then
            local child=require('EmberRoutesProbe/FieldWorkMonitor').project(context,job)
            if child.bucket=='active' and not child.uncertain then child.reasonText=nil end
            cleaning[#cleaning+1]=child
        end
    end
    table.sort(cleaning,function(a,b) return a.id<b.id end)
    for _,fact in ipairs(require('EmberRoutesProbe/FieldDemand').rows(scope)) do
        append({id=fact.id,title=getText('IGUI_EmberRoutesProbe_Public_cleaning'),
            blocker=fact.state~='READY' and fact.reason or nil,blocked=fact.state=='BLOCKED',
            generation=fact.generation,observationRevision=fact.observationRevision,
            demandSummary=text('cleaningCount',tostring(fact.observedCount)),blockerLabels=fact.blockerLabels,
            coverageText=text('cleaningCoverage',tostring(fact.staleCount or 0))},cleaning)
    end
    if #cleaning>0 and not seen['DEMAND:cleaning:'..scope] then
        append({id='DEMAND:cleaning:'..scope,title=getText('IGUI_EmberRoutesProbe_Public_cleaning'),
            demandSummary=text('cleaningUnderway')},cleaning)
    end
    if require('EmberRoutesProbe/Boot').publicDispatch then
        local public=require 'EmberRoutesProbe/PublicWork'
        local byId={}
        for _,o in ipairs(public.orders(scope)) do byId[o.id]=o end
        for _,rule in ipairs(public.rules(scope)) do
            local shortage=type(rule.knownCount)=='number' and rule.knownCount<rule.minimum
            if rule.enabled and (shortage or rule.reason or rule.activeOrder) then
                local handlers={} local o=rule.activeOrder and byId[rule.activeOrder]
                if o and o.state~='DONE' and o.state~='CANCELLED' then
                    handlers[1]={id=o.id,name=o.name or getItemNameFromFullType(rule.product),
                        phase=o.state,reasonText=reason(o.reason),assets={},
                        bucket=o.state=='RUNNING' and 'active' or 'waiting',uncertain=o.state=='RECONCILE_REQUIRED'}
                end
                local reason=rule.reason
                if reason=='ORDER_CREATED' or reason=='MANUAL_ORDER_ACTIVE' then reason=nil end
                append({id='DEMAND:stock:'..scope..':'..rule.product,
                    title=text('stock',getItemNameFromFullType(rule.product)),generation=rule.revision,
                    blocker=reason,blocked=reason~=nil,
                    demandSummary=text('stockCount',rule.knownCount~=nil and tostring(rule.knownCount) or text('unknown'),tostring(rule.minimum))},handlers)
            end
        end
    end
    -- Medical observation is supplied by the personal service, never by the UI.
    for _,row in ipairs(require('EmberRoutesProbe/MedicalCare').demands(scope)) do append(row,row.children) end
    table.sort(rows,function(a,b)
        if a.urgency~=b.urgency then return a.urgency=='urgent' end
        return a.id<b.id
    end)
    return {rows=rows}
end
function D.watch(actor,scope,callback) return Orders.watch(actor,scope,callback,D.status) end
function D.command() return 'TASK_READ_ONLY' end
return D
