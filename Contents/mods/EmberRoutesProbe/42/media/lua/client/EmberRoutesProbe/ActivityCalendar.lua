-- Calendar commands delegated by ActivityService. No independent tick or owner.
local Store=require 'EmberRoutesProbe/ActivityStore'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Definitions=require 'EmberRoutesProbe/ActivityRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Members=require 'EmberRoutesProbe/MembershipService'
local M={}
function M.new(env)
    local C={}
    local scheduleCursor
    local load,clock=env.load,env.clock
    local function preview(...) return env.preview(...) end
    local function proposalArgs(proposal)
        local roster={} for id in pairs(proposal.roster) do roster[#roster+1]=id end table.sort(roster)
        return {name=proposal.name,settlementId=proposal.settlementId,zoneId=proposal.zone.id,zoneRevision=proposal.zone.revision,
            definitionId=proposal.definition,definitionVersion=proposal.definitionVersion,
            roster=roster,rules=Store.copy(proposal.rules),organizerId=proposal.organizerId,speakerId=proposal.speakerId,quorum=proposal.quorum,
            durationHours=proposal.durationHours,gatherHours=proposal.gatherHours}
    end
    function C.schedule(actor,args,token,firstAt,interval,count)
        local tokens=env.tokens()
        local preview,why=preview(actor,args,true) if not preview then return nil,why end
        local saved,reason=load() if not saved then return nil,reason end
        local rows,invalid=Store.schedules() if not rows then return nil,invalid end
        local Calendar=require 'EmberRoutesProbe/ActivitySchedule'
        local signature=Definitions.commandKey(args)
        local key=signature..'|schedule:'..tostring(firstAt)..':'..tostring(interval)..':'..tostring(count)
        local owner=Members.character(actor) local total,oldest=0,nil
        for _,s in pairs(rows) do
            if not Calendar.valid(s) or not Store.scalar(s) then return nil,'ACTIVITY_SCHEDULE_INVALID' end
            if s.requestId==token then
                if s.owner==owner and s.key==key then return Store.copy(s) end
                return nil,'ACTIVITY_REQUEST_CONFLICT'
            end
            total=total+1
            if not s.enabled then
                local busy=false for _,e in pairs(saved.events) do if e.scheduleId==s.id and e.state~='CLOSED' then busy=true break end end
                if not busy and (not oldest or s.firstAt<oldest.firstAt) then oldest=s end
            end
        end
        local issued=tokens[token]
        if not issued or issued.owner~=owner or issued.scope~=args.settlementId or issued.untilTime<getTimestampMs() then return nil,'ACTIVITY_REQUEST_EXPIRED' end
        local row={format=1,id=Registry.id(),owner=owner,requestId=token,key=key,enabled=true,
            firstAt=firstAt,intervalHours=interval,count=count,lastIndex=-1,args=proposalArgs(preview),revision=1}
        if not Calendar.valid(row) or not Store.scalar(row) or firstAt<clock() then return nil,'ACTIVITY_SCHEDULE_INVALID' end
        if total>=Calendar.LIMIT then if not oldest then return nil,'ACTIVITY_LIMIT' end rows[oldest.id]=nil end
        rows[row.id]=row tokens[token]=nil saved.revision=saved.revision+1
        return Store.copy(row)
    end
    function C.updateSchedule(actor,id,expected,args,token,firstAt,interval,count)
        local tokens=env.tokens()
        local saved,why=load() if not saved then return nil,why end
        local rows,invalid=Store.schedules() if not rows then return nil,invalid end
        local old=rows[id] local calendar=require 'EmberRoutesProbe/ActivitySchedule'
        if not old or not calendar.valid(old) or not Store.scalar(old) then return nil,'ACTIVITY_SCHEDULE_INVALID' end
        if not Ledger.view(actor,old.args.settlementId) then return nil,'ACCESS_DENIED' end
        if type(args)~='table' or args.settlementId~=old.args.settlementId then return nil,'ACTIVITY_EDIT_FIELDS' end
        local owner=Members.character(actor) local signature=Definitions.commandKey(args)
        if not signature then return nil,'ACTIVITY_DATA_INVALID' end
        local key=signature..'|schedule:'..tostring(firstAt)..':'..tostring(interval)..':'..tostring(count)
        local receipt=old.editReceipt
        if receipt and receipt.requestId==token then
            if receipt.owner==owner and receipt.key==key and receipt.expected==expected then return Store.copy(old) end
            return nil,'ACTIVITY_REQUEST_CONFLICT'
        end
        local issued=tokens[token]
        if not issued or issued.owner~=owner or issued.scope~=old.args.settlementId or issued.untilTime<getTimestampMs() then
            return nil,'ACTIVITY_REQUEST_EXPIRED'
        end
        if old.revision~=expected then return nil,'ACTIVITY_CHANGED' end
        local preview,reason=preview(actor,args,true) if not preview then return nil,reason end
        local row=Store.copy(old)
        row.owner=owner row.args=proposalArgs(preview) row.firstAt=firstAt row.intervalHours=interval row.count=count
        row.enabled=true row.lastIndex=-1 row.reason=nil row.series=(row.series or 1)+1 row.revision=row.revision+1
        row.editReceipt={requestId=token,owner=owner,key=key,expected=expected}
        if not calendar.valid(row) or not Store.scalar(row) or firstAt<clock() then return nil,'ACTIVITY_SCHEDULE_INVALID' end
        rows[id]=row tokens[token]=nil saved.revision=saved.revision+1 return Store.copy(row)
    end
    function C.cancelSchedule(actor,id,expected)
        local rows,why=Store.schedules() if not rows then return false,why end
        local row=rows[id]
        if not row or not require('EmberRoutesProbe/ActivitySchedule').valid(row) or not Store.scalar(row) then return false,'ACTIVITY_SCHEDULE_INVALID' end
        if not Ledger.view(actor,row.args.settlementId) then return false,'ACCESS_DENIED' end
        if not row.enabled then return true end
        if row.revision~=expected then return false,'ACTIVITY_CHANGED' end
        row.enabled=false row.revision=row.revision+1
        local saved=Store.current() saved.revision=saved.revision+1 return true
    end
    function C.schedules(actor,scope)
        if not Ledger.view(actor,scope) then return nil,'ACCESS_DENIED' end
        local rows,why=Store.schedules() if not rows then return nil,why end
        local result={}
        for _,s in pairs(rows) do
            if not require('EmberRoutesProbe/ActivitySchedule').valid(s) or not Store.scalar(s) then return nil,'ACTIVITY_SCHEDULE_INVALID' end
            if s.args.settlementId==scope then result[#result+1]=Store.copy(s) end
        end
        table.sort(result,function(a,b) return a.firstAt==b.firstAt and a.id<b.id or a.firstAt<b.firstAt end)
        return result
    end
    function C.tickSchedules(actor,hours,budget)
        local rows=Store.schedules() if not rows then return end
        local Calendar=require 'EmberRoutesProbe/ActivitySchedule'
        local saved=Store.current()
        if not scheduleCursor or scheduleCursor.rows~=rows or scheduleCursor.key and not rows[scheduleCursor.key] then
            local iter,state,key=pairs(rows) scheduleCursor={iter=iter,state=state,key=key,rows=rows}
        end
        local limit=type(budget)=='number' and budget==budget and math.max(0,math.min(Calendar.LIMIT,math.floor(budget))) or 2
        local owner=Members.character(actor)
        for _=1,limit do
            local key,s=scheduleCursor.iter(scheduleCursor.state,scheduleCursor.key) scheduleCursor.key=key
            if not key then scheduleCursor=nil break end
            if Calendar.valid(s) and Store.scalar(s) and s.owner==owner then
                local index,run=Calendar.due(s,hours)
                if index and index>s.lastIndex then
                    s.lastIndex=index s.revision=s.revision+1
                    saved.revision=saved.revision+1
                    local busy=false
                    for _,e in pairs(saved.events) do if e.scheduleId==s.id and e.state~='CLOSED' then busy=true break end end
                    if run and not busy then
                        -- Persisted occurrence identity is separate from UI command tokens.
                        local occurrence='schedule:'..s.id..':'..tostring(s.series or 1)..':'..tostring(index)
                        local exists=false for _,e in pairs(saved.events) do if e.requestId==occurrence then exists=true break end end
                        if not exists then
                            local intent,why=preview(actor,s.args)
                            if intent then
                                intent.id=Registry.id() intent.worldId=Store.worldId() intent.requestId=occurrence intent.requesterId=s.owner intent.scheduleId=s.id
                                intent.proposalKey=Definitions.commandKey(s.args) intent.revision=1 intent.state='GATHERING'
                                intent.createdAt=hours intent.gatherDeadline=hours+intent.gatherHours intent.gatherHours=nil
                                intent.endsAt=intent.gatherDeadline+intent.durationHours
                                local result,failed=Store.insert(intent)
                                if result then
                                    local event=Store.get(result.id)
                                    local ok,err=require('EmberRoutesProbe/ActivityParticipant').prepare(event)
                                    if not ok then Store.close(event.id,event.revision,err) end
                                    s.lastEventId=event.id s.reason=nil
                                else s.reason=failed end
                            else s.reason=why end
                        end
                    else s.reason=busy and 'ACTIVITY_PREVIOUS_UNSETTLED' or 'ACTIVITY_MISSED_WINDOW' end
                    if index>=s.count-1 then s.enabled=false end
                end
            end
        end
    end
    return C
end
return M
