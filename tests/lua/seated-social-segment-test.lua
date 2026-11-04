package.path='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;'..package.path
-- Real furniture proofs, personal claims, Jobs, eligibility, seek geometry,
-- pair protocol and SIT leaf. Native bodies/pose/visibility are substitutes.
local f=dofile('tests/lua/repose-sites-test.lua')
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local now,hours=0,10
getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return hours end,getTimeOfDay=function() return 12 end} end
ZombRand=function() return 0 end
CharacterStat={PAIN='pain',BOREDOM='boredom',UNHAPPINESS='unhappy',STRESS='stress'}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/BusinessJobs']={hauls=function() return {tasks={},byNpc={},routes={}} end,flush=function() end}
package.loaded['EmberRoutesProbe/CraftRecord']={records=function() return {} end}
package.loaded['EmberRoutesProbe/LaborStore']=nil
local Store=require 'EmberRoutesProbe/LaborStore'
f.resourceProxy.resourceOwner=Store.resourceOwner
local Jobs=require 'EmberRoutesProbe/TaskJobs' local jobs=Jobs.current()
local Record=require 'EmberRoutesProbe/SelfCareRecord'
assert(jobs:create(Record.create('care-a','a'))) Store.data()
local blocked=false local socialRule=1
package.loaded['EmberRoutesProbe/ActivityService']={allowsPoint=function() return true end,policyAt=function(_,_,_,_,_,activity)
 return activity=='SOCIAL' and socialRule or 1 end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {status=function(_,id,job)
 return {kind='SELF_CARE',state='ACTIVE',jobId=job} end} end}
local sitting,resting=false,false local exits,moves,adds,lines=0,0,0,0
local stats={pain=0,boredom=20,unhappy=20,stress=0.5}
f.npc.getX=function() return 0.5 end f.npc.getY=function() return 0.5 end
f.npc.isSittingOnFurniture=function() return sitting end f.npc.isResting=function() return resting end
f.npc.isAsleep=function() return false end f.npc.isDead=function() return false end
f.npc.getStats=function() return {get=function(_,k) return stats[k] end,set=function(_,k,v) stats[k]=v end} end
f.npc.getBodyDamage=function() return {getOverallBodyHealth=function() return 100 end} end
f.npc.getPrimaryHandItem=function() end f.npc.getSecondaryHandItem=function() end
f.npc.addLineChatElement=function() lines=lines+1 end
f.npc.faceLocationF=function() error('seated participant must not turn via standing emote machinery') end
f.npc.playEmote=function() error('no unverified standing emote on seat') end
f.npc.getInventory=function() return {getItems=function() return f.list({}) end} end
local partner={isDead=function() return false end,getX=function() return 1.5 end,getY=function() return 0.5 end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(actor,id)
 check(actor==f.actor,'pair uses authorized actor') return {id=id,handle=id=='a' and f.npc or partner} end}
EmberRoutesProbeJava.socialVisible=function() return true end
for _,xy in ipairs({{0,0},{1,0},{0,1},{-1,0},{0,-1}}) do
 local sq=f.squares[xy[1]..':'..xy[2]..':0'] or f.square(xy[1],xy[2])
 for _,name in ipairs({'isSolid','isSolidTrans','HasStairs','isDoorSquare','isOutside'}) do sq[name]=function() return false end end
 sq.TreatAsSolidFloor=function() return true end sq.isFree=function() return not blocked end
 sq.getMovingObjects=function() return f.list({}) end sq.canReachTo=function() return not blocked end
end
local Sites=f.sites local view=Sites.view(f.actor,f.furniture)
local proof=assert(Sites.prepare({object=f.furniture,revision=view.revision,key='fixture-seat',settlementId=f.entry.id},f.actor,f.npc,'a','REST'))
local Service=require 'EmberRoutesProbe/LeisureService'
local Social=require 'EmberRoutesProbe/SocialCoordinator'
local sample={safe=true,hunger=0,thirst=0,fatigue=0,endurance=1}
local body={retained=function() return true end,repose=function(_,enter)
 resting=enter if not enter then exits=exits+1 sitting=false end return true end,
 move=function() moves=moves+1 error('seated body moved') end,add=function() adds=adds+1 error('second action') end}
package.loaded['EmberRoutesProbe/LeisurePosture']={new=function() return {enter=function() sitting=true return 'Success' end,
 leave=function() sitting=false return true end} end}
