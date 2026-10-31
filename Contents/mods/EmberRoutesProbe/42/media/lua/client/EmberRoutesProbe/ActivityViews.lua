-- Read-only projections. No state transitions, native sampling or subscriptions.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local M={}
function M.new(load)
    local V={}
    local function snapshot(event)
        local row={}
        for key,value in pairs(event) do if key~='stage' and key~='roster' then row[key]=Store.copy(value) end end
        row.roster={}
        for npc,member in pairs(event.roster) do
            local m={}
            for key,value in pairs(member) do if key~='duty' and key~='relief' then m[key]=Store.copy(value) end end
            if event.reliefBlocked then m.relief={state='UNKNOWN',reason='UNSUPPORTED'}
            elseif member.relief then
                m.relief={state=member.relief.state,reason=member.relief.reason,hours=member.relief.hours}
            end
            row.roster[npc]=m
        end
        if event.stage then
            local stage=event.stage
            row.stage=event.stageBlocked and {supported=false} or {supported=true,id=stage.id,index=stage.index,format=stage.format,
                state=stage.state,actorCount=stage.actorCount,exitCount=stage.exitCount,outcome=stage.outcome}
            if stage.format==2 then row.stage.sharedStart=stage.sharedStart row.stage.sharedEnd=stage.sharedEnd end
        end
        row.counts={invited=0,arrived=0,joined=0,settled=0,withdrawn=0,unknown=0}
        for npc,member in pairs(row.roster) do
            local counts=row.counts counts.invited=counts.invited+1
            if member.arrival then counts.arrived=counts.arrived+1 end
            if member.joined then counts.joined=counts.joined+1 end
            if member.settled then counts.settled=counts.settled+1 end
            if member.withdrawn then counts.withdrawn=counts.withdrawn+1 end
            local job=member.jobId and Jobs.current():peek(member.jobId)
            member.effectsUnknown=event.reliefBlocked or member.relief and (member.relief.state=='UNKNOWN' or member.relief.state=='APPLYING')
                or job and job.effects~='KNOWN' or not member.settled and member.attendanceState=='UNKNOWN' or false
            local duty=event.roster[npc].duty
            if event.dutyBlocked or duty and duty.current and duty.current.unknown then member.effectsUnknown=true end
            if not member.settled then
                Jobs.current():visitNpc(npc,function(owned) if owned.effects~='KNOWN' then member.effectsUnknown=true end end)
            end
            if member.effectsUnknown then counts.unknown=counts.unknown+1 end
            if not member.reason and member.effectsUnknown then member.reason='ACTIVITY_EFFECTS_UNKNOWN' end
        end
        return row
    end
    function V.detail(actor,id)
        local saved,why=load() if not saved then return nil,why end
        local event=saved.events[id] if not event then return nil,'ACTIVITY_MISSING' end
        if not Ledger.view(actor,event.settlementId) then return nil,'ACCESS_DENIED' end
        return snapshot(event)
    end
    function V.view(actor,scope,summaryOnly)
        local entry,why=Ledger.view(actor,scope) if not entry then return nil,why end
        local saved,reason=load() if not saved then return nil,reason end
        local result={}
        for id,event in pairs(saved.events) do
            if event.settlementId==scope then
                local row=summaryOnly and {id=event.id,name=event.name,state=event.state,createdAt=event.createdAt,revision=event.revision} or snapshot(event)
                result[#result+1]=row
            end
        end
        table.sort(result,function(a,b) return a.createdAt==b.createdAt and a.id<b.id or a.createdAt<b.createdAt end)
        return result
    end
    function V.revision(actor,scope,selectedId)
        if not Ledger.view(actor,scope) then return nil,'ACCESS_DENIED' end
        local saved,why=load() if not saved then return nil,why end
        local event=selectedId and saved.events[selectedId]
        local revisions={}
        if event and event.settlementId==scope then
            for npc,member in pairs(event.roster) do
                if not member.settled then
                    Jobs.current():visitNpc(npc,function(job) revisions[#revisions+1]=job.id..':'..tostring(job.revision) end)
                end
            end
        end
        table.sort(revisions)
        return saved.revision,nil,table.concat(revisions,'|')
    end
    return V
end
return M
