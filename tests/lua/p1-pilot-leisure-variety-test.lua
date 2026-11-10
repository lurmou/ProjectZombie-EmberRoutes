-- P0 pilot 2/15: leisure variety (RimWorld): the repeat discount in
-- LeisurePolicy.choose grows with the consecutive run of the same activity
-- in the recent history (N=3) instead of only looking at the last activity.
-- Two equal-weight candidates {SIT, OBSERVE} expose the weight through the
-- roll threshold: SIT wins iff roll < f/(f+1) with f = 0.15^streak.
-- Candidate set, cooldown semantics and thresholds are pinned unchanged.
-- Run from the repo root: lua tests/lua/p1-pilot-leisure-variety-test.lua
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(v,s) checks=checks+1 assert(v,s) end
local P=require 'EmberRoutesProbe/Leisure/LeisurePolicy'
local Config=require 'EmberRoutesProbe/Leisure/LeisureConfig'
local R=require 'EmberRoutesProbe/Leisure/LeisureRecord'

check(Config.repeatWeightFactor==0.15,'repeat factor stays 0.15')
check(Config.repeatHistory==3,'recent history window stays 3')

local pair={{activity='SIT',weight=1},{activity='OBSERVE',weight=1}}
local function picked(memory,roll) local c=P.choose(pair,memory,10.1,roll) return c and c.activity or nil end

-- ---- remember() builds a most-recent-first history capped at 3 ----
local m=P.remember(nil,'SIT',10,true)
check(m.last=='SIT' and #m.recent==1 and m.recent[1]=='SIT','first remember seeds last and recent')
m=P.remember(m,'OBSERVE',10,true)
check(m.last=='OBSERVE' and #m.recent==2 and m.recent[1]=='OBSERVE' and m.recent[2]=='SIT','second remember prepends')
m=P.remember(m,'SIT',10,true) m=P.remember(m,'SIT',10,true)
check(#m.recent==3 and m.recent[1]=='SIT' and m.recent[2]=='SIT' and m.recent[3]=='OBSERVE','history keeps the newest three')
m=P.remember(m,'SIT',10,true)
check(#m.recent==3 and m.recent[1]=='SIT' and m.recent[2]=='SIT' and m.recent[3]=='SIT','fourth repeat still caps at three')

-- ---- discount grows with the consecutive run: 0.15, 0.15^2, 0.15^3 ----
local once=P.remember(nil,'SIT',10,true)
check(picked(once,0.13)=='SIT' and picked(once,0.14)=='OBSERVE','streak 1: threshold 0.15/1.15')
local twice=P.remember(once,'SIT',10,true)
check(picked(twice,0.02)=='SIT' and picked(twice,0.03)=='OBSERVE','streak 2: threshold 0.0225/1.0225')
local thrice=P.remember(twice,'SIT',10,true)
check(picked(thrice,0.003)=='SIT' and picked(thrice,0.004)=='OBSERVE','streak 3: threshold 0.003375/1.003375')
check(picked(thrice,0.02)=='OBSERVE','after 3 repeats the switch wins a roll the repeat won at streak 1 and 2')
check(picked(thrice,0.13)=='OBSERVE','after 3 repeats the switch wins a roll the repeat won at streak 1')

-- ---- switching once restores the full weight ----
local switched=P.remember(thrice,'OBSERVE',10,true)
check(switched.recent[1]=='OBSERVE' and switched.recent[2]=='SIT' and switched.recent[3]=='SIT','switch prepends and keeps the old run behind it')
check(picked(switched,0.4)=='SIT' and picked(switched,0.9)=='OBSERVE','the switch target keeps its single last-only discount')
local fresh={{activity='SIT',weight=1},{activity='READING',weight=1}}
local function pickedFresh(memory,roll) local c=P.choose(fresh,memory,10.1,roll) return c and c.activity or nil end
check(pickedFresh(switched,0.4)=='SIT' and pickedFresh(switched,0.6)=='READING','one switch restores the repeated activity to full weight against a fresh activity')

-- ---- a non-consecutive repeat does not stack ----
local broken=P.remember(nil,'SIT',10,true)
broken=P.remember(broken,'OBSERVE',10,true) broken=P.remember(broken,'SIT',10,true)
check(broken.recent[1]=='SIT' and broken.recent[2]=='OBSERVE' and broken.recent[3]=='SIT','SIT-OBSERVE-SIT history recorded in order')
check(picked(broken,0.13)=='SIT' and picked(broken,0.14)=='OBSERVE','interrupted run discounts exactly once, like the old last-only rule')

-- ---- memory without `recent` still discounts once ----
check(picked({cooldowns={},last='SIT'},0.13)=='SIT' and picked({cooldowns={},last='SIT'},0.14)=='OBSERVE','last-only memory keeps the old single discount')
check(picked({cooldowns={},last='SIT',recent={}},0.13)=='SIT','empty recent falls back to last')
check(picked({cooldowns={},last='SIT',recent={'OBSERVE'}},0.4)=='SIT','a present recent history is authoritative over last')

-- ---- candidate set, cooldowns and thresholds unchanged ----
check(picked(nil,0.4)=='SIT' and picked(nil,0.6)=='OBSERVE','no memory means equal weights')
check(P.choose({},nil,10.1,0.5)==nil,'no candidates means no choice')
local fit=P.remember(nil,'FITNESS',10,true)
check(P.choose({{activity='FITNESS',weight=10}},fit,11,0)==nil,'FITNESS 12h cooldown still blocks at +1h')
check(P.choose({{activity='FITNESS',weight=10}},fit,23,0).activity=='FITNESS','FITNESS cooldown still expires at +13h')
local failed=P.remember(nil,'SIT',10,false)
check(failed.last=='SIT' and failed.recent[1]=='SIT','a failed attempt still records the activity')
check(P.choose({{activity='SIT',weight=10}},failed,10.01,0)==nil,'failed cooldown (0.03h) still blocks at +0.01h')
check(P.choose({{activity='SIT',weight=10}},failed,10.1,0).activity=='SIT','failed cooldown still expires at +0.1h')

-- ---- the new history field is loadable and validated like `last` ----
check(R.memory(thrice),'memory with a 3-long recent history loads')
check(R.memory({cooldowns={},last='SIT'}),'memory without recent still loads')
check(not R.memory({cooldowns={},recent={'SIT','SIT','SIT','SIT'}}),'recent history longer than 3 does not load')
check(not R.memory({cooldowns={},recent={'DANCE'}}),'unknown activity in recent history does not load')
check(R.memory({cooldowns={},recent={'READING'}}),'READING stays a valid history entry')

print('P1 pilot leisure variety: '..checks..' recent-history discount checks')