-- Isolation for the ordinary continuous SIT review: choose end only when asked.
local finishSit=false
Service.review=function() return finishSit end
local function newSit()
 Social.reset() Service.reset() now=now+10000 hours=hours+1 finishSit=false
 local job=jobs:get('care-a') local p=assert(Record.begin(job,'LEISURE'))
 p.leisureMemory={cooldowns={}} p.step='ACTING' p.leisure={format=1,activity='SIT',hours=hours}
 p.site=proof p.claims=Sites.keys(proof,'REST') p.settlementId=f.entry.id
 p.membershipRevision=1 p.settlementRevision=f.entry.revision
 assert(jobs:update(job.id,job.revision,{payload=p})) job=jobs:get(job.id)
 assert(Store.claimPersonal(job))
 local c={actor=f.actor,npc=f.npc,job=job,payload=p,effects='KNOWN',body=body,budget={scan=32,paths=8,containers=0},
  sample=function() return sample end,sameAttempt=function() return true end}
 c.valid=function() return Service.valid(f.actor,f.npc,'a',p) end
 c.persist=function() local live=jobs:get(job.id) return jobs:update(job.id,live.revision,{payload=p,effects=c.effects}) end
 local leaf=require('EmberRoutesProbe/LeisureSit').new(c)
 check(leaf.run()=='Running' and leaf.run()=='Running','SIT enters and seats through original leaf')
 Service.workState('a',f.entry,'IDLE')
 return c,leaf
end
local function advertisePartner() Social.advertise('b',f.entry,{x=1.5,y=0.5,z=0},now,f.actor) end
local function startPair(c,leaf)
 Service.workState('a',f.entry,'IDLE') advertisePartner()
 c.budget={scan=32,paths=8,containers=0}
 check(leaf.run()=='Running','seated leaf invites without leaving SIT')
 local key=assert(Social.pending('a'))
 check(Social.accept(key,'b','stand-attempt',now),'standing accepts normally')
 check(Social.arrive(key,'b','stand-attempt',hours),'standing arrival via normal protocol')
 check(leaf.run()=='Running','seated arrival does not move')
 check(Social.view(key,'a',c.payload.attemptId,now).phase=='CONVERSE','arrival barrier starts converse')
 return key
