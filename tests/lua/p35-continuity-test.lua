local P=require 'EmberRoutesProbe/LeisurePolicy'
local R=require 'EmberRoutesProbe/LeisureRecord'
local minimum=P.pause(nil,10,0) local maximum=P.pause(nil,10,1)
assert(minimum.decisionAfter==10+1/60 and maximum.decisionAfter==10+4/60)
assert(R.memory(maximum)) maximum.decisionAfter=0/0 assert(not R.memory(maximum))
local now=0 local valid=true local retained=true local calls,cleared=0,0
getTimestampMs=function() return now end
ZombRand=function() return 70 end
local c={sameAttempt=function() return retained end,valid=function() return valid end,
    body={retained=function() return retained end},npc={
        setHeadLookAround=function(_,on) if not on then cleared=cleared+1 end end,
        setHeadLookAroundDirection=function(_,x,y) assert(x>=-0.7 and x<=0.7 and y==0) calls=calls+1 end}}
local look=require('EmberRoutesProbe/LeisureLook').new(c)
look.update() assert(calls==1)
for i=1,100 do now=i look.update() end
assert(calls==1,'native look direction is not rewritten every frame')
now=3100 look.update() assert(calls==2)
look.clear() assert(cleared==1 and calls==3)
look.clear() assert(cleared==1,'normal completion and subsequent halt share idempotent cleanup')
look.update() retained=false look.clear()
assert(cleared==1,'late cleanup cannot change a new body owner')
print('P3.5 continuity: bounded game-time pause, loadable memory, throttled head look and fenced cleanup')
local reviews=0 local paused=false
isGamePaused=function() return paused end
package.loaded['EmberRoutesProbe/LeisureService']={review=function() reviews=reviews+1 return false end}
local Continuity=require 'EmberRoutesProbe/LeisureContinuity'
local continuous=Continuity.new({payload={leisure={activity='SIT'}}})
now=0 continuous.start()
for _=1,450 do now=now+100 continuous.tick() assert(not continuous.boundary()) end
assert(reviews==1,'minimum dwell delays challenger discovery and keeps the incumbent alive')
paused=true
for _=1,450 do now=now+100 continuous.tick() assert(not continuous.boundary()) end
assert(reviews==1,'paused real time cannot spend the dwell/review clock')
paused=false now=now+3600000 continuous.tick() assert(not continuous.boundary() and reviews==1,
    'a suspended simulation cannot create catch-up reviews')
for _=1,100 do now=now+100 continuous.tick() continuous.boundary() end
assert(reviews==2,'resume advances only the next bounded review')
for _,kind in ipairs({'OBSERVE','STROLL','SMOKE','SOCIAL','READING','FITNESS','NEW_ACTIVITY'}) do
    local finite=Continuity.new({payload={leisure={activity=kind}}})
    assert(finite.boundary(),'finite/bounded/unknown activities do not automatically replay effects')
end
print('PASS continuous dwell/pause/review cadence and safe finite defaults')
