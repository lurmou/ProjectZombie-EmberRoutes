-- Real planner/service/worker adapters; native path and transfer host deliberately fake.
local world=dofile("tests/lua/multi-worker-test.lua")
local f=world.fixture local actor,a,b=world.actor,world.a,world.b
local Work=world.Work
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Store=require "EmberRoutesProbe/LogisticsStore"
local Service=require "EmberRoutesProbe/LogisticsService"
local Claims=require "EmberRoutesProbe/LaborStore"
local count=0 local function check(value,message) count=count+1 assert(value,message) end
local originalPrint=print print=function() end
function actor:getIndex() return 0 end
world.select(a.id) Work.execute(actor,"clear") world.select(b.id) Work.execute(actor,"clear")
local area={x=0,y=0,w=40,h=10}
actor.x=4.5
local entry=assert(Ledger.commit(actor,nil,"Logistics test",area))
local function container(x,types,role,private)
    local object=f.object(x) actor.x=x+0.5
    local filter=Filter.new() filter.private=private==true
    for _,id in ipairs(types) do filter.types[id]=true end
    check(Registry.configure(actor,object,filter,object.container)=="FILTER_CONFIGURED","configure real endpoint filter")
    if not private then check(Registry.configureLogistics(actor,object,object.container,role or "STORAGE")=="ROLE_CONFIGURED","configure role independent of filter") end
    return object
end
local input=container(4,{},"INPUT")
local food=container(12,{"food"})
local tools=container(8,{"tool"})
local wrong=container(6,{"tool"})
local correct=container(16,{"food"})
local private=container(10,{"food"},nil,true)
local untagged=f.object(14)
local originals={}
for i=1,3 do originals[i]=f.item("food",input.container) end
local tool=f.item("tool",input.container)
local misplaced=f.item("food",wrong.container)
local keep=f.item("food",correct.container)
local unknown=f.item("unknown",input.container)
local favorite=f.item("food",input.container) favorite.favorite=true
local secret=f.item("food",private.container)
local personal=f.item("food",untagged.container)
function private.container:getItems() error("private inventory must never be read by logistics") end
for _,npc in ipairs({a,b}) do
    npc.x=0.5
    function npc:getMaxWeight() return self.maxWeight or 10 end
    function npc:getInventoryWeight()
        local weight=0 for _,item in ipairs(self.root.items) do weight=weight+item:getUnequippedWeight() end return weight
    end
    function npc.root:getFreeCapacity() return 10-#self.items end
    function npc.root:hasRoomFor(_,item) return self:getFreeCapacity()>=item:getUnequippedWeight() end
end
actor.x=4.5
check(Service.addNearby(actor,entry.id)=="WORKERS_ADDED","one intent adds available settlement workers")
check(#Store.view(entry.id).workers==2,"shared two-worker pool")
check(Service.start(actor,entry.id)=="STARTED","start both modes together")

-- Keep one consumer so another worker's state event cannot hide a missing signal.
Service.removeWorker(actor,entry.id,b.id)
local eventMiddle,actualMiddle,collect,deliver=0,0,false,false
local seenCompleted=false
local release=Service.watch(entry.id,function(snapshot)
    for _,row in ipairs(snapshot.workers) do
        if row.delivered>0 and row.delivered<row.total then eventMiddle=eventMiddle+1 end
        if row.phase=="COLLECT" then collect=true elseif row.phase=="DELIVER" then deliver=true end
        if row.lastCompleted and row.taskId~=row.lastCompleted.id then
            assert(row.lastCompleted.delivered==row.lastCompleted.total,"completion summary must be verified")
            seenCompleted=true
        end
    end
end)
local checkedClaims=false
for _=1,500 do
    Service.tick() world.tick(1,true)
    local record=Work.record(a.id)
    if record and record.delivered>0 and record.delivered<#record.items then actualMiddle=actualMiddle+1 end
    if record and record.state=="RUNNING" and not checkedClaims then
        for _,id in ipairs(record.items) do assert(Claims.owner(id),"active manifest original must remain claimed") end
        local planner=assert(require("EmberRoutesProbe/LogisticsPlanner").new(entry,Store.get(entry.id),b))
        local intent,state
        for i=1,1000 do intent,state=planner:step(64) if state~="WAIT" then break end end
        if intent then for _,id in ipairs(intent.items) do assert(not Claims.owner(id),"planner stole a claimed original") end end
        checkedClaims=true
    end
end
release()
print=originalPrint
assert(actualMiddle>0,"fixture must pass through partial delivery")
assert(eventMiddle>0,"automatic partial delivery must notify its subscribed view")
assert(collect and deliver,"collect and deliver phase changes must reach the view")
assert(seenCompleted,"new batch must retain last completed batch identity")
assert(checkedClaims,"live claims must exclude competing planning")
local last=assert(Work.lastCompleted(a.id)) local taskId=last.id last.delivered=-100
assert(Work.lastCompleted(a.id).id==taskId and Work.lastCompleted(a.id).delivered>=0,"completion DTO must be detached")
-- Repeated finish, pause/clear and world changes must not fabricate completions.
local current=Work.record(a.id)
assert(current.state=="DONE" and current.delivered==#current.items,"last task actually finished")
local before=Work.lastCompleted(a.id).id
Claims.finish(current)
assert(Work.lastCompleted(a.id).id==before,"finish is not a new completion identity")
local delivered=current.delivered current.state="PAUSED" current.delivered=0
Claims.finish(current)
assert(Work.lastCompleted(a.id).id==before,"pause or cancellation cannot replace a verified completion")
current.state="DONE" current.delivered=delivered
local registryData=Registry.data local savedRoot=registryData()
Registry.data=function() return {} end
assert(Claims.recent(a.id)==nil,"world switch drops prior completion metadata")
Registry.data=function() return savedRoot end
assert(Claims.recent(a.id)==nil,"returning to a world does not revive session-only metadata")
Claims.finish(current)
world.select(a.id) Work.execute(actor,"clear")
assert(Work.lastCompleted(a.id)==nil,"explicit task clear releases the bounded summary")
print("PASS automatic progress/phase/completion snapshot/claim exclusion; partial events="..eventMiddle.." actual partial ticks="..actualMiddle.."; native host mocked")
