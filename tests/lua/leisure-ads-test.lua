-- LeisureAds: the single advertisement table for the SOCIAL / READING /
-- SMOKE / SIT / PUBLIC_LIFE pilot. Each activity must hit through the
-- table (ad carries activity, point, benefit, condition) and must miss
-- when its condition fails. Sources are stubs: no world scan runs here,
-- and the table only ever holds what a lookup just published.
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end

local zoneRuleValue=1
local socialKey=nil
local bookValid=true
package.loaded['EmberRoutesProbe/Activity/SocialCoordinator']={
    advertise=function() end,
    withdraw=function() end,
    pending=function(id) return socialKey end,
    invite=function(id,entry,now,choose,roll) socialKey='pair-1' return 'pair-1' end,
    view=function(key,id,attempt,now)
        if id=='npc-1' then return {other='npc-2',point={x=11,y=10,z=0}} end
        return {other='npc-1',point={x=12,y=10,z=0}}
    end,
}
package.loaded['EmberRoutesProbe/Leisure/LibraryIndex']={
    choose=function(actor,npc,entry,target,budget,offset,leisure,itemId)
        return {item={getID=function() return 7 end},id='book-1',container={},endpoint={},entry=entry},true
    end,
    revalidate=function(candidate) return bookValid end,
}
package.loaded['EmberRoutesProbe/Leisure/LeisureSmoke']={
    find=function(npc,budget,cache)
        return {item={getID=function() return 11 end},fire={getID=function() return 12 end}},true
    end,
}
package.loaded['EmberRoutesProbe/SelfCare/ReposeSites']={
    new=function(actor,npc,npcId,kind,blocked,options)
        return {step=function(self,slice)
            return {key='seat:1',object={getSquare=function()
                return {getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end}
            end}},true,nil,1
        end}
    end,
    prepare=function(found,actor,npc,npcId,kind) return {key=found.key} end,
    keys=function(proof,kind) return {'seat:1'} end,
}
package.loaded['EmberRoutesProbe/Settlement/SettlementFacilities']={
    watch=function(entry,classify) return {version=1} end,
    describe=function(object) return 'good',2 end,
}
package.loaded['EmberRoutesProbe/Settlement/LifeZoneVisits']={
    seek=function(env,standable)
        return {activity='OBSERVE',point={x=12,y=10,z=0},entry=env.entry,pure=true,publicVisit=true,
            targetKey='life-zone:z1:1',weight=0.9,
            leisure={format=1,activity='OBSERVE',point={x=12,y=10,z=0},hours=env.hours,moving=true,zoneVisit={id='z1'}}},true
    end,
}
function getGameTime() return {getTimeOfDay=function() return 19 end,getWorldAgeHours=function() return 10 end} end
function getTimestampMs() return 1000 end
function ZombRand(n) return 0 end
function getCell() return {getGridSquare=function() return nil end} end

local Ads=require 'EmberRoutesProbe/Leisure/LeisureAds'
local Policy=require 'EmberRoutesProbe/Leisure/LeisurePolicy'
Ads.install({zoneRule=function() return zoneRuleValue end,
    standable=function() return {canReachTo=function() return true end} end})

local function sampleWith(o)
    local s={safe=true,healthy=true,health=100,hunger=0,thirst=0,fatigue=0,endurance=1,
        handsFree=true,smoker=true,boredom=0.5,stress=0.5,pain=0}
    if o then for k,v in pairs(o) do s[k]=v end end
    return s
end
local function makeEnv(s)
    return {actor={},npc={getX=function() return 10 end,getY=function() return 10 end,getZ=function() return 0 end},
        id='npc-1',entry={id='s1',revision=1},offer={entryRevision=1,membershipRevision=1},
        s=s or sampleWith(),hours=10,now=1000,point={x=10,y=10,z=0},
        budget={scan=10,paths=2,containers=2},cooling={},state={},memory={}}
