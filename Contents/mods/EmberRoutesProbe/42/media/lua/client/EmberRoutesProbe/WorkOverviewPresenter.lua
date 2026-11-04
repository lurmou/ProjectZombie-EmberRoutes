-- Disposable projection. Problem IDs, work IDs and NPC IDs are separate namespaces.
local P={}
local categories={CRAFT='crafting',ORDER='crafting',HAUL='hauling',DELIVERY='hauling',COOKING='cooking'}
function P.state(row)
    if row.closed or row.state=='DONE' or row.state=='CANCELLED' then return nil end
    if row.state=='PAUSED' or row.bucket=='paused' then return 'paused' end
    if not row.npcId then return 'waiting' end
    if row.uncertain or row.bucket=='attention' or row.state=='BLOCKED' or row.state=='RECONCILE_REQUIRED'
        or row.kind=='FIELD_WORK' and row.reason and string.find(row.reason,'^FIELD_') and row.bucket~='active' then return 'blocked' end
    if row.bucket=='active' or row.state=='RUNNING' then return 'working' end
    return 'waiting'
end
function P.project(rows,workers,problems)
    local out={works={},byNpc={},problems={},counts={waiting=0,blocked=0,paused=0},alerts={}}
    local seen={}
    for _,row in ipairs(rows or {}) do
        local state=P.state(row)
        local key=row.id -- Service IDs already contain the domain prefix.
        if state and row.kind~='TOOL_CUSTODY' and not seen[key] then
            seen[key]=true
            local w={key=key,row=row,state=state,title=row.title or row.kind,category=row.workCategory or (row.providerType=='COOKING' and 'cooking') or categories[row.kind]}
            out.works[#out.works+1]=w
            if row.npcId then
                local prior=out.byNpc[row.npcId]
                if not prior or state=='working' then out.byNpc[row.npcId]=w end
            end
            if state=='paused' or state=='blocked' and row.npcId or state=='waiting' and not row.npcId then out.counts[state]=out.counts[state]+1 end
        end
    end
    -- Custody monitor IDs are NPC-group summaries, not stable work identities.
    -- Keep actual responsibility facts visible in personnel, outside work counts/queues.
    for _,row in ipairs(rows or {}) do
        if (row.kind=='TOOL_CUSTODY' or not P.state(row) and not row.closed) and row.npcId and not out.byNpc[row.npcId] then
            out.byNpc[row.npcId]={row=row,title=row.title,state=P.state(row) or (row.uncertain and 'blocked' or 'waiting'),category='toolReturn'}
        end
    end
    for _,worker in ipairs(workers or {}) do
        if worker.isBleeding or worker.isInfected or worker.hasInjury then
            out.alerts[#out.alerts+1]={kind='health',title=worker.name,tab='personnel',context={npcId=worker.id}}
        end
    end
    seen={}
    for _,problem in ipairs(problems or {}) do
        if not seen[problem.id] then seen[problem.id]=true out.problems[#out.problems+1]=problem end
    end
    -- The current demand source has stock/medical/cleaning facts, no typed food/water facts.
    for _,w in ipairs(out.works) do
        if w.state=='blocked' and w.row.npcId then out.alerts[#out.alerts+1]={kind='blocked',title=w.title,tab='personnel',context={npcId=w.row.npcId}} end
    end
    for _,w in ipairs(out.works) do
        if w.state=='waiting' and not w.row.npcId then
            out.alerts[#out.alerts+1]={kind='waiting',title=w.title,tab=w.category=='crafting' and 'crafting' or 'policies',
                context=w.category=='crafting' and {view='orders'} or {category=w.category}}
        end
    end
    return out
end
function P.visible(work,filter)
    return filter=='all' or (work and work.state or 'idle')==filter
end
return P
