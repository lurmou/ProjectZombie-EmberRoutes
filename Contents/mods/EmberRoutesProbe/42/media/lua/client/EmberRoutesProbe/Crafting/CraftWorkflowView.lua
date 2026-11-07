-- Production facts to display steps. Never plans recipes, moves assets or settles Jobs.
local M={}
function M.attach(row,p,control,revision)
    local steps={} local current=1
    local active=control and not control.pending and control.state=='ACTIVE'
    local a=p.nativeAttempt
    local committing=active and p.phase=='COMMITTING' and a and a.state=='COMMITTING'
    local uncertain=p.uncertain or a and a.state~='APPLIED' and not committing
    local function add(key,status,progress)
        steps[#steps+1]={key=key,labelKey='IGUI_EmberRoutesProbe_Monitor_'..key,status=status,progress=progress}
        if status=='ACTIVE' or status=='UNCERTAIN' or status=='BLOCKED' then current=#steps end
    end
    if p.phase=='PLANNING' then
        add(p.chain and 'craftDependencies' or 'craftPlan',active and 'ACTIVE' or 'BLOCKED')
    end
    if p.phase=='COLLECTING' and (#(p.materials or {})+#(p.tools or {}))>0 then
        add('craftPrepare',active and 'ACTIVE' or 'BLOCKED')
    end
    local verified=p.unitMade==true and a and a.state=='APPLIED' and a.observation and a.observation.complete==true
    add('craftEffect',uncertain and 'UNCERTAIN' or verified and 'COMPLETED'
        or row.closed and p.state=='CANCELLED' and 'SKIPPED'
        or active and (p.phase=='CRAFTING' or p.phase=='COMMITTING') and 'ACTIVE' or 'PLANNED',
        tostring(p.produced or 0)..'/'..tostring(p.target or 0))
    local total,delivered=0,0
    for _,o in ipairs(p.outputs or {}) do total=total+1 if o.delivered then delivered=delivered+1 end end
    if total>0 then add('craftDelivery',delivered==total and not uncertain and 'COMPLETED'
        or active and p.phase=='RETURNING' and 'ACTIVE' or 'PLANNED',delivered..'/'..total) end
    if #(p.tools or {})+#(p.held or {})>0 or p.phase=='RETURNING' then
        add('craftCleanup',p.released and not uncertain and 'COMPLETED'
            or active and p.phase=='RETURNING' and 'ACTIVE' or 'PLANNED')
    end
    row.stages=steps row.stageIndex=current
    row.workflow={viewRevision=revision or p.generation,steps=steps}
end
return M
