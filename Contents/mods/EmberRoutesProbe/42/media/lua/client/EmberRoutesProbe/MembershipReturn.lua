-- One return attempt is a normal runtime session; no teleport and no private scheduler.
local S=require 'EmberRoutesProbe/MembershipService'
local Driver=require 'EmberRoutesProbe/Driver'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Policy=require 'EmberRoutesProbe/MembershipPolicy'
local R={}
function R.start(actor,binding,member)
    local entry,why=S.entry(binding.id) if not entry then return nil,why end
    local saved=entry.returnPoint if not saved then return nil,'RETURN_POINT_MISSING' end
    local entryRevision=entry.revision
    local p={x=saved.x,y=saved.y,z=saved.z,revision=saved.revision}
    local square=getCell() and getCell():getGridSquare(math.floor(p.x),math.floor(p.y),p.z)
    if not square then return nil,'TARGET_UNLOADED' end
    if not square:isFree(false) then return nil,'RETURN_POINT_BLOCKED' end
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    local world=Registry.data() local jobId=Registry.id() local body,done,arrived,reason
    local deadline=getTimestampMs()+35000
    local function same()
        local row=S.view(binding.id) local e=S.entry(binding.id)
        return Registry.data()==world and row and not row.pending and row.revision==member.revision
            and e and e.revision==entryRevision and e.returnPoint and e.returnPoint.revision==p.revision
    end
    local handle,failed=runtime:submit({npcId=binding.id,jobId=jobId,kind='MEMBERSHIP_RETURN',binding=binding,nonPreemptive=true,
        validate=same,
        start=function(grant)
            body=grant local ok,result=body.move(actor,p)
            return ok and type(result)=='string' and string.find(result,'^MOVE_REQUESTED')~=nil,result
        end,
        tick=function()
            if not same() then done=true reason='STALE_MEMBERSHIP' return end
            local n=binding.handle
            local motion=EmberRoutesProbeJava.motionResult(n)
            if motion=='REACHED' then
                arrived=Policy.inside(entry,{x=n:getX(),y=n:getY()}) and math.abs(n:getZ()-p.z)<0.5
                    and (n:getX()-p.x)^2+(n:getY()-p.y)^2<=4
                reason=arrived and nil or 'RETURN_NOT_REACHED' done=true
            elseif motion~='MOVING' or getTimestampMs()>=deadline then done=true reason='RETURN_UNREACHABLE' end
        end,
        finished=function() return done==true end,
        stopAdapter=function(controller,ticket)
            return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,npc=binding.handle,
                npcId=binding.id,jobId=jobId,same=function() return Registry.data()==world and Driver.valid(binding) end,
                pause=function() return true end,effects=function() return 'KNOWN' end,persist=function() return true end})
        end,
        persistFailure=function() if same() then S.note(binding.id,'RETURN_UNREACHABLE') end return true end})
    if not handle then return nil,failed end
    return {handle=handle,revision=member.revision,entryRevision=entryRevision,
        outcome=function() return arrived==true,reason end}
end
return R
