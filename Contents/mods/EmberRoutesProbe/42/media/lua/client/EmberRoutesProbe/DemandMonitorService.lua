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
    for _,child in ipairs(row.children) do if child.uncertain then row.uncertain=true break end end
    row.bucket=row.uncertain and 'attention' or row.handling and 'active' or row.blocked and 'attention' or 'waiting'
    row.state=row.bucket row.stateText=text(row.handling and 'handling' or 'unhandled')
    local blocker=row.blocker and reason(row.blocker) or text('none')
    row.summaryText=text('summary',text('urgency_'..row.urgency),row.affected,row.stateText)
    row.demandReason=text('blocker',blocker)
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
    for _,job in pairs(jobs) do
        if job.scopeId==scope and job.providerType=='FIELD_WORK' and job.payload.category=='cleaning'
            and job.state~='DONE' and job.state~='CANCELLED' then
            local p=job.payload
            cleaning[#cleaning+1]={id=job.id,name=require('EmberRoutesProbe/DisplayNames').name(job.npcId),
                phase=p.phase,reasonText=reason(p.reason),assets={},uncertain=job.effects~='KNOWN'}
        end
    end
    table.sort(cleaning,function(a,b) return a.id<b.id end)
    for _,fact in ipairs(require('EmberRoutesProbe/FieldDemand').rows(scope)) do
        append({id=fact.id,title=getText('IGUI_EmberRoutesProbe_Public_cleaning'),
            blocker=fact.state~='READY' and fact.reason or nil,blocked=fact.state=='BLOCKED',
            generation=fact.generation,observationRevision=fact.observationRevision,
            demandSummary=fact.demandSummary,blockerLabels=fact.blockerLabels},cleaning)
    end
    if #cleaning>0 and not seen['DEMAND:cleaning:'..scope] then
        append({id='DEMAND:cleaning:'..scope,title=getText('IGUI_EmberRoutesProbe_Public_cleaning'),
            demandSummary=text('executionObserved')},cleaning)
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
                        phase=o.state,reasonText=reason(o.reason),assets={}}
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
