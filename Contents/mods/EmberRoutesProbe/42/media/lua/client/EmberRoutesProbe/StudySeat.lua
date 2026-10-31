-- Optional seating is part of the existing reading Session. It owns no queue,
-- effect formula or inventory ledger. The real book remains in normal custody.
local Sites=require 'EmberRoutesProbe/ReposeSites'
local Store=require 'EmberRoutesProbe/LaborStore'
local Config=require 'EmberRoutesProbe/LeisureConfig'
local Log=require 'EmberRoutesProbe/Log'
local S={}
function S.release(c)
    local proof=c.payload.readingSite
    if not proof then return true end
    if c.npc:isSittingOnFurniture() or c.npc:getSitOnFurnitureObject()~=nil then return false end
    c.payload.leisureMemory=c.payload.leisureMemory or {cooldowns={}}
    for _,part in ipairs(proof.parts or {}) do
        if part.id==proof.partId then
            c.payload.leisureMemory.seatPreference={x=part.x,y=part.y,z=part.z} break
        end
    end
    local removed={} for _,key in ipairs(Sites.keys(proof,'REST')) do removed[key]=true end
    local kept={} for _,key in ipairs(c.payload.claims) do if not removed[key] then kept[#kept+1]=key end end
    c.payload.claims=kept c.payload.readingSite=nil
    if not c.persist() then return false end
    local released=Store.releasePersonalSeats(c.job,c.token)
    local service=require 'EmberRoutesProbe/LeisureService'
    if released and service.seatReleased then service.seatReleased(c.payload.settlementId) end
    return released
end
function S.new(c,item)
    local read=require('EmberRoutesProbe/StudyActions').read(c,item)
    local phase='SEEK' local notedStanding=false local standingReason
    local failedSeats,retries,retryAt={},0,nil
    local retrySeat=false
    local scan,move,posture,site,exitDeadline
    local function clearSeat()
        if posture and not posture.leave() then return false end
        if not c.body.repose('REST',false) then return false end
        return S.release(c)
    end
    local function standFallback(reason,proof)
        standingReason=reason
        c.reason=nil
        Log.write('STUDY_SEAT','Fallback stand-reading npc='..tostring(c.job.npcId)..' reason='..tostring(reason))
        require('EmberRoutesProbe/LeisureService').note(c.job.npcId,reason or 'READ_STANDING')
        proof=proof or c.payload.readingSite
        local key=proof and proof.key
        retrySeat=key~=nil and retries<Config.readingSeatRetries
        if key then failedSeats[key]=math.huge end
        phase='FALLBACK' exitDeadline=getTimestampMs()+8000
        -- Movement may still be active; request a stop before starting reading.
        c.body.stop()
        return 'Running'
    end
    return {kind='Action',run=function()
        if not c.valid() then return 'Failure' end
        if phase=='RETRY' then
            if getTimestampMs()<retryAt then return 'Running' end
            phase='SEEK'
        end
        if phase=='SEEK' then
            -- A missing bridge is an explicit stand-reading fallback (e.g. a
            -- non-seating environment), never adjacent-tile fake seating.
            if not EmberRoutesProbeJava.moveSeatWithControl then phase='READ'
            else
                if not scan then
                    scan=Sites.new(c.actor,c.npc,c.job.npcId,'REST',failedSeats,
                        {seatingOnly=true,excludeBeds=true,
                            preferredPoint=c.payload.leisureMemory and c.payload.leisureMemory.seatPreference})
                end
                if c.budget.scan<1 then
                    return 'Running'
                else
                    local slice=math.min(8,c.budget.scan) c.budget.scan=c.budget.scan-slice
                    local candidate,done,why=scan:step(slice)
                    if candidate then
                        local proof=Sites.prepare(candidate,c.actor,c.npc,c.job.npcId,'REST')
                        if proof then
                            local previous=c.payload.claims local keys={}
                            for _,key in ipairs(previous) do keys[#keys+1]=key end
                            for _,key in ipairs(Sites.keys(proof,'REST')) do keys[#keys+1]=key end
                            c.payload.readingSite=proof c.payload.claims=keys
                            if not c.persist() then return 'Failure' end
                            if Store.extendPersonal(c.job,c.token) then
                                Log.write('STUDY_SEAT','Found seat proof='..tostring(proof.key)..' npc='..tostring(c.job.npcId))
                                move=require('EmberRoutesProbe/SelfCareFurniture').seat(c,proof) phase='MOVE'
                            else
                                c.payload.readingSite=nil c.payload.claims=previous
                                if not c.persist() then return 'Failure' end
                                return standFallback('READ_SEAT_CHANGED',proof)
                            end
                        else return standFallback('READ_SEAT_CHANGED',candidate) end
                    elseif done or why and why~='SITE_OBSERVING' and why~='SITE_UNAVAILABLE' then
                        standingReason='READ_'..tostring(why or 'NO_SEAT')
                        Log.write('STUDY_SEAT','No seat candidate npc='..tostring(c.job.npcId)..' reason='..tostring(standingReason))
                        require('EmberRoutesProbe/LeisureService').note(c.job.npcId,standingReason)
                        phase='READ'
                    else
                        require('EmberRoutesProbe/LeisureService').note(c.job.npcId,'READ_SEAT_OBSERVING')
                        return 'Running'
                    end
                end
            end
        end
        if phase=='MOVE' then
            local state=move.run()
            if state=='Running' then return state end
            if state=='Failure' then return standFallback('READ_SEAT_UNREACHABLE') end
            site=Sites.resolve(c.payload.readingSite,c.actor,c.npc,c.job.npcId,'REST',c.job.id)
            if not site then return standFallback('READ_SEAT_CHANGED') end
            if not c.body.repose('REST',true,site.object,site.quality) then return standFallback('READ_SEAT_CHANGED') end
            Log.write('STUDY_SEAT','Arrived at seat, entering posture npc='..tostring(c.job.npcId))
            posture=require('EmberRoutesProbe/LeisurePosture').new(c,site.object) phase='ENTER'
        end
        if phase=='ENTER' then
            if not Sites.resolve(c.payload.readingSite,c.actor,c.npc,c.job.npcId,'REST',c.job.id) then
                return standFallback('READ_SEAT_CHANGED')
            end
            local state=posture.enter()
            if state=='Failure' then return standFallback('READ_SEAT_CHANGED') end
            if state~='Success' then return 'Running' end
            -- Vanilla ISRestAction is just the seating transition here. Reading
            -- uses native sitting benefits, not the active REST modifier.
            if not c.body.repose('REST',false) then return 'Failure' end
            Log.write('STUDY_SEAT','Seated posture confirmed, beginning book reading npc='..tostring(c.job.npcId))
            phase='READ'
        end
        if phase=='READ' then
            if not c.payload.readingSite and not notedStanding then
                notedStanding=true
                Log.write('STUDY_SEAT','Standing reading started npc='..tostring(c.job.npcId)..' reason='..tostring(standingReason or 'READ_STANDING'))
                require('EmberRoutesProbe/LeisureService').note(c.job.npcId,standingReason or 'READ_STANDING')
            end
            if c.payload.readingSite and not Sites.resolve(c.payload.readingSite,c.actor,c.npc,c.job.npcId,'REST',c.job.id) then
                c.reason='SITE_CHANGED' return 'Failure'
            end
            local state=read.run()
            if state~='Success' then return state end
            phase='LEAVE' exitDeadline=getTimestampMs()+8000
        end
        if phase=='LEAVE' or phase=='FALLBACK' then
            if clearSeat() then
                if phase=='LEAVE' then return 'Success' end
                if retrySeat then
                    retries=retries+1 retryAt=getTimestampMs()+Config.readingSeatRetryMs
                    scan,move,posture,site=nil,nil,nil,nil
                    phase='RETRY'
                    require('EmberRoutesProbe/LeisureService').note(c.job.npcId,'READ_SEAT_RETRY')
                else phase='READ' end
                return 'Running'
            end
            if getTimestampMs()>exitDeadline then c.reason='SIT_EXIT_TIMEOUT' return 'Failure' end
        end
        return 'Running'
    end,halt=function()
        -- Stop the reading action before requesting get-up; the same original
        -- is reconciled by StudyActions and existing return obligations.
        if phase=='READ' and not read.halt() then return false end
        if move and phase=='MOVE' then move.halt() end
        if posture then posture.leave() end
        c.body.repose('REST',false)
        return not c.payload.readingSite or S.release(c)
    end}
end
function S.exit(c)
    local requested=false
    local deadline
    return {
        kind='Action',
        run=function()
            if not c.payload.readingSite then return 'Success' end
            deadline=deadline or (getTimestampMs()+8000)
            local seated=c.npc:isSittingOnFurniture() or c.npc:getSitOnFurnitureObject()~=nil
            if seated then
                if not requested then
                    c.npc:setVariable('forceGetUp',true)
                    requested=true
                end
                if getTimestampMs()>deadline then
                    c.reason='SIT_EXIT_TIMEOUT'
                    return 'Failure'
                end
                return 'Running'
            end
            if not c.body.repose('REST',false) then return 'Running' end
            if not S.release(c) then return 'Failure' end
            return 'Success'
        end
    }
end
return S
