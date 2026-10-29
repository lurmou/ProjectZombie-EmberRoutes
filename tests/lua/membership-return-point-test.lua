local data={format=1,entries={},revision=1,factionId='f'}
local root={} local loaded,free=true,true
local actor={getIndex=function() return 0 end,isDead=function() return false end,
    getX=function() return 2 end,getY=function() return 2 end}
isClient=function() return false end isServer=function() return false end getSpecificPlayer=function() return actor end
ModData={getOrCreate=function() return data end}
getCell=function() return {getGridSquare=function() return loaded and {isFree=function() return free end} or nil end} end
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() return 'id' end}
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
data.entries.home={id='home',name='Home',format=1,factionId='f',revision=1,areas={{x=0,y=0,w=10,h=10}}}
local point={x=3.5,y=4.5,z=0}
assert(Ledger.setReturnPoint(actor,'home',point,1))
local copy=Ledger.get('home') assert(copy.revision==2 and copy.returnPoint.x==3.5)
copy.returnPoint.x=99 assert(Ledger.get('home').returnPoint.x==3.5,'UI snapshots do not write return targets')
local ok,why=Ledger.setReturnPoint(actor,'home',point,1) assert(not ok and why=='SETTLEMENT_CHANGED')
free=false ok,why=Ledger.setReturnPoint(actor,'home',point,2) assert(not ok and why=='RETURN_POINT_BLOCKED')
free=true loaded=false ok,why=Ledger.setReturnPoint(actor,'home',point,2) assert(not ok and why=='TARGET_UNLOADED')
loaded=true ok,why=Ledger.setReturnPoint(actor,'home',{x=30,y=30,z=0},2) assert(not ok and why=='RETURN_POINT_INVALID')
assert(Ledger.get('home').revision==2,'failed target changes leave the previous target and revision intact')
print('Membership return point: authority, live target validation, detached snapshots and revision fences')
