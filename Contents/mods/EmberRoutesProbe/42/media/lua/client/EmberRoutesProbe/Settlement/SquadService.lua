-- Presentation session only: Membership remains the command/roster authority.
local Membership=require 'EmberRoutesProbe/Settlement/MembershipService'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Personnel=require 'EmberRoutesProbe/Settlement/PersonnelService'
local Names=require 'EmberRoutesProbe/Warehouse/DisplayNames'
local T=require 'EmberRoutesProbe/Settlement/MembershipText'
local Service={}
local Session={} Session.__index=Session
local function label(key) return getText('IGUI_EmberRoutesProbe_Squad_'..key) end
local function reasonText(code)
    local key='IGUI_EmberRoutesProbe_Membership_'..code
    local value=getTextOrNull(key)
    return value and value~=key and value or T.reason('BLOCKED')
end
local motionKeys={FOLLOW_ACTIVE='following',FOLLOW_WAITING='inPosition',FOLLOW_QUEUED='queued',
    FOLLOW_YIELD_SIDE='yielding',FOLLOW_YIELD_BACK='yielding',FOLLOW_TRAVERSAL='traversal',
    FOLLOW_WAIT_VEHICLE='vehicleWait',FOLLOW_TIMEOUT='blocked',FOLLOW_PATH_FAILED='blocked'}
local moodles={
    {key='BLEEDING',label='bleeding',minimum=1,tone='RECONCILE'},
    {key='SICK',label='sick',minimum=2,tone='WAITING'},
    {key='PAIN',label='pain',minimum=2,tone='WAITING'},
    {key='ENDURANCE',label='exhausted',minimum=3,tone='WAITING'},
    {key='PANIC',label='panic',minimum=3,tone='WAITING'},
    {key='HEAVY_LOAD',label='heavyLoad',minimum=3,tone='WAITING'},
    {key='TIRED',label='tired',minimum=3,tone='WAITING'},
    {key='HUNGRY',label='hungry',minimum=3,tone='WAITING'},
    {key='THIRST',label='thirsty',minimum=3,tone='WAITING'}}
local function readMood(npc)
    local result={}
    local values=npc and npc.getMoodles and npc:getMoodles()
    if not values or not MoodleType then return result end
    for _,def in ipairs(moodles) do
        local kind=MoodleType[def.key]
        local level=kind and values:getMoodleLevel(kind)
        if level and level>=def.minimum then
            result[#result+1]={label=label(def.label),tone=def.tone,level=level}
        end
    end
    return result
end
function Service.new(actor,owner)
    return setmetatable({actor=actor,owner=owner,world=Registry.data(),dirty=true,nextRefresh=0,nextDirty=0,leader=Membership.character(actor),
        rows={},receipts={},portraitIds={}},Session)
end
function Session:valid()
    return not self.closed and self.world==Registry.data() and self.actor and not self.actor:isDead()
end
function Session:invalidate(id)
    if id and not self.portraitIds[id] then
        local row=Membership.view(id)
        if not row or row.squadLeaderId~=self.leader then return end
    end
    self.dirty=true
end
function Session:close()
    if self.closed then return end
    self.closed=true
    for id in pairs(self.portraitIds) do Personnel.releasePortrait(id,self.owner) end
    self.portraitIds={} self.rows={} self.receipts={}
end
function Session:refresh(now)
    if not self:valid() then return false end
    if now<self.nextRefresh and (not self.dirty or now<self.nextDirty) then return false end
    self.dirty=false self.nextRefresh=now+500 self.nextDirty=now+100
    local rows,portraits={},{}
    local runtime=Runtime.current()
    for _,id in ipairs(Membership.squad(self.actor)) do
        local member=Membership.view(id)
        local binding=Driver.bindId(self.actor,id)
        local npc=binding and Driver.valid(binding) and binding.handle or nil
        local status=runtime and runtime:status(id)
        local care=require('EmberRoutesProbe/SelfCare/SelfCare').activity(id)
        local motion=npc and EmberRoutesProbeJava and EmberRoutesProbeJava.motionResult(npc)
        local actual=not npc and label('unavailable') or status and status.state=='STOPPING' and label('stopping')
            or care and label('selfCare') or status and not status.started and label('starting')
            or status and status.kind=='COMPANION' and label(motionKeys[motion] or 'starting')
            or status and status.kind=='MEMBERSHIP_RETURN' and label('returning')
            or status and label('working') or label('idle')
        local health
        if npc and npc.getBodyDamage then
            local damage=npc:getBodyDamage()
            if damage then health=damage:getOverallBodyHealth() end
        end
        local request=self.receipts[id]
        local result=request and (Membership.result(id,request.requestId) or request)
        local receiptText=''
        if result then
            if result.reason then receiptText=reasonText(result.reason)
            elseif result.state=='COMMITTED' then
                if member.lastCommand and member.lastCommand.requestId==result.requestId then
                    receiptText=label(member.pending and 'superseded' or 'applied')
                else receiptText=label('superseded') end
            else receiptText=T.reason(result.state) end
        end
        local reason=member.reason
        if reason=='COMMAND_PENDING' then reason=nil end
        if not reason and (motion=='FOLLOW_TIMEOUT' or motion=='FOLLOW_PATH_FAILED') then reason='FOLLOW_BLOCKED' end
        local portrait=Personnel.squadPortrait(self.actor,id,self.owner)
        portraits[id]=true
        rows[#rows+1]={id=id,revision=member.revision,slot=member.squadSlot,
            moods=readMood(npc),loaded=npc~=nil,name=Names.name(id,npc),portrait=portrait and (portrait.texture or portrait.icon),
            health=health,healthText=health and (label('health')..' '..tostring(math.floor(health))..'%') or label('healthUnknown'),
            command=label('command')..': '..T.reason(member.pending and member.pending.kind or member.context),
            actual=label('actual')..': '..actual,
            feedback=reason and reasonText(reason) or member.pending and label('pending') or receiptText,
            blocked=reason~=nil,pending=member.pending~=nil}
    end
    for id in pairs(self.portraitIds) do if not portraits[id] then Personnel.releasePortrait(id,self.owner) end end
    self.portraitIds=portraits self.rows=rows return true
end
-- Capture IDs/revisions/slots at wheel-open time; selection changes never retarget a command.
function Session:targets(selected)
    local result={} local any=false
    for _,row in ipairs(self.rows) do if selected[row.id] then any=true break end end
    for _,row in ipairs(self.rows) do if not any or selected[row.id] then
        local member=Membership.view(row.id)
        if member and not member.retired and member.squadLeaderId==self.leader then
            result[#result+1]={id=row.id,revision=member.revision,slot=member.squadSlot}
        end
    end end
    return result
end
function Session:command(targets,kind,slot)
    if not self:valid() then return {} end
    local allowed={FOLLOW=true,WAIT=true,RETURN=true,DISMISS=true}
    if not allowed[kind] or slot~=nil and (kind~='FOLLOW' or #targets~=1) then return {} end
    local results={} local leader=Membership.character(self.actor)
    for _,target in ipairs(targets) do
        local member=Membership.view(target.id)
        local result
        if not member or member.retired or member.squadLeaderId~=leader then
            result={state='REJECTED',reason='NO_MEMBERSHIP'}
        else
            result=Membership.request(self.actor,target.id,{kind=kind,expectedRevision=target.revision,
                requestId=Registry.id(),followSlot=kind=='FOLLOW' and (slot~=nil and slot or target.slot) or nil})
        end
        self.receipts[target.id]=result results[#results+1]={id=target.id,result=result}
    end
    self.dirty=true return results
end
return Service
