-- Real Job/Claims/Runtime transfer and recipient action chain; native world mocked.
local h=dofile('tests/lua/cooking-heat-test.lua') local f=h.f local npc=f.npc
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local Record=require 'EmberRoutesProbe/CookingRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Context=require 'EmberRoutesProbe/CookingContext'
local Agent=require 'EmberRoutesProbe/CookingAgent'
local Handoff=require 'EmberRoutesProbe/CookingHandoff'
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local t=h.preparation(false)
h.untilState(t,function() return t.stove.object.active end)
local held=false for _,a in ipairs(t.c.job.payload.assets) do if a.custody=='HELD' then held=true end end
check(not held,'borrowed leftovers return before opening fire so world Duty can be transferred')
local recipient=setmetatable({id='relief-cook',root=f.fixture.fixture.ctx.newContainer(),actions=f.list({}),alive=true},
    {__index=npc})
function recipient.root:getCapacityWeight() return #self.items end
function recipient.root:getEffectiveCapacity() return 150 end
local bridge=EmberRoutesProbeJava
bridge.bindingValid=function(body,id) return (body==npc or body==recipient) and body.id==id end
bridge.carrierActive=function() return true end
local binding={id=recipient.id,handle=recipient}
Runtime.current=function() return t.r end
check(not Handoff.transfer(f.fixture.actor,t.c.job,binding),'running donor cannot hand off its live body or stove')
assert(t.r:stop(npc.id,'SELF_CARE')) h.finish(t)
local before=t.c.job
check(before.payload.stopProof and before.payload.stopProof.bodyStopped,'confirmed stop persists a sequence-fenced transfer proof')
local unknown=Record.copy(before) unknown.effects='UNKNOWN'
check(not Record.handoff(unknown,recipient.id),'unknown effect cannot become an automatic transfer')
local changed=assert(Handoff.transfer(f.fixture.actor,before,binding))
check(changed.id==before.id and changed.npcId==recipient.id and changed.payload.duty.id==before.payload.duty.id
    and changed.payload.duty.revision==before.payload.duty.revision+1,'one atomic transfer keeps Job and Duty identity and advances ownership version')
check(not Context.current(t.c),'old context loses revision/token authority immediately after transfer')
check(Store.owner(t.ids[1]).taskId==before.id and Store.resourceOwner(changed.payload.duty.siteKey).taskId==before.id,
    'food and device declarations never release or change to a second Job')
local donorHas=false local receiverHas=false
Jobs:visitNpc(npc.id,function(j) if j.id==changed.id then donorHas=true end end)
Jobs:visitNpc(recipient.id,function(j) if j.id==changed.id then receiverHas=true end end)
check(not donorHas and receiverHas,'persistent owner and both live NPC indexes agree')
check(not Handoff.transfer(f.fixture.actor,before,binding),'duplicate stale transfer cannot submit a second owner')
ISTimedActionQueue.add=function(action)
    f.queue(action) ISTimedActionQueue.queues[action.character]={queue={action},current=action}
end
ISTimedActionQueue.clear=function(character)
    local action=f.queued() if action then action:stop() end f.queue(nil)
    ISTimedActionQueue.queues[character or recipient]={queue={}}
end
local spec,c=assert(Agent.new(f.fixture.actor,binding,changed,nil,
    function() return {nodes=24,scan=16,paths=1} end,function() return true end,{settleOnly=true}))
local r=Runtime.new() local handle=assert(r:submit(spec)) Runtime.current=function() return r end
for _=1,400 do
    r:step() local action=f.queued()
    if action then action:start() if action.complete then action:complete() end action:perform()
        if not f.queued() then ISTimedActionQueue.queues[recipient]={queue={}} end end
    if r:inspect(handle).state=='CLOSED' then break end
end
check(c.closed and c.job.state=='CANCELLED' and not c.job.payload.duty and not t.stove.object.active,
    'recipient really drains same stove: '..tostring(c.reason)..' '..c.job.state..' '..tostring(r:inspect(handle).error))
check(c.items[t.ids[1]]:getContainer()==t.a.container and c.job.payload.expected==0,
    'unfinished original reaches cold storage without reheating or claiming a finished meal')
print('PASS cross-cook same-Job handoff/recovery boundaries; native engine mocked, game NOT RUN')
return {h=h,recipient=recipient}
