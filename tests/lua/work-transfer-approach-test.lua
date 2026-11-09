-- Installed adjacent-tile selection + real transfer movement adapter; native paths mocked.
local checks,now=0,100
local function check(v,m) checks=checks+1 assert(v,m) end
getTimestampMs=function() return now end
package.loaded['TimedActions/ISInventoryTransferAction']=true
package.loaded['EmberRoutesProbe/Work/LaborProducers']={}
local moves,motion,arrived={},'MOVING',false
package.loaded['EmberRoutesProbe/Runtime/Driver']={
    suspended=function() return false end,
    move=function(binding,actor,p,body)
    check(binding.id=='npc' and body=='owned-session','retry retains the same body authority')
    moves[#moves+1]=p motion='MOVING' return 'MOVE_REQUESTED'
end}
EmberRoutesProbeJava={motionResult=function() return motion end}
IsoDirections={W='W',E='E',N='N',S='S',NW='NW',NE='NE',SW='SW',SE='SE'}
IsoFlagType={cutW='cutW',cutN='cutN',collideW='collideW',collideN='collideN'}
local tiles={}
local function tile(x,y)
    local s={x=x,y=y}
    function s:getX() return self.x end function s:getY() return self.y end function s:getZ() return 0 end
    function s:has() return false end function s:canStand() return true end
    function s:TreatAsSolidFloor() return true end function s:isSolid() return false end
    function s:isSolidTrans() return false end function s:canReachTo() return true end
    function s:DistToProper() return (self.x+5)^2+self.y*self.y end
    tiles[x..':'..y]=s return s
end
local target=tile(10,0) local west,east=tile(9,0),tile(11,0)
function target:getAdjacentSquare(dir) return dir=='W' and west or dir=='E' and east or nil end
getCell=function() return {getGridSquare=function(_,x,y) return tiles[x..':'..y] end} end
luautils={getCorrectSquareForWall=function(_,s) return s end}
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/Util/AdjacentFreeTileFinder.lua')
local Transfer=require 'EmberRoutesProbe/Work/WorkTransfer'
Transfer.reachable=function() return arrived end
local c={npc={},actor={},job={npcId='npc'},body='owned-session'}
local endpoint={object={getSquare=function() return target end}}
local step=Transfer.move(c,endpoint)
check(step.start()==nil and #moves==1 and moves[1].x==9.5,'first attempt uses installed nearest-neighbour selection')
check(step.poll()=='WAIT' and #moves==1,'pending native path is not restarted')
motion='FAILED'
check(step.poll()=='WAIT' and #moves==2 and moves[2].x==11.5,'unreachable nearest tile is excluded; other side is tried')
motion='REACHED' arrived=true
check(step.poll()=='PASSED' and #moves==2,'verified arrival completes the original step')
arrived=false moves={} step=Transfer.move(c,endpoint) step.start()
motion='FAILED' step.poll() motion='FAILED'
check(step.poll()=='FAILED' and #moves==2,'exhausted neighbours fail finitely without repeating a failed tile')
moves={} step=Transfer.move(c,endpoint) step.start() motion='STOPPED'
check(step.poll()=='FAILED' and #moves==1,'external stop does not launch an automatic replacement')
local driver=package.loaded['EmberRoutesProbe/Runtime/Driver'] local move=driver.move
driver.move=function() return 'NOT_AUTHORIZED' end
step=Transfer.move(c,endpoint)
check(step.start()=='FAILED','denied body authority fails without alternate retries')
driver.move=move
print('PASS '..checks..' approach checks; installed neighbour finder, native paths mocked')
