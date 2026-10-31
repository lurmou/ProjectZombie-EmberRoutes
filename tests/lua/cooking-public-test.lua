-- End-to-end provider admission/recovery with real selection, Jobs and Runtime.
local prior=dofile('tests/lua/cooking-handoff-test.lua') local h=prior.h local f=h.f local npc=f.npc
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Directory=require 'EmberRoutesProbe/TaskDirectory'
local Observer=require 'EmberRoutesProbe/NeedsObserver'
local Work=require 'EmberRoutesProbe/Work'
local root={containers={},taskJobs={format=1,byId={}},npcMembership={format=1,byNpc={}}}
Registry.data=function() return root end
h.entry.factionId='f'
root.npcMembership.byNpc[npc.id]={npcId=npc.id,settlementId=h.entry.id,factionId='f',context='SETTLEMENT'}
local now=100000
function getTimestampMs() return now end
function getGameTime() return {getWorldAgeHours=function() return now/3600000 end} end
Observer.sample=function() return {safe=true,observedAt=now} end
function npc:isOnFire() return false end function npc:getSurroundingAttackingZombies() return 0 end
Work.busy=function() return false end Work.hasCargo=function() return false end
package.loaded['EmberRoutesProbe/PublicWork']={priorities=function() return {cooking=3} end}
EmberRoutesProbeJava.carrierFor=function(id) if id==npc.id then return npc end end
EmberRoutesProbeJava.workerCount=function() return 1 end EmberRoutesProbeJava.workerIdAt=function() return npc.id end
local runtime=Runtime.new() Runtime.current=function() return runtime end
local recipe=h.e.recipe
function recipe:getItemRecipe(item) if item.food then return {getUse=function() return 10 end} end end
function recipe:needToBeCooked() return true end
function getScriptManager() return {getAllEvolvedRecipes=function() return f.list({recipe}) end,
    getItem=function(_,id) if id=='Base.PotOfSoupRecipe' then return {getActualWeight=function() return 3 end} end end} end
local source=h.endpoint('auto-stock',4,{'Base.Pot','Base.Carrot','Base.Potato'})
function source.container:isFridge() return false end function source.container:isFreezer() return false end
function source.container:isPowered() return true end function source.container:getTemperature() return 1 end
local cold=h.fridge('auto-cold',5) local stove=h.stove('auto-stove')
h.setCandidates({source.id,cold.id,stove.id})
local pot=f.item('Base.Pot',false,source.container)
pot.fluid={amount=10,capacity=10,kind='Water',getAmount=function(self) return self.amount end,
 getCapacity=function(self) return self.capacity end,isPureFluid=function() return true end,
 isFilledWithCleanWater=function() return true end}
