-- Manifest receipts determine display facts; route policy stays with HaulAgent.
local M={}
function M.attach(row,p,control,revision)
    local uncollected,carried,delivered,withdrawn,unresolved=0,0,0,0,0
    for _,line in ipairs(p.manifest or {}) do
        local s=line.custodyState
        if s=='UNCOLLECTED' then uncollected=uncollected+1
        elseif s=='CARRIED' then carried=carried+1
        elseif s=='DELIVERED' and line.deliveryReceipt then delivered=delivered+1
        elseif s=='WITHDRAWN' then withdrawn=withdrawn+1
        else unresolved=unresolved+1 end
    end
    local steps={} local current=1 local a=p.activeAttempt
    local active=control and not control.pending and control.state=='ACTIVE'
    local uncertain=p.controlUncertain or unresolved>0
    local function add(key,status,progress)
        steps[#steps+1]={key=key,labelKey='IGUI_EmberRoutesProbe_Monitor_'..key,status=status,progress=progress}
        if status=='ACTIVE' or status=='UNCERTAIN' or status=='BLOCKED' then current=#steps end
    end
    if uncertain then add('haulReconcile','UNCERTAIN') end
    if p.routingWait or active and not a then add('haulRoute',p.routingWait and 'BLOCKED' or 'ACTIVE') end
    local total=uncollected+carried+delivered+unresolved
    if total>0 then
        add('haulTake',not uncertain and carried+delivered==total and 'COMPLETED'
            or active and a and a.kind=='TAKE' and 'ACTIVE' or 'PLANNED',tostring(carried+delivered)..'/'..total)
        add('haulPut',not uncertain and delivered==total and 'COMPLETED'
            or active and a and a.kind=='PUT' and 'ACTIVE' or 'PLANNED',delivered..'/'..total)
    end
    if withdrawn>0 then add('haulWithdraw','COMPLETED',tostring(withdrawn)) end
    row.stages=steps row.stageIndex=current
    row.workflow={viewRevision=revision or p.generation,planRevision=p.routeRevision,steps=steps}
end
return M
