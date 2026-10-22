package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Query=require "EmberRoutesProbe/WarehouseQuery"
local n=0 local function check(v,why) n=n+1 assert(v,why) end
local rows={
    {fullType="B",label="Same",searchKey="same b",node="tools",count=2},
    {fullType="A",label="Same",searchKey="same a",node="tools",count=2},
    {fullType="C",label="Alpha",searchKey="alpha c",node="other",count=0},
    {fullType="D",label="Zulu",searchKey="zulu d",node="other",count=false,pending=true}}
local q=Query.new()
local function ids(mode) local r=q:page(rows,"",false,1,mode) local s="" for _,v in ipairs(r) do s=s..v.fullType end return s end
check(ids("nameAsc")=="CABD" and ids("nameDesc")=="DABC","name sorting has deterministic type-ID ties")
check(ids("quantityAsc")=="CABD" and ids("quantityDesc")=="ABCD","zero is known and unknown sorts last in either quantity direction")
check(rows[1].fullType=="B" and rows[4].count==false,"sorting cannot mutate source snapshot or make unknown quantities usable")
q:page(rows,"same",false,1,"nameAsc") local matching=q.matching
q:page(rows,"SAME",false,2,"nameAsc") check(q.matching==matching,"case-equivalent search and page changes reuse cached filtered order")
local big={}
for i=1,2048 do local id=string.format("Mod.%04d",i) big[i]={fullType=id,label=id,searchKey=string.lower(id),node="tools",count=i} end
local page,p,pages,total=q:page(big,"",false,1,"quantityDesc",big[1].fullType)
check(p==35 and pages==35 and total==2048 and page[#page].fullType==big[1].fullType,"selected type anchors its page after a reorder")
local changed={} for i,v in ipairs(big) do changed[i]=v end
changed[1]={fullType=big[1].fullType,label=big[1].label,searchKey=big[1].searchKey,node="tools",count=9999}
page,p=q:page(changed,"",false,35,"quantityDesc",big[1].fullType)
check(p==1 and page[1].fullType==big[1].fullType,"stock change can follow selected identity across pages")
check(#q:page(big,"missing",false,1,"nameAsc")==0,"empty searches produce a stable empty result")
if ERTestNanoTime then
    for i=1,30 do Query.new():page(big,"",false,1,"quantityDesc") end
    local start=ERTestNanoTime()
    for i=1,30 do Query.new():page(big,"",false,1,"quantityDesc") end
    local build=(ERTestNanoTime()-start)/30000000
    q:page(big,"",false,1,"quantityDesc") start=ERTestNanoTime()
    for i=1,300 do q:page(big,"",false,i%35+1,"quantityDesc") end
    local cached=(ERTestNanoTime()-start)/300000000
    print(string.format("BASELINE Kahlua pure-query types=2048 coldAvgMs=%.4f cachedPageAvgMs=%.4f; fixture CPU only, not engine/GPU",build,cached))
end
print("PASS "..n.." warehouse query sorting/cache/anchor checks")