end
local function adShape(ad,activity)
    check(ad~=nil,activity..': lookup hits through the table')
    check(ad.activity==activity,activity..': ad carries its activity')
    check(type(ad.point)=='table' and ad.point.x~=nil,activity..': ad carries a point')
    check(type(ad.benefit)=='number',activity..': ad carries a benefit')
    check(type(ad.condition)=='function',activity..': ad carries a condition')
    check(type(ad.key)=='string' and #ad.key>0,activity..': ad carries a key')
end

-- SOCIAL: hit through the table, then miss when the zone rule fails.
socialKey=nil
local env=makeEnv()
local ad,done=Ads.lookup('SOCIAL',env)
adShape(ad,'SOCIAL')
check(ad.key=='pair-1','SOCIAL: ad key is the pair id')
check(ad.point.x==11,'SOCIAL: ad point is the partner meeting point')
check(ad.benefit==1,'SOCIAL: benefit is the unchanged Policy weight')
check(ad.payload.other=='npc-2','SOCIAL: payload names the partner')
check(#Ads.list('SOCIAL')==1,'SOCIAL: exactly one ad is registered')
check(done==true,'SOCIAL: lookup reports done')
zoneRuleValue=0
local miss,missDone=Ads.lookup('SOCIAL',makeEnv())
check(miss==nil and missDone==true,'SOCIAL: origin zone rule 0 publishes no ad')
check(#Ads.list('SOCIAL')==0,'SOCIAL: no stale ad survives a miss')
zoneRuleValue=1
socialKey=nil
local ad2=Ads.lookup('SOCIAL',makeEnv())
check(ad2~=nil,'SOCIAL: re-hit after the rule recovers')
zoneRuleValue=0
check(Ads.query('SOCIAL',makeEnv())==nil,'SOCIAL: query re-checks the condition on a registered ad')
zoneRuleValue=1
check(Ads.query('SOCIAL',makeEnv())~=nil,'SOCIAL: query passes the ad again once the condition holds')

-- READING: hit, then miss when revalidation (the ad condition) fails.
bookValid=true
local readAd,readDone=Ads.lookup('READING',makeEnv())
adShape(readAd,'READING')
check(readAd.key=='item:book-1','READING: ad key is the book id')
check(readAd.benefit==Policy.weight('READING',sampleWith(),1.3),'READING: benefit is the unchanged Policy weight')
bookValid=false
local readMiss,readMissDone=Ads.lookup('READING',makeEnv())
check(readMiss==nil and readMissDone==true,'READING: failed revalidation does not hit')
check(#Ads.list('READING')==1,'READING: the ad is published but filtered by its condition')
bookValid=true

-- SMOKE: hit, then miss for a non-smoker (the ad condition).
local smokeAd=Ads.lookup('SMOKE',makeEnv())
adShape(smokeAd,'SMOKE')
check(smokeAd.key=='item:11','SMOKE: ad key is the cigarette id')
check(smokeAd.payload.fire:getID()==12,'SMOKE: payload carries the fire item')
check(smokeAd.benefit==Policy.weight('SMOKE',sampleWith(),1),'SMOKE: benefit is the unchanged Policy weight')
local smokeMiss=Ads.lookup('SMOKE',makeEnv(sampleWith({smoker=false})))
check(smokeMiss==nil,'SMOKE: non-smoker publishes no ad')

-- SIT: hit (preview keeps its flag), then miss without the Java repose entry.
EmberRoutesProbeJava={reposeAtWithControl=function() end}
local sitAd=Ads.lookup('SIT',makeEnv())
adShape(sitAd,'SIT')
check(sitAd.key=='seat:1','SIT: ad key is the seat key')
check(sitAd.point.x==10.5,'SIT: ad point is the seat tile')
check(sitAd.benefit==Policy.weight('SIT',sampleWith(),1.2),'SIT: benefit is the unchanged Policy weight')
local previewAd=Ads.lookup('SIT',makeEnv(),{preview=true})
check(previewAd~=nil and previewAd.payload.preview==true,'SIT: preview lookup advertises the same seat as a preview')
EmberRoutesProbeJava=nil
local sitMiss,sitDone=Ads.lookup('SIT',makeEnv())
check(sitMiss==nil and sitDone==true,'SIT: no Java repose entry publishes no ad')
EmberRoutesProbeJava={reposeAtWithControl=function() end}

-- PUBLIC_LIFE: hit, then miss when the STROLL gate (the ad condition) fails.
local lifeAd=Ads.lookup('PUBLIC_LIFE',makeEnv())
adShape(lifeAd,'PUBLIC_LIFE')
check(lifeAd.key=='life-zone:z1:1','PUBLIC_LIFE: ad key is the zone target key')
check(lifeAd.benefit==0.9,'PUBLIC_LIFE: benefit is the unchanged zone weight')
check(lifeAd.payload.candidate.activity=='OBSERVE','PUBLIC_LIFE: payload carries the zone-visit candidate')
local lifeMiss=Ads.lookup('PUBLIC_LIFE',makeEnv(sampleWith({fatigue=0.9})))
check(lifeMiss==nil,'PUBLIC_LIFE: failed STROLL gate does not hit')
check(#Ads.list('PUBLIC_LIFE')==1,'PUBLIC_LIFE: the ad is published but filtered by its condition')

-- Table discipline: unknown activity, scope change, reset, bounded size.
local unknown,unknownDone,unknownWhy=Ads.lookup('NOPE',makeEnv())
check(unknown==nil and unknownDone==true and unknownWhy=='AD_UNKNOWN_ACTIVITY','unknown activity is rejected, not scanned')
socialKey=nil
Ads.lookup('SOCIAL',makeEnv())
check(#Ads.list('SOCIAL')==1,'scope: SOCIAL ad registered before the scope change')
local movedEnv=makeEnv()
movedEnv.offer={entryRevision=2,membershipRevision=1}
Ads.lookup('READING',movedEnv)
check(#Ads.list('SOCIAL')==0,'scope: entry revision change clears the table')
local total=0
for _,activity in ipairs({'SOCIAL','READING','SMOKE','SIT','PUBLIC_LIFE'}) do total=total+#Ads.list(activity) end
check(total<=5,'table holds at most one ad per pilot activity, never a map sweep')
Ads.reset()
check(#Ads.list('READING')==0,'reset clears the table')

print('PASS '..checks..' leisure advertisement-table checks')