function pot:getFluidContainer() return self.fluid end
for _=1,4 do f.item('Base.Carrot',true,source.container) end
local Service=require 'EmberRoutesProbe/CookingService'
local directory=Directory.new() local provider=Service.provider
local env={actor=f.fixture.actor,npc=npc,npcId=npc.id,entry=h.entry,candidates={},now=now,
 upsertOffer=function(key,revision,category,scope) return directory:upsert(key,revision,category,scope) end}
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
provider.discover(env)
check(env.pending and #env.candidates==0,'partial provider observation keeps discovery pending without reserving a body')
for _=1,300 do
 now=now+50 env.now=now provider.advance({actor=env.actor,now=now}) env.candidates={} provider.discover(env)
 if #env.candidates>0 then break end
end
local selected=assert(env.candidates[1],tostring(Service.status(npc.id)))
check(directory:claim(selected.key,selected.revision,npc.id,'auto-job'),'existing public directory arbitrates one cooking offer')
check(provider.claim(selected,npc.id,'auto-job',{actor=env.actor,entry=h.entry,now=now,directory=directory})=='QUEUED',
 'provider prepares original claims and submits to existing Runtime')
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local stopped=false local active=false
for _=1,600 do
 now=now+50 runtime:step()
 local action=f.queued()
 if action then action:start() if action.complete then action:complete() end action:perform()
  if not f.queued() then ISTimedActionQueue.queues[npc]={queue={}} end end
 local j=Jobs:peek('auto-job')
 if stove.object.active and not stopped then
  active=true stopped=true assert(runtime:stop(npc.id,'SAVE'))
 end
 provider.advance({actor=env.actor,now=now})
 if j and j.state=='CANCELLED' then break end
end
local final=Jobs:get('auto-job')
check(active and final.state=='CANCELLED' and not final.payload.duty and not stove.object.active,
 'normal-stop recovery automatically resumes, drains and closes the saved Duty')
check(final.payload.expected==0 and #final.payload.claims==0,'recovered unfinished batch returns originals without creating ready food')
provider.reconcile()
check(directory:upsert(selected.key,1,'cooking',h.entry.id).jobId==nil,'only settled original Job releases its public offer')
check(not Service.retained(npc.id),'settled cooking no longer blocks other ordinary work')
-- Self-care uses the existing predecessor relation, rather than starving behind a COOKING kind.
local Resume=require 'EmberRoutesProbe/TaskResume'
local Care=require 'EmberRoutesProbe/SelfCareRecord'
local pot2=f.item('Base.Pot',false,source.container) pot2.fluid=pot.fluid
function pot2:getFluidContainer() return self.fluid end
-- Fixture mutations bypass native container events; publish the same stock
-- invalidation so the shared failure backoff observes these new originals.
for _,notify in ipairs(Registry.inventoryListeners or {}) do notify(source.id) end
env.candidates={} provider.discover(env)
for _=1,300 do
 now=now+50 env.now=now provider.advance({actor=env.actor,now=now}) env.candidates={} provider.discover(env)
 if #env.candidates>0 then break end
end
selected=assert(env.candidates[1],tostring(Service.status(npc.id)))
assert(directory:claim(selected.key,selected.revision,npc.id,'care-cooking'))
assert(provider.claim(selected,npc.id,'care-cooking',{actor=env.actor,entry=h.entry,now=now,directory=directory})=='QUEUED')
local careStarted,careFinished=false,false
for _=1,600 do
 now=now+50 runtime:step()
 local action=f.queued()
 if action then action:start() if action.complete then action:complete() end action:perform()
  if not f.queued() then ISTimedActionQueue.queues[npc]={queue={}} end end
 if stove.object.active and not careStarted then
  careStarted=true
  local personal=Care.create('cook-care',npc.id) personal.payload=assert(Care.begin(personal,'DRINK'))
  assert(Jobs:create(personal))
  check(Resume.prepare(env.actor,npc.id,personal.id),'cooking can be captured as a self-care predecessor')
  assert(runtime:stop(npc.id,'SELF_CARE'))
 end
 local j=Jobs:peek('care-cooking')
 if careStarted and not careFinished and j.state=='SUSPENDED' and not runtime:owns(npc.id) then
  assert(Resume.stopped({npcId=npc.id,jobId=j.id,kind='COOKING',state='CLOSED',reason='SELF_CARE',effects='KNOWN'}))
  local personal=Jobs:get('cook-care') personal.payload.step='IDLE'
  assert(Jobs:update(personal.id,personal.revision,{payload=personal.payload}))
  local _,why=Resume.resume(env.actor,npc.id,personal.id)
  check(why=='QUEUED','finished self-care queues same cooking Job without a blocksWork deadlock')
  careFinished=true
 elseif careFinished then Resume.resume(env.actor,npc.id,'cook-care') end
 provider.advance({actor=env.actor,now=now})
 if j.state=='CANCELLED' then break end
end
check(careFinished and Jobs:get('care-cooking').state=='CANCELLED','self-care recovery closes actual native stove responsibility')
provider.reconcile()
check(Service.retire(8)==2 and not Jobs:get('auto-job') and not Jobs:get('care-cooking') and Jobs:get('cook-care'),
 'normal-tick retirement frees settled cooking capacity and preserves personal facts')
-- An explicit request has the same physical/native execution path and reports
-- progress only after real output delivery, even though its estimate is larger.
function recipe:getName() return 'Soup' end
local Members=require 'EmberRoutesProbe/MembershipService'
Members.members=function() return {npc.id} end
local Orders=require 'EmberRoutesProbe/CookingOrders'
local request={id='soup-order',category='cooking',recipeId='evolved:Soup',settlementId=h.entry.id,
    product='Base.PotOfSoupRecipe',name='Soup',quantity=1,target=1,delivered=0,sequence=1,revision=1,state='WAITING'}
root.publicWork={orders={[request.id]=request}}
local readyMeal=f.item('Base.PotOfSoupRecipe',true,cold.container) readyMeal.cooked=true readyMeal.raw=.4
local requestPot=f.item('Base.Pot',false,source.container) requestPot.fluid=pot.fluid
function requestPot:getFluidContainer() return self.fluid end
for _=1,4 do f.item('Base.Carrot',true,source.container) end
env.candidates={} provider.discover(env)
for _=1,400 do
 now=now+50 env.now=now provider.advance({actor=env.actor,now=now}) env.candidates={} provider.discover(env)
 if env.candidates[1] and env.candidates[1].orderId==request.id then break end
end
selected=assert(env.candidates[1],tostring(Service.status(npc.id)))
check(selected.orderId==request.id,'specified food is offered without binding a cook in the request')
assert(directory:claim(selected.key,selected.revision,npc.id,'requested-soup'))
assert(provider.claim(selected,npc.id,'requested-soup',{actor=env.actor,now=now,directory=directory})=='QUEUED')
check(request.delivered==0 and request.jobId=='requested-soup','admission and predicted servings are not delivered progress')
for _=1,600 do
 now=now+50 runtime:step()
 local action=f.queued()
 if action then action:start() if action.complete then action:complete() end action:perform()
  if not f.queued() then ISTimedActionQueue.queues[npc]={queue={}} end end
 local j=Jobs:peek('requested-soup')
 if stove.object.active then for _,asset in ipairs(j.payload.assets) do
  if asset.role=='OUTPUT' then
   for _,held in ipairs(stove.container.items) do if held.id==asset.id then held.cooked=true end end
  end
 end end
 provider.advance({actor=env.actor,now=now})
 if request.state=='DONE' then break end
end
check(request.state=='DONE' and request.delivered==1 and not request.jobId,
 'actual cooked original delivered to cold storage settles one requested dish exactly once')
Orders.settle(Jobs:get('requested-soup'))
check(request.delivered==1,'repeated reconciliation cannot duplicate request progress')
print('PASS cooking public admission and automatic recovery; native engine mocked, game NOT RUN')
