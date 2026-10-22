package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Sort=require "EmberRoutesProbe/SortPolicy"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Claims=require "EmberRoutesProbe/LaborClaims"
local count=0 local function check(value,message) count=count+1 assert(value,message) end
local item={}
function item:getFullType() return "Base.Food" end
function item:isFood() return true end
function item:getOffAgeMax() return 10 end
function item:getCategory() return "Food" end
function item:getDisplayCategory() return "Food" end
local broad=Filter.new() broad.groups.food=true
local precise=Filter.new() precise.groups["food.perishable"]=true
local exact=Filter.new() exact.types["Base.Food"]=true
local denied=Filter.new() denied.groups.food=true denied.types["Base.Food"]=false
check(Sort.source("INPUT",{intake=true},broad,item)=="INTAKE","input exports even when broad filter accepts")
check(not Sort.source("STORAGE",{tidy=true},broad,item),"correct warehouse contents stay put")
check(Sort.source("STORAGE",{tidy=true},Filter.new(),item)=="TIDY","misplaced contents eligible")
check(not Sort.source("EXCLUDED",{intake=true,tidy=true},Filter.new(),item),"excluded role cannot export")
local description=Filter.describe(item)
check(Sort.specificity(exact,description,item)>Sort.specificity(precise,description,item),"exact type outranks category")
check(Sort.specificity(precise,description,item)>Sort.specificity(broad,description,item),"deeper category outranks parent")
check(not Sort.specificity(denied,description,item),"explicit exclusion wins over category")
check(Sort.better({id="a",specificity=1,distance=1},{id="b",specificity=1,distance=1}),"stable identity breaks equal-distance ties")
local index=Sort.index()
for i,filter in ipairs({broad,precise,exact,denied}) do index:add({id=tostring(i),filter=filter}) end
local cursor=index:cursor(item) local seen={} local steps=0
while true do local target,done=cursor:step() steps=steps+1 if target then check(not seen[target.id],"deduplicated candidate") seen[target.id]=true end if done then break end end
check(seen['1'] and seen['2'] and seen['3'] and steps<20,"inverted route index yields matching type/category buckets")
local claims=Claims.new()
local a=claims:acquire("a",1,{"item:1","item:2","item:3"})
local b=claims:acquire("b",1,{"item:4"})
check(claims:reserveMany(a,"box",{[1]=2,[2]=3,[3]=1},6),"whole route reserves batch capacity")
check(not claims:reserve(b,"box",4,1,6),"another worker cannot overbook planned batch")
claims:releaseCapacity(a,99)
check(claims:available("box",6)==0,"unknown delivery cannot release other cargo capacity")
claims:releaseCapacity(a,1)
check(claims:available("box",4)==0,"physical delivery and single reservation release keep remaining batch accounted")
local renewed=claims:acquire("a",2,{"item:1","item:2","item:3"}) claims:release(a)
check(claims:availableFor(renewed,"box",2,4)==3,"renewed generation retains reservation for each held/planned original")
check(not claims:reserveMany(b,"box",{[4]=5},4) and claims:available("box",4)==0,"failed batch reservation is atomic")
claims:release(renewed)
check(claims:available("box",4)==4,"release removes full remaining batch")
print("PASS "..count.." sort policy/index/batch capacity assertions; no engine effects")
