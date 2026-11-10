-- Central constants and dimension table (P1 constants): one vocabulary,
-- one read path. Run: LUA_PATH set to the repo's shared+client lua dirs,
-- e.g. LUA_PATH="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;;" lua tests/lua/constants-test.lua
-- Game/save codec NOT RUN.
local C=require 'EmberRoutesProbe/Kernel/Constants'
local Tick=require 'EmberRoutesProbe/Kernel/TickConfig'
local n=0 local function check(ok,label) n=n+1 assert(ok,label) end

-- Dimension table: native ranges, 0-1 vs 0-100.
local Max=C.Stat.NATIVE_MAX
for _,stat in ipairs({'HUNGER','THIRST','FATIGUE','ENDURANCE','STRESS','MORALE'}) do
    check(Max[stat]==1,stat..' is native 0-1')
end
for _,stat in ipairs({'BOREDOM','UNHAPPINESS','PAIN','PANIC','HEALTH'}) do
    check(Max[stat]==100,stat..' is native 0-100')
end
check(C.Stat.isUnit(0) and C.Stat.isUnit(1) and not C.Stat.isUnit(1.0001)
    and not C.Stat.isUnit(-0.1) and not C.Stat.isUnit(0/0) and not C.Stat.isUnit(nil)
    and not C.Stat.isUnit('0.5'),'isUnit accepts exactly 0-1 numbers')
check(C.Stat.isNative('BOREDOM',100) and not C.Stat.isNative('BOREDOM',100.0001)
    and C.Stat.isNative('STRESS',1) and not C.Stat.isNative('STRESS',1.0001)
    and not C.Stat.isNative('HEALTH',-1) and not C.Stat.isNative('NOPE',0.5),
    'isNative enforces each stat range')
check(C.Stat.toUnit('BOREDOM',50)==0.5 and C.Stat.toUnit('PAIN',100)==1
    and C.Stat.toUnit('STRESS',0.25)==0.25 and C.Stat.toUnit('HUNGER',0.5)==0.5
    and C.Stat.toUnit('NOPE',7)==7,'toUnit normalizes 0-100 stats, passes 0-1 through')
check(C.Stat.normalizeHungerChange(0.5)==0.5 and C.Stat.normalizeHungerChange(1)==1
    and C.Stat.normalizeHungerChange(50)==0.5 and C.Stat.normalizeHungerChange(100)==1,
    'hunger-change heuristic: above 1 reads as percent')
check(C.Stat.TOLERANCE_CENT==0.0001 and C.Stat.TOLERANCE_UNIT==0.000001,
    'write-back tolerances split by scale')

-- Threat rule (Lua side mirrors ObserverReads.java by name).
check(C.Threat.SPOTTED_LIMIT==64 and C.Threat.RADIUS==10 and C.Threat.Z_MAX==1
    and C.Threat.RADIUS*C.Threat.RADIUS==100,'threat rule: 64 spotted, 10 tiles, 1 floor')

-- Health lines shared by haul, cleanup orders and leisure fitness/stroll.
check(C.Health.WORK_MIN==95 and C.Health.STROLL_MIN==85
    and C.Health.MENTAL_UNHAPPINESS_WARN==80 and C.Health.MENTAL_STRESS_WARN==0.8
    and C.Health.CACHE_MS==1000,'health gates')
check(C.Observer.DAMAGE_DROP==0.01 and C.Observer.DAMAGE_GRACE_MS==3000,
    'recent-damage grace')
check(C.Needs.SLEEP_MAX_HUNGER==0.5 and C.Needs.SLEEP_MAX_THIRST==0.5
    and C.Needs.FIELD_MIN_ENDURANCE==0.4,'needs gates')
check(C.Supply.STATUS_CRITICAL_DAYS==2.0 and C.Supply.STATUS_WARNING_DAYS==5.0
    and C.Supply.HUNGER_MEALS==0.35 and C.Supply.HUNGER_STABLE==0.25
    and C.Supply.HUNGER_DEFAULT==0.15,'supply status days and hunger fallbacks')
check(C.Priority.MIN==0 and C.Priority.MAX==4,'priority range 0-4')
check(C.Timeout.MOVE_MS==185000,'move-step watchdog is 185000ms')

-- Stash distances: 15 in the open, 9999 = unlimited inside a settlement.
-- The 9999 is a distance sentinel only, NOT the 9999 quantity cap used by
-- Production/DeliveryService/OrderStore/StockRule/CraftRecord.
local Stash=require 'EmberRoutesProbe/Warehouse/PlayerStashRoutine'
check(Stash.DEFAULT_MAX_DISTANCE==15 and Stash.UNLIMITED_DISTANCE==9999,
    'stash distances: 15 open, 9999 unlimited in-settlement')

-- Tick table: new cadences present with the pre-refactor values.
check(Tick.wakeMs==50 and Tick.discoveryWakeMs==100 and Tick.reconcileMs==1000
    and Tick.stockMs==1000 and Tick.reservationExpiryMs==15000
    and Tick.socialRoundMs==1500 and Tick.businessPaceMs==18
    and Tick.businessIdleMs==50,'tick cadences')
check(Tick.backoffMs[1]==2000 and Tick.backoffMs[2]==5000 and Tick.backoffMs[3]==15000,
    'backoff ladder values')
for _,case in ipairs({{1,2000},{2,5000},{3,15000},{7,15000}}) do
    check(Tick.backoffMs[math.min(case[1],3)]==case[2],
        'backoff '..case[1]..' reads '..case[2]..'ms')
end

-- Behaviour pins through the public APIs that read the tables.
local Policy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
local sample={thirst=0.3,hunger=0,fatigue=0,endurance=1}
check(Policy.choose(sample,nil,{safe=true,isWorking=false},{DRINK=true})=='DRINK',
    'idle thirst 0.3 enters DRINK at the 0.20 threshold')
check(Policy.choose(sample,nil,{safe=true,isWorking=true},{DRINK=true})==nil,
    'working thirst 0.3 stays below the 0.45 work threshold')
local Leisure=require 'EmberRoutesProbe/Leisure/LeisurePolicy'
local fit={safe=true,healthy=true,hunger=0,thirst=0,fatigue=0,endurance=1,
    health=95,handsFree=true,fitnessKnown=true,stiff=false,pain=0}
check(Leisure.allowed('FITNESS',fit,{hold=true}),'fitness allowed at health 95')
fit.health=94 check(not Leisure.allowed('FITNESS',fit,{hold=true}),
    'fitness refused at health 94')
local stroll={safe=true,healthy=true,hunger=0,thirst=0,fatigue=0,endurance=1,
    health=85,pain=0}
check(Leisure.allowed('STROLL',stroll,{hold=true}),'stroll allowed at health 85')
stroll.health=84 check(not Leisure.allowed('STROLL',stroll,{hold=true}),
    'stroll refused at health 84')
local Supply=require 'EmberRoutesProbe/Warehouse/SupplyEstimate'
local starving=Supply.calculate({},1)
check(starving.status=='CRITICAL' and starving.foodDailyDemand==0.6
    and starving.waterDailyDemand==2.0,'empty stockpile is CRITICAL; P0 demand constants untouched')

print('PASS '..n..' central constants checks; game/save codec NOT RUN')
