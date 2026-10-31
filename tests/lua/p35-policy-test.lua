local P=require 'EmberRoutesProbe/LeisurePolicy'
local s={safe=true,hunger=0.05,thirst=0.05,fatigue=0.1,endurance=0.9,pain=0,
    healthy=true,handsFree=true,fitnessKnown=true,stiff=false,smoker=true}
assert(P.allowed('FITNESS',s,{hold=true}))
s.fatigue=0.5 assert(not P.allowed('FITNESS',s,{hold=true})) s.fatigue=0.1
s.stiff=true assert(not P.allowed('FITNESS',s,{hold=true})) s.stiff=false
s.handsFree=false assert(not P.allowed('FITNESS',s,{hold=true})) s.handsFree=true
assert(not P.allowed('OBSERVE',s,{hold=false}))
local m={cooldowns={FITNESS=12},last='OBSERVE'}
assert(P.choose({{activity='FITNESS',weight=10}},m,11,0)==nil)
assert(P.choose({{activity='FITNESS',weight=10}},m,13,0).activity=='FITNESS')
assert(P.choose({},m,13,0.5)==nil)
print('P3.5 policy: body guards, retained cooldown, no eligible activity')

local Config=require 'EmberRoutesProbe/LeisureConfig'
assert(Config.weights.STROLL<Config.weights.OBSERVE and Config.strollMinutes>=2)
local settled=P.remember(nil,'STROLL',10,true) settled.moveAfter=10+Config.movementIntervalHours
local options={{activity='OBSERVE',moving=true,weight=10},{activity='OBSERVE',weight=1}}
assert(P.choose(options,settled,10.1,0)==options[2],'window trips share the movement interval; stationary observation stays available')
assert(P.choose(options,settled,10.3,0)==options[1],'movement interval expires in game time')
assert(not P.choose({{activity='STROLL',weight=1}},settled,10.3,0),'strolling also has its own longer cooldown')
print('P3.5 pacing: shared move interval, stationary fallback, lower movement weight and longer pauses')
