local n=0 local function check(v,m) n=n+1 assert(v,m) end
local entry={id='s',revision=1,factionId='f',areas={{x=0,y=0,w=10,h=10},{x=20,y=0,w=10,h=10}}}
local root={entries={s=entry}}
local zones={z={id='z',settlementId='s',enabled=true,revision=1,areas={{x=100,y=100,z=2,w=5,h=5}}}}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return root end,get=function() return entry end}
local G=require 'EmberRoutesProbe/SettlementGeometry'
package.loaded['EmberRoutesProbe/SettlementZones']={get=function(id) return zones[id] end,
 contains=function(z,x,y,floor) for _,r in ipairs(z.areas) do if r.z==floor and G.contains(r,x,y) then return true end end return false end}
local seen={}
getCell=function() return {getChunk=function(_,x,y) seen[x..':'..y]=true return {x=x,y=y} end} end
local S=require 'EmberRoutesProbe/FieldSpatial'
check(S.inside(entry,nil,5,5,0),'first territory segment accepted')
check(S.inside(entry,nil,25,5,0),'second territory segment accepted')
check(not S.inside(entry,nil,15,5,0),'gap is not filled by a bounding box')
check(S.inside(entry,'z',101,101,2),'offsite explicit zone accepted')
check(not S.inside(entry,'z',101,101,0),'explicit zone retains floor')
check(not S.inside(entry,'missing',1,1,0),'missing explicit zone never falls back')
for i=0,8 do S.chunk(entry,nil,'cleaning',i*300) end
check(seen['0:0'] and seen['2:0'] and not seen['1:0'],'union traversal scans both components without a gap chunk')
local policy={spoilageStrategy='EXPIRE_SOON_FIRST',kitchenZoneId='z'}
package.loaded['EmberRoutesProbe/JobPolicyService']={get=function() return policy end}
instanceof=function(i,kind) return kind=='Food' and i.food end
local D=require 'EmberRoutesProbe/CookingDirectives'
local function food(id,remaining)
 return {food=true,getID=function() return id end,getAge=function() return 10-remaining end,getOffAgeMax=function() return 10 end}
end
local old,new={item=food(20,1)},{item=food(10,8)}
check(D.less('s')(old,new),'expire first uses actual remaining shelf life')
policy.spoilageStrategy='FRESH_FIRST'
check(D.less('s')(new,old),'fresh first reverses shelf life ordering')
policy.spoilageStrategy='ANY_SAFE'
check(D.less('s')(new,old),'any safe keeps deterministic identity ordering')
local square={getX=function() return 101 end,getY=function() return 101 end,getZ=function() return 2 end}
local object={getSquare=function() return square end}
check(D.kitchen('s',object),'kitchen consumes selected zone')
zones.z.enabled=false
check(not D.kitchen('s',object),'disabled kitchen fails closed')
local P=require 'EmberRoutesProbe/MembershipPolicy'
local row={npcId='npc',settlementId='s',factionId='f',context='SETTLEMENT',revision=1}
check(not P.evaluate(row,entry,'WORK',{x=101,y=101}).allowed,'ordinary work stays inside settlement')
check(P.evaluate(row,entry,'FIELD_WORK',{x=101,y=101,scopeId='s'}).allowed,'field macro eligibility allows approved offsite execution')
row.context='FOLLOW'
check(not P.evaluate(row,entry,'FIELD_WORK',{x=101,y=101,scopeId='s'}).allowed,'follow still revokes field work')
print('PASS '..n..' field spatial/directive checks; native world mocked')
