-- User regression: three saw-log batches must fit one batch at a time.
-- Installed native Lua action path; bodies, inventory and craft effects mocked.
local f=dofile('tests/lua/craft-probe-test.lua')
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
f.Probe.controlledExecution=false
local _,saw=f.fresh(3)
f.npc.maxWeight=8 saw.weight=1
local logs={}
for i=0,f.materials.container:getItems():size()-1 do
    local item=f.materials.container:getItems():get(i)
    if item:getFullType()=='Base.Log' then item.weight=9 logs[#logs+1]=item end
end
check(#logs==3 and 28>f.npc:getMaxWeight()*1.5,'all three logs cannot fit at once')
local request=require('EmberRoutesProbe/ProductionChain').new(f.actor,f.npc,f.entry,f.recipe.key,9,nil,'offer:three',false)
local plan,reason
for _=1,2000 do plan,reason=request:step() if plan or reason then break end end
check(plan and not reason and #plan.assets==4,'public preclaim admits three logs and one reusable saw by single-batch capacity')
check(not f.Craft.record(f.npc.id) and not f.Store.owner(logs[1].id),'preclaim moves and claims no originals')
check(f.Craft.execute(f.actor,'run',nil,f.npc.id,true,{recipeId=f.recipe.key,quantity=9,
    orderId='three-batch-demand',chain=true,nonPreemptive=true})=='STARTED','public-style three-batch demand starts')
local peak,mostLogs=0,0
for _=1,3000 do
    f.tick(true)
    local count=0 for _,log in ipairs(logs) do if log.container==f.npc.root then count=count+1 end end
    mostLogs=math.max(mostLogs,count)
    peak=math.max(peak,f.npc.root:getCapacityWeight())
    if not f.Work.busy(f.npc.id) then break end
end
local record=f.Craft.record(f.npc.id)
check(record.state=='DONE' and record.target==9 and record.produced==9 and record.delivered==9 and f.nativeCalls()==3,
    'three original logs become nine verified delivered planks through exactly three commits: '..tostring(record.reason))
check(mostLogs==1 and peak<=10+0.001,'one log carried at a time; prior outputs delivered before next collection')
check(saw.container==f.tools.container and not f.Store.owner(saw.id),'one original saw reused and finally returned')
print('PASS '..checks..' three-batch saw-log checks; peak='..peak..'; native effects mocked, game NOT RUN')
