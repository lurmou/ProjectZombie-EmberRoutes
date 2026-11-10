-- Rebuildable cleaning facts. No Job, Claim, body grant or UI-owned observation.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local JobState=require 'EmberRoutesProbe/Kernel/JobState'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/Settlement/SettlementGeometry'
local Spatial=require 'EmberRoutesProbe/Field/FieldSpatial'
local Discovery=require 'EmberRoutesProbe/Field/FieldDiscovery'
local Tools=require 'EmberRoutesProbe/Field/ToolDiscovery'
local Signals=require 'EmberRoutesProbe/Work/LaborSignals'
local D={}
local world,scopes,cursor,nextAt=nil,{},0,0
local inventoryRevision=0
if Registry.inventoryListeners then
    Registry.inventoryListeners[#Registry.inventoryListeners+1]=function() inventoryRevision=inventoryRevision+1 end
end
local function current()
    local root=Registry.data()
    if root~=world then world,scopes,cursor,nextAt=root,{},0,0 end
    return root
end
local function key(p) return p.x..':'..p.y..':'..p.z end
local function evaluate(r,actor,entry,now,eligible,priorities)
    local count=EmberRoutesProbeJava.workerCount()
    if count==0 then r.state='BLOCKED' r.reason='FIELD_NO_WORKER' r.missingRoles={} r.evaluation=nil return end
    if count<0 or count>256 then r.state='OBSERVING' r.reason='FIELD_OBSERVING' return end
    local e=r.evaluation
    if not e or e.count~=count or e.inventory~=inventoryRevision or e.cursor>=count and now>=e.nextAt then
        e={count=count,cursor=0,enabled=0,eligible=0,unknown=false,missing={},inventory=inventoryRevision,nextAt=now+1000}
        r.evaluation=e
    end
    if e.cursor<count then
        for _=1,math.min(4,count-e.cursor) do
            local npcId=EmberRoutesProbeJava.workerIdAt(e.cursor) e.cursor=e.cursor+1
            if (priorities(npcId).cleaning or 0)>0 then
                e.enabled=e.enabled+1
                local binding,workerEntry=eligible(actor,npcId,entry.id)
                if binding and workerEntry and workerEntry.id==entry.id then
                    local target
                    for _,p in ipairs(r.points) do
                        if not p.stale and not r.claimed[key(p)] and Discovery.allowed('cleaning',entry,
                            {kind='STAIN',x=p.x,y=p.y,z=p.z},binding.handle) then target=p break end
                    end
                    if target then
                        e.eligible=e.eligible+1
                        local plan,reason,detail=Tools.findSupplies(entry,binding.handle,'STAIN')
                        if plan then e.ready=true
                        else
                            e.unknown=e.unknown or not detail or not detail.complete
                            e.reason=reason or 'FIELD_OBSERVING'
                            for _,role in ipairs(detail and detail.missingRoles or {}) do e.missing[role]=true end
                        end
                    end
                end
            end
        end
    end
    r.missingRoles={} for role in pairs(e.missing) do r.missingRoles[#r.missingRoles+1]=role end table.sort(r.missingRoles)
    if e.ready then r.state='READY' r.reason='FIELD_DEMAND_READY' r.missingRoles={}
    elseif e.cursor<count or e.unknown then r.state='OBSERVING' r.reason='FIELD_OBSERVING'
    elseif e.enabled==0 then r.state='BLOCKED' r.reason='FIELD_POLICY_DISABLED'
    elseif e.eligible==0 then r.state='BLOCKED' r.reason='FIELD_WORKER_BUSY'
    else r.state='BLOCKED' r.reason=e.reason or 'FIELD_TOOLS_UNAVAILABLE' end
end
function D.advance(actor,now,eligible,priorities)
    local root=current()
    if now<nextAt then return end nextAt=now+1000
    local bridge=EmberRoutesProbeJava
    if not bridge or not bridge.cleaningScanStains or not bridge.cleaningSquareHasStains
        or not bridge.workerCount or not bridge.workerIdAt then
        for _,r in pairs(scopes) do
            if r.state~='UNSUPPORTED' then
                r.state='UNSUPPORTED' r.reason='FIELD_DEMAND_UNSUPPORTED' r.revision=r.revision+1 Signals.changed()
            end
        end
        return
    end
    local entries=Ledger.list()
    local present={}
    for _,entry in ipairs(entries) do present[entry.id]=true end
    for id in pairs(scopes) do
        if not present[id] then scopes[id]=nil Signals.changed() end
    end
    if #entries==0 then
        for _ in pairs(scopes) do Signals.changed() break end
        scopes={} return
    end
    cursor=cursor%#entries+1 local entry=Ledger.view(actor,entries[cursor].id)
    if not entry then scopes[entries[cursor].id]=nil return end
    local r=scopes[entry.id]
    if not r or r.entryRevision~=entry.revision then
        r={points={},byKey={},check=0,revision=0,entryRevision=entry.revision,missingRoles={}} scopes[entry.id]=r
    end
    local chunk=Spatial.chunk(entry,nil,'cleaning-demand',now)
    if chunk then
        for _,p in ipairs(EmberRoutesProbeJava.cleaningScanStains(chunk,16) or {}) do
            if Geometry.inside(entry,p.x,p.y) then
                local k=key(p) local old=r.byKey[k]
                if old then old.stale=false
                elseif #r.points<128 then
                    local point={x=p.x,y=p.y,z=p.z,stale=false}
                    r.points[#r.points+1]=point r.byKey[k]=point
                end
            end
        end
    end
    for _=1,math.min(16,#r.points) do
        r.check=r.check%#r.points+1 local p=r.points[r.check]
        local square=Spatial.square(p)
        if not square then p.stale=true
        elseif not EmberRoutesProbeJava.cleaningSquareHasStains(square) then
            r.byKey[key(p)]=nil table.remove(r.points,r.check) r.check=r.check-1
            if #r.points==0 then break end
        else p.stale=false end
    end
    r.claimed={}
    for _,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do
        if j.providerType=='FIELD_WORK' and j.scopeId==entry.id and not JobState.isTerminal(j.state)
            and j.payload.target.kind=='STAIN' then r.claimed[key(j.payload.target)]=true end
    end
    r.count,r.stale=0,0
    for _,p in ipairs(r.points) do if not r.claimed[key(p)] then r.count=r.count+1 if p.stale then r.stale=r.stale+1 end end end
    if r.count>0 then
        evaluate(r,actor,entry,now,eligible,priorities)
        if r.stale>0 then r.state='OBSERVING' r.reason='FIELD_SOURCE_STALE' end
    end
    local signature=r.count..':'..r.stale..':'..tostring(r.state)..':'..tostring(r.reason)..':'..table.concat(r.missingRoles,',')
    if r.signature~=signature then r.signature=signature r.revision=r.revision+1 Signals.changed() end
end
function D.rows(scopeId)
    current() local r=scopes[scopeId]
    if not r or r.count==0 or not r.count then return {} end
    local stages={{key='conditions',labelKey='IGUI_EmberRoutesProbe_Monitor_fieldConditions',
        status=r.state=='READY' and 'COMPLETED' or r.state=='OBSERVING' and 'OBSERVING' or 'BLOCKED'},
        {key='work',labelKey='IGUI_EmberRoutesProbe_Monitor_fieldWork',status='PLANNED'}}
    local missing={} for i,role in ipairs(r.missingRoles) do missing[i]=role end
    local labels={} for _,role in ipairs(missing) do labels[#labels+1]=getText('IGUI_EmberRoutesProbe_Monitor_role_'..role) end
    local explanation=getText('IGUI_EmberRoutesProbe_Monitor_'..r.reason)
    return {{id='DEMAND:cleaning:'..scopeId,kind='FIELD_DEMAND',state=r.state,phase='WAITING_CLAIM',
        title=getText('IGUI_EmberRoutesProbe_Monitor_cleaningDemand'),reason=r.reason,
        stateText=getText('IGUI_EmberRoutesProbe_Monitor_demandState_'..r.state),
        reasonText=explanation,summaryText=explanation,blockerLabels=labels,
        observedCount=r.count,staleCount=r.stale,coverage='PARTIAL',missingRoles=missing,
        demandSummary=getText('IGUI_EmberRoutesProbe_Monitor_demandCount',r.count,r.stale),
        observationRevision=r.revision,feasibilityRevision=r.revision,generation=r.revision,
        bucket=r.state=='BLOCKED' and 'attention' or 'waiting',closed=false,carrierAvailable=true,
        stages=stages,stageIndex=1,workflow={viewRevision=r.revision,steps=stages},
        assets={},nodes={},target=0,requested=0,delivered=0,readOnly=true,canPause=false,canResume=false,canCancel=false}}
end
return D
