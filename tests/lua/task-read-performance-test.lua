-- Installed Kahlua CPU comparison only; no inference about whole-game latency.
local Store=require 'EmberRoutesProbe/JobStore'
for _,ordinary in ipairs({1,8}) do
    local root={} local store=assert(Store.open(root))
    local function job(id,provider)
        return {id=id,npcId='npc',providerType=provider,scopeId='s',revision=1,state='PREPARING',effects='KNOWN',obligations={},payload={}}
    end
    for i=1,ordinary do
        local record=job('work'..i,'CRAFT')
        for k=1,512 do record.payload[k]={id=k,source='container'} end
        assert(store:create(record))
    end
    assert(store:create(job('personal','SELF_CARE')))
    local function read(filtered)
        for _,record in ipairs(store:forNpc('npc',filtered and 'SELF_CARE' or nil)) do
            if record.providerType=='SELF_CARE' then assert(record.id=='personal') return end
        end
        error('missing personal record')
    end
    for _=1,5 do read(false) read(true) end
    local loops=30
    if _ERTestNanos then
        local oldStarted=_ERTestNanos()
        for _=1,loops do read(false) end
        local oldMs=(_ERTestNanos()-oldStarted)/1000000
        local newStarted=_ERTestNanos()
        for _=1,loops do read(true) end
        local newMs=(_ERTestNanos()-newStarted)/1000000
        print(string.format('TASK_READ ordinary=%d payloadRows=512 queries=%d allJobsMs=%.3f personalIndexMs=%.3f; installed VM only, host world absent',ordinary,loops,oldMs,newMs))
    else for _=1,loops do read(false) read(true) end end
    assert(#store:forNpc('npc')==ordinary+1,'read optimization does not discard retained jobs')
end
print('PASS targeted task read workload; snapshots detached, no game timing claim')