end
local function releaseSit(c,leaf,reason)
 check(leaf.halt(),'normal SIT halt confirms exit')
 for _,name in ipairs({'ISInventoryTransferAction','ISEatFoodAction','ISDrinkFluidAction'}) do package.loaded['TimedActions/'..name]=true end
 package.loaded['EmberRoutesProbe/CraftSupply']={} package.loaded['EmberRoutesProbe/SelfCareResources']={}
 local spec=require('EmberRoutesProbe/SelfCareExecution').new(f.actor,{id='a',handle=f.npc},jobs:get(c.job.id),nil,function() return {} end)
 check(spec.persistFailure({bodyStopped=true,effects='KNOWN'},reason),'normal SelfCare settlement succeeds')
 check(not Store.resourceOwner(c.payload.claims[1]) and #jobs:get(c.job.id).payload.claims==0,'seat released only by normal SIT settlement')
end
local c,leaf=newSit()
check(Social.seated('a',f.actor)~=nil and not Social.available('a') and Social.available('b'),'seated eligibility extends standing eligibility')
local owner=Store.resourceOwner(c.payload.claims[1])
local savedProof=c.payload.site
local key=startPair(c,leaf)
local a=Social.view(key,'a',c.payload.attemptId,now) local b=Social.view(key,'b','stand-attempt',now)
check(a.point.x==0.5 and a.point.y==0.5 and a.point.z==0,'pair seated point is seat point')
check(math.abs(a.point.x-b.point.x)+math.abs(a.point.y-b.point.y)==1 and a.point.z==b.point.z,'standing point is adjacent same floor')
check(a.ends==hours+10/60,'ten game minutes unchanged')
check(Store.resourceOwner(c.payload.claims[1]).taskId==owner.taskId
 and Store.resourceOwner(c.payload.claims[1]).generation==owner.generation
 and #c.payload.claims==1 and c.payload.site==savedProof and exits==0,'seat owner and proof unchanged during converse')
-- Preserve original duration, but exercise the still-unexpired contract explicitly.
c.payload.leisure.untilHours=hours+1 assert(c.persist())
hours=a.ends now=now+100
check(leaf.run()=='Running' and not c.payload.leisure.finished and sitting and resting,'unexpired SIT resumes in same leaf')
check(not c.payload.leisure.seatedSocial and not Social.pending('a') and lines>0,'pair released and shared lines played')
check(stats.boredom==14 and stats.unhappy==17 and stats.stress==0.48,'shared effects applied once')
check(c.payload.leisureMemory.cooldowns.SOCIAL>hours and c.payload.leisureMemory.decisionAfter>hours,'normal SOCIAL cooldown and decision pause')
check(Store.resourceOwner(c.payload.claims[1]).taskId==owner.taskId
 and Store.resourceOwner(c.payload.claims[1]).generation==owner.generation and moves==0 and adds==0,'no second body action or claim during/resuming converse')
check(leaf.run()=='Running' and stats.boredom==14,'effects not replayed on resumed SIT')
releaseSit(c,leaf,'COMPLETED')
Social.release(key,'b','stand-attempt',true)
-- Needs interruption uses exactly the normal leaf halt + SelfCare settlement.
c,leaf=newSit() key=startPair(c,leaf)
releaseSit(c,leaf,'LEISURE_NEEDS_CARE')
check(not Social.view(key,'b','stand-attempt',now),'needs halt cancels pair')
Social.release(key,'b','stand-attempt',true)
-- Expired SIT ends normally after the full converse, not midway through it.
c,leaf=newSit() key=startPair(c,leaf)
local deadline=Social.view(key,'a',c.payload.attemptId,now).ends
c.payload.leisure.untilHours=deadline assert(c.persist())
hours=deadline now=now+100
check(leaf.run()=='Success' and c.payload.leisure.finished and not sitting and not resting,'expired SIT exits after converse')
releaseSit(c,leaf,'COMPLETED') Social.release(key,'b','stand-attempt',true)
-- A standing cancellation resumes the same unexpired SIT, without re-claim.
c,leaf=newSit() key=startPair(c,leaf)
local originalClaim=c.payload.claims[1]
assert(Social.cancel(key,'b','stand-attempt'))
check(leaf.run()=='Running' and sitting and not c.payload.leisure.finished,'standing cancellation resumes SIT')
check(Store.resourceOwner(originalClaim).taskId==c.job.id,'cancel preserves original seat owner')
releaseSit(c,leaf,'COMPLETED') Social.release(key,'b','stand-attempt',true)
-- Standing may initiate against a seated advert through the same seek callback.
c,leaf=newSit()
check(not Service.seatedSocial(c),'seated side advertises before a partner is present')
local def=require('EmberRoutesProbe/LeisureRegistry').get('SOCIAL')
local candidate=def.seek({actor=f.actor,npc=partner,id='b',entry=f.entry,point={x=1.5,y=0.5,z=0},
 now=now,hours=hours,cooling={},budget={scan=8,paths=1},state={}})
check(candidate and candidate.leisure.activity=='SOCIAL','standing initiator uses original SOCIAL candidate')
key=candidate.leisure.socialId
local seatedPoint=Social.view(key,'a',nil,now).point
check(seatedPoint.x==0.5 and seatedPoint.y==0.5,'reverse initiator preserves seat point')
Social.withdraw('b') releaseSit(c,leaf,'COMPLETED')
-- No adjacent point means no pair and no released seat.
c,leaf=newSit() advertisePartner() blocked=true
check(not Service.seatedSocial(c) and not Social.pending('a'),'no adjacent standable point means no pair') blocked=false
check(Store.resourceOwner(c.payload.claims[1])~=nil,'failed geometry retains seat')
-- Zone, needs, SOCIAL cooldown and decision pause retain admission gates.
socialRule=0 check(not Service.seatedSocial(c),'SOCIAL zone prohibition') socialRule=1
sample.hunger=1 check(not Service.seatedSocial(c),'needs gate') sample.hunger=0
c.payload.leisureMemory={cooldowns={SOCIAL=hours+1}} check(not Service.seatedSocial(c),'SOCIAL cooldown')
c.payload.leisureMemory={cooldowns={},decisionAfter=hours+1} check(not Service.seatedSocial(c),'decision pause')
c.payload.leisureMemory={cooldowns={}}
local p=c.payload
for _,kind in ipairs({'READING','STROLL','FITNESS','SMOKE'}) do
 p.leisure.activity=kind assert(c.persist()) check(not Social.participant('a',f.actor),kind..' ineligible')
end
p.leisure.activity='SIT' assert(c.persist())
-- Membership changes invalidate pair formation.
local member=require('EmberRoutesProbe/MembershipService').view('a') member.pending={}
check(not Service.seatedSocial(c),'pending membership denied') member.pending=nil
-- Second actual claimed seat: two seated participants cannot pair.
local otherProof=assert(Sites.prepare({object=f.other,revision=Sites.view(f.actor,f.other).revision,key='other-seat',settlementId=f.entry.id},f.actor,f.npc,'b','REST'))
assert(jobs:create(Record.create('care-b','b')))
local jb=jobs:get('care-b') local pb=assert(Record.begin(jb,'LEISURE'))
pb.step='ACTING' pb.leisure={format=1,activity='SIT',hours=hours,started=true,seated=true}
pb.membershipRevision=1 pb.settlementRevision=f.entry.revision
pb.site=otherProof pb.claims=Sites.keys(otherProof,'REST') pb.settlementId=f.entry.id
assert(jobs:update(jb.id,jb.revision,{payload=pb})) assert(Store.claimPersonal(jobs:get(jb.id)))
partner.isSittingOnFurniture=function() return true end partner.isResting=function() return true end
partner.getZ=function() return 0 end
Social.reset() Service.workState('a',f.entry,'IDLE') advertisePartner()
check(Social.seated('b',f.actor)~=nil,'second seat has valid independent proof/claim')
check(not Service.seatedSocial(c) and not Social.pending('a'),'seated-seated not formed')
releaseSit(c,leaf,'COMPLETED')
print('PASS seated-social directed checks='..checks..'; native bodies, pose, visibility mocked')
