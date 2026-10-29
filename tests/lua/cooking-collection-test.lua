-- Full same-Job collection/addition/heat/delivery, including suspension mid-mixture.
local h=dofile('tests/lua/cooking-heat-test.lua') local f=h.f local e=h.e
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Inventory=require 'EmberRoutesProbe/CookingInventory'
local Evolved=require 'EmberRoutesProbe/CookingEvolved'
local Agent=require 'EmberRoutesProbe/CookingAgent'
local Store=require 'EmberRoutesProbe/LaborStore'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
-- Installed PotOfSoupRecipe script weight. A missing native output script is
-- intentionally a production admission error, not a reason to weaken the gate.
local scriptManager={getItem=function(_,id)
    if id=='Base.PotOfSoupRecipe' then return {getActualWeight=function() return 3 end} end
end}
function getScriptManager() return scriptManager end
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/Entity/TimedActions/ISHandcraftAction.lua')
package.loaded['Entity/TimedActions/ISHandcraftAction']=true
local source=h.endpoint('collection-stock',5,{'Base.Pot','Base.Carrot','Base.Potato'})
local cold=h.fridge('collection-cold',4) local stove=h.stove('collection-stove')
h.setCandidates({source.id,cold.id,stove.id})
local old,pot=e.setup({})
local released=Record.copy(old.job) Inventory.release(released,pot.id,'RETURNED') assert(Context.publish(old,released))
f.root:Remove(pot) source.container.items[#source.container.items+1]=pot pot.container=source.container
pot.fluid.amount=10
local a=f.item('Base.Carrot',true,source.container) local b=f.item('Base.Potato',true,source.container)
local job=assert(Record.new('collection-job',f.npc.id,'kitchen','Soup','AUTO','policy:kitchen',.12,.2))
local selection={base={id=pot.id,item=pot,endpoint=source},entries={
    {id=a.id,item=a,endpoint=source},{id=b.id,item=b,endpoint=source}}}
local prepared=assert(Evolved.prepare(job,e.recipe,selection))
check(prepared.payload.evolved.originSourceId==source.id and prepared.payload.evolved.inputs[1].sourceId==source.id,
    'base and every ingredient keep original warehouse provenance')
check(prepared.payload.assets[1].custody=='SOURCE' and not Store.owner(pot.id),
    'preparing the immutable plan does not move or claim originals')
selection.entries[2]=selection.entries[1]
check(not Evolved.prepare(job,e.recipe,selection),'duplicate ingredient original cannot occupy two positions')
assert(Jobs:create(prepared))
local function start(saved,settleOnly)
    local spec,c=assert(Agent.new(f.fixture.actor,{id=f.npc.id,handle=f.npc},saved,nil,
        function() return {nodes=24,scan=16,paths=1} end,function() return true end,
        {evolvedRecipe=e.recipe,settleOnly=settleOnly}))
    local runtime=Runtime.new() local handle=assert(runtime:submit(spec))
    return {r=runtime,h=handle,c=c}
end
local t=start(Jobs:get(job.id))
h.untilState(t,function()
    local p=t.c.job.payload
    return p.attempt and p.attempt.kind=='ADD' and p.attempt.state=='APPLIED' and p.evolved.cursor==1
end)
check(pot:getContainer()==nil and a:getContainer()==f.root and b:getContainer()==f.root,
    'Agent fetched exact base and both ingredients, then followed the native replacement')
assert(t.r:stop(f.npc.id,'SELF_CARE')) h.finish(t)
check(t.c.job.state=='SUSPENDED' and not t.c.job.payload.evolved.completed,
    'mid-mixture interruption retains incomplete same Job and original claims')
local forged=Record.copy(t.c.job) forged.payload.evolved.originSourceId='different-stock'
check(not Jobs:update(forged.id,forged.revision,{payload=forged.payload}),
    'saved provenance cannot be silently redirected after a partial effect')
t=start(t.c.job)
h.untilState(t,function() return stove.object.active end)
local p=t.c.job.payload local output=assert(Record.resolveOutput(t.c.job,Record.outputReference(t.c.job,p.evolved.baseSequence,1)))
local item=t.c.items[output.id]
check(item.extra:size()==2 and p.evolved.completed,'resume acknowledges first receipt and adds only the remaining ingredient')
item.cooked=true h.finish(t)
check(t.c.closed and t.c.job.state=='DONE' and item:getContainer()==cold.container and not stove.object.active,
    'automatically collected mixture completes heat, original delivery and conditional shutdown under existing Runtime')
check(a:getContainer()==source.container and b:getContainer()==source.container and not Store.owner(a.id) and not Store.owner(b.id),
    'partially used borrowed ingredients return to their actual source and release claims')
-- Cancel at the narrow receipt-before-cursor boundary, with no usable stove.
old,pot=e.setup({}) released=Record.copy(old.job)
Inventory.release(released,pot.id,'RETURNED') assert(Context.publish(old,released))
f.root:Remove(pot) source.container.items[#source.container.items+1]=pot pot.container=source.container pot.fluid.amount=10
a=f.item('Base.Carrot',true,source.container) b=f.item('Base.Potato',true,source.container)
job=assert(Record.new('collection-cancel',f.npc.id,'kitchen','Soup','AUTO','policy:kitchen',.12,.2))
prepared=assert(Evolved.prepare(job,e.recipe,{base={id=pot.id,item=pot,endpoint=source},entries={
    {id=a.id,item=a,endpoint=source},{id=b.id,item=b,endpoint=source}}}))
assert(Jobs:create(prepared)) t=start(Jobs:get(job.id))
h.untilState(t,function()
    local p=t.c.job.payload
    return p.attempt and p.attempt.kind=='ADD' and p.attempt.state=='APPLIED' and p.evolved.cursor==1
end)
assert(t.r:stop(f.npc.id,'USER_CANCEL')) h.finish(t)
stove.object.powered=false h.setCandidates({source.id,cold.id})
t=start(t.c.job,true) h.finish(t)
check(t.c.closed and t.c.job.state=='CANCELLED' and t.c.job.payload.expected==0 and not stove.object.active,
    'cancelled partial mixture is returned without requesting an unused stove or opening fire')
local returned
for _,asset in ipairs(t.c.job.payload.assets) do if asset.role=='OUTPUT' then returned=asset end end
check(returned and returned.custody=='RETURNED' and t.c.items[returned.id]:getContainer()==cold.container,
    'receipt-before-cursor cancellation keeps actual replacement, returns it cold, and credits no meal')
print('PASS cooking collection/resume boundaries; engine effects mocked, game NOT RUN')
return {h=h,source=source,cold=cold,stove=stove}
