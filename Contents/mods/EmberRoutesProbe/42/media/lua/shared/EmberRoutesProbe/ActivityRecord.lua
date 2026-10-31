-- Participant coordination outlives its short arrival/wait body Session.
-- FREE behavior uses existing personal Sessions after that Session stops.
local R={}
local steps={INVITED=true,WAITING=true,FREE=true,PERSONAL=true,LEAVING=true,SETTLED=true}
local function id(s) return type(s)=='string' and #s>0 and #s<=256 end
local function integer(n) return type(n)=='number' and n==n and n>=1 and n<9007199254740000 and n==math.floor(n) end
function R.create(id,npc,event)
    return {id=id,npcId=npc,providerType='ACTIVITY',scopeId=event.settlementId,revision=1,
        state='PREPARING',effects='KNOWN',obligations={},payload={format=1,eventId=event.id,
        controlEpoch=event.controlEpoch,participantEpoch=event.roster[npc].participantEpoch or 1,sequence=0,step='INVITED',claims={}}}
end
function R.valid(job)
    local p=job and job.payload
    if not p or job.providerType~='ACTIVITY' or p.format~=1 or not id(p.eventId)
        or not integer(p.controlEpoch) or p.participantEpoch~=nil and not integer(p.participantEpoch)
        or not steps[p.step] or type(p.claims)~='table' then return false end
    if p.sequence~=0 and not integer(p.sequence) then return false end
    local count=0
    if p.point~=nil then
        if type(p.point)~='table' then return false end
        for _,key in ipairs({'x','y','z'}) do
            local n=p.point[key] if type(n)~='number' or n~=n or math.abs(n)>10000000 then return false end
        end
        if p.point.z~=math.floor(p.point.z) then return false end
    end
    for key,value in pairs(p.claims) do
        count=count+1
        if count>1 or key~=1 or not p.point or p.sequence<1
            or value~=require('EmberRoutesProbe/LeisureRecord').tileKey(p.point) then return false end
    end
    if (p.step=='FREE' or p.step=='PERSONAL') and (count>0 or not p.started or not p.stopped) then return false end
    if p.step=='SETTLED' and (count>0 or p.started and not p.stopped) then return false end
    if p.started~=nil and type(p.started)~='boolean' or p.stopped~=nil and type(p.stopped)~='boolean' then return false end
    return true
end
return R
