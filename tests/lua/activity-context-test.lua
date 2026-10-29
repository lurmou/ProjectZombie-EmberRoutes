-- Real context/store/zones; world identity, clock and membership are substitutes.
local checks=0
local function check(v,label) assert(v,label) checks=checks+1 end
local root,spatial={}, {entries={home={id='home',revision=1,areas={{x=0,y=0,w=20,h=20}}}}}
local actor,serial,hours,millis={},0,10,100
getGameTime=function() return {getWorldAgeHours=function() return hours end} end
getTimestampMs=function() return millis end
local members={a={context='SETTLEMENT',settlementId='home',revision=1},
    b={context='SETTLEMENT',settlementId='home',revision=1}}
local epochs={a=0,b=0}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    id=function() serial=serial+1 return 'id-'..serial end}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return spatial end,
    view=function(a,id) if a==actor and id=='home' then return spatial.entries.home end return nil,'ACCESS_DENIED' end}
package.loaded['EmberRoutesProbe/MembershipService']={view=function(id) return members[id] end,
    entry=function(id,scope) return members[id] and members[id].settlementId==scope and spatial.entries[scope] end,
    character=function(a) return a==actor and 'player-1' end}
package.loaded['EmberRoutesProbe/TaskResume']={epoch=function(id) return epochs[id] end}
local Zones=require 'EmberRoutesProbe/SettlementZones'
local Store=require 'EmberRoutesProbe/ActivityStore'
local Service=require 'EmberRoutesProbe/ActivityService'
local zone=assert(Zones.save(actor,'home',nil,nil,{name='Garden',enabled=true,
    area={x=2,y=2,w=5,h=5,z=0},rules={SOCIAL=0,READING=1,OBSERVE=1}}))
local function args()
    return {name='Friends',settlementId='home',zoneId=zone.id,zoneRevision=zone.revision,
        durationHours=1,roster={'a'},rules={SOCIAL=2,READING=0}}
end
local function policy(id,behavior,x,z)
    return Service.policyAt('home',id,x or 3,3,z or 0,behavior)
end
check(policy('a','SOCIAL')==0,'no event retains ordinary ban')
check(not Service.issue({},'home'),'issue checks authority')
local token=assert(Service.issue(actor,'home'))
check(not Service.start(actor,args(),'unissued'),'unissued token cannot start')
local preview=assert(Service.preview(actor,args()))
preview.rules.SOCIAL=0
check(not root.communityActivities.events[token],'preview creates no event')
local event=assert(Service.start(actor,args(),token))
check(event.state=='GATHERING' and not event.outcome,'intent is not attendance/completion')
check(policy('a','SOCIAL')==2 and policy('a','READING')==0,'roster gets explicit overrides')
check(policy('a','SIT')==1,'sparse rule inherits area')
check(policy('b','SOCIAL')==0,'unlisted NPC does not inherit event')
check(policy('a','SOCIAL',10)==1 and policy('a','SOCIAL',3,1)==1,'outside and other floor use ordinary policy')
event.rules.SOCIAL=0
check(policy('a','SOCIAL')==2,'returned event is detached')
local again=assert(Service.start(actor,args(),token))
check(again.id==event.id,'repeat command returns same event')
check(not Service.start(actor,args(),assert(Service.issue(actor,'home'))),'one active context per NPC')
check(not Service.cancel(actor,event.id,99),'stale cancel rejected')
check(Service.cancel(actor,event.id,event.revision),'matching cancel closes')
check(policy('a','SOCIAL')==0,'cancel restores area immediately')
local closed=assert(Service.start(actor,args(),token))
check(closed.state=='CLOSED','repeated closed token never restarts')
event=assert(Service.start(actor,args(),assert(Service.issue(actor,'home'))))
epochs.a=1
check(policy('a','SOCIAL')==0,'new explicit command immediately invalidates invitation')
local rows=assert(Service.view(actor,'home'))
check(rows[#rows].state=='CLOSED' and rows[#rows].roster.a.withdrawn,'refresh records withdrawn roster')
event=assert(Service.start(actor,args(),assert(Service.issue(actor,'home'))))
hours=event.endsAt
check(policy('a','SOCIAL')==0,'deadline revokes preference before refresh')
event=assert(Service.start(actor,args(),assert(Service.issue(actor,'home'))))
check(event.state=='GATHERING','expired intent frees participant at next command')
zone=assert(Zones.save(actor,'home',zone.id,zone.revision,{name='Garden changed',area=zone.area,enabled=true,rules=zone.rules}))
check(policy('a','SOCIAL')==0,'zone revision invalidates old context')
Service.view(actor,'home')
event=assert(Service.start(actor,args(),assert(Service.issue(actor,'home'))))
check(Service.finishScenes('SAVE_INTERRUPTED'),'save winds down preference intents')
check(policy('a','SOCIAL')==0 and Store.current().events[event.id].reason=='SAVE_INTERRUPTED','save retains history, removes override')
local expired=assert(Service.issue(actor,'home')) millis=millis+120001
check(not Service.start(actor,args(),expired),'expired issue rejected')
local bad=args() bad.rules={MUSIC=2}
check(not Service.preview(actor,bad),'unimplemented music not executable')
bad=args() bad.roster={'a','a'}
check(not Service.preview(actor,bad),'duplicate roster rejected')
event=assert(Service.start(actor,args(),assert(Service.issue(actor,'home'))))
local saved=Store.copy(root.communityActivities)
root={communityActivities=saved}
check(policy('a','SOCIAL')==0 and saved.events[event.id].reason=='LOAD_INTERRUPTED','loaded scene never resumes')
root={communityActivities={format=99,events={}}}
check(Service.policyAt('home','a',3,3,0,'SOCIAL')==0,'unknown context format disables overrides, keeps ordinary life')
check(root.communityActivities.format==99,'unknown data preserved')
print('activity-context: '..checks..' PASS (identity/clock/membership substitutes)')
