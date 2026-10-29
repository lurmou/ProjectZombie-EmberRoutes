local now=0
getTimestampMs=function() return now end
local object={} local result='MOVING' local goal=object
package.loaded['EmberRoutesProbe/ReposeSites']={resolve=function() return {object=object} end}
EmberRoutesProbeJava={motionResult=function() return result end,reachedSeat=function() return goal end}
local calls=0
local c={payload={kind='LEISURE',site={}},npc={},actor={},job={id='job',npcId='npc'},budget={paths=1},
    valid=function() return true end,body={stop=function() return true end,
        move=function(_,target) assert(target.furniture==object and target.x==nil)
            calls=calls+1 return true,'MOVE_REQUESTED_SEAT' end}}
local F=require 'EmberRoutesProbe/SelfCareFurniture'
local leaf=F.move(c,'REST')
assert(leaf.run()=='Running' and calls==1,'even adjacent NPC must request a native seating approach')
assert(leaf.run()=='Running','a pending approach is never adjacent success')
result='REACHED' goal={}
assert(leaf.run()=='Failure' and c.reason=='SITE_CHANGED','cannot occupy an unreserved sprite-grid part')
goal=object c.budget.paths=1
leaf=F.seat(c,{}) result='MOVING' assert(leaf.run()=='Running')
result='REACHED' assert(leaf.run()=='Success','only actual native completion and exact original prove arrival')
c.budget.paths=0 calls=0 leaf=F.seat(c,{}) assert(leaf.run()=='Running' and calls==0)
print('P3.5 seat path: original native goal, no adjacent shortcut, exact reserved part, shared path budget')
