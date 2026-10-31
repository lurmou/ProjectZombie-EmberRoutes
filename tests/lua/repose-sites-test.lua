local checks=0 local function check(v,s) checks=checks+1 assert(v,s) end
local function list(rows) rows=rows or {} return {size=function() return #rows end,get=function(_,i) return rows[i+1] end,
 contains=function(_,o) for _,v in ipairs(rows) do if v==o then return true end end return false end,
 add=function(_,o) rows[#rows+1]=o end} end
local root={} local serial=0 local now=0 local allowed=true local known={a=true,b=true}
local claims={} local squares={} local playerBed,playerAsleep
local entry={id='s',areas={{x=-3,y=-3,w=8,h=8}}}
dofile('tests/lua/membership-fixture.lua')(function() if allowed then return entry end end,{'a','b'})
local actor={getX=function() return 0.5 end,getY=function() return 1.5 end,getZ=function() return 0 end,
 getBed=function() return playerBed end,isAsleep=function() return playerAsleep end,Say=function() end}
local npc={getX=function() return 0.5 end,getY=function() return 1.5 end,getZ=function() return 0 end}
local function square(x,y,z)
 local s={x=x,y=y,z=z or 0,rows={}}
 function s:getX() return self.x end function s:getY() return self.y end function s:getZ() return self.z end
 function s:getObjects() return list(self.rows) end
 squares[x..':'..y..':'..s.z]=s return s
end
local left,right=square(0,0),square(1,0)
local parts={}
local function furniture(s)
 local o={mod={},square=s}
 function o:getSquare() return self.square end function o:getModData() return self.mod end
 function o:getProperties() return {get=function(_,key) if key=='BedType' then return 'goodBed' end end,
  has=function() return self.bed==true end} end
 function o:hasSpriteGrid() return true end
 function o:getSprite() return {getName=function() return self.bed and 'furniture_bedding_01_0' or 'furniture_seating_indoor_01_0' end,getSpriteGrid=function() return {getSpriteCount=function() return 2 end} end} end
 function o:getSpriteGridObjectsIncludingSelf(out) for _,v in ipairs(parts) do out:add(v) end end
 function o:isFurnitureOccupied() return self.occupied==true end
 s.rows[#s.rows+1]=o return o
end
local a,b=furniture(left),furniture(right) parts={a,b}
local chunk={low=0,high=0}
function chunk:getMinLevel() return self.low end function chunk:getMaxLevel() return self.high end
local cell={getGridSquare=function(_,x,y,z) return squares[x..':'..y..':'..z] end,
 getChunkForGridSquare=function() return chunk end}
getCell=function() return cell end
getTimestampMs=function() return now end getSpecificPlayer=function() return actor end
ArrayList={new=function() return list() end}
SeatingManager={getInstance=function() return {getTilePositionCount=function() return 1 end} end}
IsoFlagType={bed='bed'}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() serial=serial+1 return 'stable-'..serial end}
package.loaded['EmberRoutesProbe/SettlementLedger']={authorized=function() return allowed end,at=function() return {entry} end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) if known[id] then return {id=id,handle=npc} end end}
package.loaded['EmberRoutesProbe/LaborStore']={resourceOwner=function(key) return claims[key] end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
local Sites=require 'EmberRoutesProbe/ReposeSites' Sites.RADIUS=1
local function discover(id,kind,options)
 local request=Sites.new(actor,npc,id,kind or 'SLEEP',nil,options)
 for _=1,1000 do local c,done=request:step(4) if done then return c end end error('unbounded furniture search')
end
local view=Sites.view(actor,b)
check(view.mode=='PUBLIC' and view.revision==0,'unconfigured whole furniture defaults to shared use')
local candidate=assert(discover('a'))
check(serial==0 and not a.mod.EmberRoutesRepose and not b.mod.EmberRoutesRepose,'discovery allocates no persistent identity or claims')
local proof=assert(Sites.prepare(candidate,actor,npc,'a','SLEEP'))
check(proof.id==a.mod.EmberRoutesRepose.id and proof.id==b.mod.EmberRoutesRepose.id,'multi-tile furniture shares one stable identity')
check(#Sites.keys(proof,'SLEEP')==2 and #Sites.keys(proof,'REST')==1,'sleep reserves whole furniture; rest reserves one part')
for _,key in ipairs(Sites.keys(proof,'SLEEP')) do claims[key]={taskId='care-a'} end
check(not discover('b'),'second NPC cannot select a reserved bed')
check(Sites.resolve(proof,actor,npc,'a','SLEEP','care-a')~=nil,'owner may revalidate its own exact reservation')
check(not Sites.resolve(proof,actor,npc,'a','SLEEP','care-b'),'foreign reservation is rejected') claims={}
check(not Sites.resolve(proof,actor,npc,'a','SLEEP','care-a'),'lost reservation cannot authorize use')
check(Sites.configure(actor,b,1,'DISABLED')=='SITE_POLICY_SAVED' and Sites.view(actor,a).mode=='DISABLED',
 'policy set on one part applies to entire furniture')
check(not discover('a') and not Sites.resolve(proof,actor,npc,'a','SLEEP'),'disabled furniture and stale policy cannot be used')
check(Sites.configure(actor,a,1,'PUBLIC')=='SITE_CHANGED','stale menu cannot overwrite newer policy')
check(Sites.configure(actor,a,2,'ASSIGNED','a')=='SITE_POLICY_SAVED','assign by stable NPC identity')
check(discover('a') and not discover('b'),'assignment is a hard permission, not a preference')
known.a=nil
check(Sites.view(actor,b).mode=='ASSIGNED' and Sites.view(actor,b).npcId=='a' and not discover('b'),
 'absent owner does not turn assigned furniture public') known.a=true
check(Sites.configure(actor,a,3,'ASSIGNED','missing')=='SITE_NPC_UNAVAILABLE','cannot assign missing NPC from stale menu')
check(Sites.configure(actor,a,3,'PUBLIC')=='SITE_POLICY_SAVED','explicitly restore public access')
playerBed=b playerAsleep=true
check(not discover('a','REST') and not discover('a','SLEEP'),'sleeping player occupies entire bed independently of NPC policy')
playerBed=nil playerAsleep=false a.occupied=true b.occupied=true
check(not discover('a'),'native sitting occupancy is respected') a.occupied=false b.occupied=false
local restProof=assert(Sites.prepare(assert(discover('a','REST')),actor,npc,'a','REST'))
playerBed=restProof.partId==a.mod.EmberRoutesRepose.partId and b or a
check(Sites.resolve(restProof,actor,npc,'a','REST')~=nil,'another seated/resting part does not block an independent rest slot')
playerBed=nil
allowed=false check(Sites.configure(actor,a,4,'DISABLED')=='ACCESS_DENIED','configuration rechecks settlement authority') allowed=true
local retained=assert(Sites.prepare(assert(discover('a')),actor,npc,'a','SLEEP'))
local failed=assert(discover('a'))
local slow=Sites.new(actor,npc,'a','SLEEP',{[failed.key]=now+10000})
now=now+20000
local alternative,done
repeat alternative,done=slow:step(8) until done
check(alternative and alternative.key~=failed.key,'scan retains failed approach exclusion even after cooldown expires mid-scan')
a.bed=true b.bed=true
check(not discover('a','REST',{seatingOnly=true,excludeBeds=true}),'ordinary idle excludes actual beds')
a.bed=false b.bed=false
local preferred=assert(discover('a','REST',{seatingOnly=true,excludeBeds=true,preferredPoint={x=1,y=0,z=0}}))
check(preferred.object==b,'sleepable sofa is allowed and previous seat outranks a closer peer')
left.rows={} right.rows={} parts={}
local replacement=furniture(left) local replacementOther=furniture(right) parts={replacement,replacementOther}
check(not Sites.resolve(retained,actor,npc,'a','SLEEP') and not replacement.mod.EmberRoutesRepose,
 'replacement at same coordinates cannot inherit identity or reservation')
check(require('EmberRoutesProbe/ReposeRecord').valid(retained),'proof is serializable without native handles')
getText=function(key,arg) return key..(arg and ':'..arg or '') end getTextOrNull=getText
EmberRoutesProbeJava={workerCount=function() return 2 end,workerIdAt=function(i) return i==0 and 'a' or 'b' end}
package.loaded['EmberRoutesProbe/DisplayNames']={name=function(id) return 'Member '..id end}
local options={}
local function menu() return {addOption=function(_,name,target,callback,...) local o={name=name,target=target,callback=callback,args={...}}
 options[#options+1]=o return o end,addSubMenu=function() end} end
ISContextMenu={getNew=function() return menu() end}
require('EmberRoutesProbe/ReposeMenu').fill(actor,menu(),{replacement,replacementOther})
local assign
for _,option in ipairs(options) do if option.args[3]=='ASSIGNED' and option.args[4]=='b' then assign=option break end end
check(assign and assign.target==actor and assign.args[1]==replacement,'real context menu offers stable NPC selection for one grouped furniture')
print('PASS '..checks..' furniture identity/policy/occupancy/menu checks; engine furniture and paths mocked')
return {root=root,actor=actor,npc=npc,sites=Sites,furniture=replacement,other=replacementOther,
 square=square,entry=entry,cell=cell,chunk=chunk,squares=squares,
 resourceProxy=package.loaded['EmberRoutesProbe/LaborStore'],list=list,advance=function(ms) now=now+(ms or 6000) end}
