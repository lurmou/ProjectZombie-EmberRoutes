local checks=0 local function check(value,label) checks=checks+1 assert(value,label) end
local function list(values)
    return {size=function() return #values end,get=function(_,i) return values[i+1] end,
        contains=function(_,v) for _,x in ipairs(values) do if v==x then return true end end return false end,
        isEmpty=function() return #values==0 end}
end
local now,root=0,{} getTimestampMs=function() return now end
getGameTime=function() return {getWorldAgeHours=function() return 10 end} end
instanceof=function(item,kind) return kind=='Literature' and item.literature==true end
CharacterTrait={ILLITERATE='illiterate'} SkillBook={Carpentry={perk='wood'}}
local owners={} local reads,known={},{} local illiterate=false
package.loaded['EmberRoutesProbe/Boot']={}
local invItems={} local inventory={getItems=function() return list(invItems) end}
local shelfItems={} local shelf={getItems=function() return list(shelfItems) end}
local npc={getInventory=function() return inventory end,hasTrait=function() return illiterate end,getZ=function() return 0 end,
    getX=function() return 1 end,getY=function() return 1 end,
    getKnownRecipes=function() return list(known) end,getPerkLevel=function() return 0 end,
    getAlreadyReadPages=function(_,id) return reads[id] or 0 end,tooDarkToRead=function() return false end}
local function book(id,skill,pages)
    local item={literature=true,container=shelf,read=0,skill=skill,pages=pages}
    function item:getID() return id end
    function item:getFullType() return 'Base.Book'..id end
    function item:getNumberOfPages() return self.pages end
    function item:getAlreadyReadPages() return self.read end
    function item:getIsCraftingConsumed() return false end
    function item:getModData() return {literatureTitle='native-recipe-magazine'} end
    function item:getLearnedRecipes() return list(skill and {} or {'MakeCakeBatter'}) end
    function item:getSkillTrained() return self.skill end
    function item:getLvlSkillTrained() return 1 end
    function item:getMaxLevelTrained() return 2 end
    function item:getContainer() return self.container end
    return item
end
local magazine,skill=book(1,nil,-1),book(2,'Carpentry',100)
shelfItems={magazine,skill}
local resolutions=0 local endpoint={id='shelf',container=shelf}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    accepts=function() return true end,logistics=function() return 'STORAGE' end,revalidate=function() return endpoint end}
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return {'shelf'} end}
package.loaded['EmberRoutesProbe/CraftSupply']={endpoint=function() resolutions=resolutions+1 return endpoint end}
package.loaded['EmberRoutesProbe/LaborStore']={owner=function(id) return owners[id] end}
package.loaded['EmberRoutesProbe/PlanningWake']={capture=function() return {} end,changed=function() return false end}
local Library=require 'EmberRoutesProbe/LibraryIndex'
check(Library.eligible(magazine),'native recipe magazines with -1 pages and literatureTitle are eligible')
check(Library.useful(npc,magazine,'MakeCakeBatter'),'unknown target magazine is useful')
illiterate=true check(not Library.useful(npc,magazine,'MakeCakeBatter'),'illiterate reader cannot borrow for study') illiterate=false
local entry={id='home',revision=1}
dofile('tests/lua/membership-fixture.lua')(function() return entry end,{'a'})
local budget={scan=32,containers=4}
local candidate,done=Library.choose({},npc,entry,'MakeCakeBatter',budget)
check(done and candidate.id==1 and budget.scan<32,'shared bounded discovery finds the exact original')
local again=Library.choose({},npc,entry,nil,{scan=32,containers=4})
check(again.id==2 and resolutions==1,'another reader reuses the settlement container observation')
local novel=book(3,nil,0)
novel.getBoredomChange=function() return -10 end novel.getUnhappyChange=function() return -5 end
novel.getLearnedRecipes=function() return list({}) end
local already=false npc.isLiteratureRead=function() return already end
check(Library.eligible(novel) and Library.useful(npc,novel,nil,true),'ordinary unpaged novel uses native leisure benefits')
check(not Library.useful(npc,novel,nil,false),'novel is not misclassified as work-skill study')
already=true check(not Library.useful(npc,novel,nil,true),'native read identity suppresses an exhausted leisure original')
owners[1]={taskId='other'}
check(not Library.revalidate(candidate),'claimed original cannot be borrowed twice') owners[1]=nil
reads[skill:getFullType()]=100
check(not Library.useful(npc,skill,nil),'completed personal skill-book record suppresses rereading')
reads[skill:getFullType()]=0
package.loaded['TimedActions/ISReadABook']=true
local queued,completeCount,live,retained=nil,0,true,true
ISReadABook={new=function(_,character,item)
    -- Models vanilla getDuration: shared item pages are reset from this reader.
    item.read=character:getAlreadyReadPages(item:getFullType())
    return {start=function() end,update=function() end,isValid=function() return true end,
        complete=function() completeCount=completeCount+1 known[1]='MakeCakeBatter' item.read=item.pages return true end,
        perform=function() queued=nil end,stop=function() queued=nil end}
end}
ISTimedActionQueue={hasAction=function(action) return queued==action end}
local wakes=0
package.loaded['EmberRoutesProbe/StudyService']={completed=function() wakes=wakes+1 end}
local Actions=require 'EmberRoutesProbe/StudyActions'
local function context(item,target)
    item.container=inventory invItems={item}
    return {npc=npc,job={npcId='a'},payload={attemptId='j:1',itemId=item:getID(),settlementId='home',study={knowledge=target}},
        sameAttempt=function() return true end,valid=function() return true end,persist=function() return true end,
        body={current=function() return live end,retained=function() return retained end,
            add=function(action) queued=action return true end,clear=function() if queued then queued:stop() end return true end}}
end
local c=context(magazine,'MakeCakeBatter') local leaf=Actions.read(c,magazine)
check(leaf.run()=='Running' and not c.payload.reading.started,'native action is fenced before start')
local action=queued action:start()
check(#known==0,'starting magazine does not grant its recipe')
action:complete() action:complete() action:perform()
check(completeCount==1 and wakes==1 and known[1]=='MakeCakeBatter','only vanilla complete learns, once, and wakes work')
check(leaf.run()=='Success' and c.payload.reading.total==0,'unpaged magazine success uses native completion and knowledge')
known={} magazine.read=0 live=true retained=true
local partial=context(magazine,'MakeCakeBatter') local interrupted=Actions.read(partial,magazine)
assert(interrupted.run()=='Running') queued:start()
live=false check(interrupted.halt() and #known==0 and partial.payload.reading.stopped,'interrupted magazine grants nothing')
live=true retained=true
reads[skill:getFullType()]=24 skill.read=99
local second=context(skill,nil) local reading=Actions.read(second,skill)
check(reading.run()=='Running' and skill.read==24,'borrower resumes own pages rather than prior borrower item progress')
local stale=queued queued=nil retained=false stale:complete()
check(completeCount==1,'stale callback cannot apply native learning') retained=true
local lost=context(skill,nil) local lostLeaf=Actions.read(lost,skill)
assert(lostLeaf.run()=='Running') queued:start() skill.container=shelf queued=nil
check(lostLeaf.run()=='Failure' and lost.effects=='UNKNOWN','missing borrowed original quarantines effects')
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local j=Record.create('j','a') local payload=assert(Record.begin(j,'STUDY'))
payload.itemId=1 payload.sourceId='shelf' payload.settlementId='home' payload.study={version=0}
j.payload=payload check(Record.valid(j),'study persistent payload is versioned and validated')
j.payload.reading={attemptId='j:1',itemId=1,fullType='Base.Book1',before=0,total=0,started=true,effects='KNOWN',stopped=true}
check(Record.valid(j),'native unpaged magazine facts survive the record validator')
j.payload.reading.total=-1 check(not Record.valid(j),'invalid persisted normalized page count is rejected')
-- Actual offer service fences new work and policy changes before borrowing.
package.loaded['EmberRoutesProbe/StudyService']=nil
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return entry end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function() return true end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode='HOLD'} end}
local order={state='WAITING',recipeId='cake'} local revision=0
package.loaded['EmberRoutesProbe/PublicWork']={order=function() return order end,
    priorities=function() return {crafting=3,revision=revision} end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
local Study=require 'EmberRoutesProbe/StudyService'
magazine.container=shelf skill.container=shelf invItems={} reads[skill:getFullType()]=0
Study.offer('a',entry,{orderId='order',recipeId='cake',knowledge={'alias','MakeCakeBatter'}})
local borrowed=Study.candidate({},npc,'a',{scan=32,containers=4})
check(borrowed and borrowed.id==1 and borrowed.study.knowledge=='MakeCakeBatter','native recipe aliases select the matching taught knowledge key')
local intent={settlementId='home',study=borrowed.study,membershipRevision=borrowed.membershipRevision,settlementRevision=borrowed.settlementRevision}
check(Study.valid({},npc,'a',intent),'fresh idle offer is valid for its own work-policy revision')
revision=1 check(not Study.valid({},npc,'a',intent),'changed worker policy invalidates the pending study') revision=0
Study.changed('home')
check(not Study.candidate({},npc,'a',{scan=32,containers=4}),'new public work cannot silently refresh an old idle grant')
check(not Study.valid({},npc,'a',intent),'new work invalidates the active ordinary-idle grant')
Study.offer('a',entry,{orderId='order',recipeId='cake',knowledge={'MakeCakeBatter'}})
local resumed=Study.candidate({},npc,'a',{scan=32,containers=4})
order.state='CANCELLED'
check(not Study.valid({},npc,'a',{settlementId='home',study=resumed.study}),'cancelled source order stops its demanded study')
print('PASS '..checks..' P3 shared-library/reading/custody checks; native bodies mocked')

getGameTime=function() return {getWorldAgeHours=function() return 1 end} end
local paused,done,reason=Study.candidate({},npc,'a',{scan=32,containers=4},{decisionAfter=2})
check(not paused and done and reason=='LEISURE_PAUSE','cancelled demand becomes autonomous study and respects pause')
order.state='WAITING'
Study.offer('a',entry,{orderId='order',recipeId='cake',knowledge={'MakeCakeBatter'}})
local demanded=Study.candidate({},npc,'a',{scan=32,containers=4},{decisionAfter=2})
check(demanded~=nil,'valid work-demanded study is not delayed by leisure pause')
local readingHours=10 getGameTime=function() return {getWorldAgeHours=function() return readingHours end} end
live,retained=true,true reads[skill:getFullType()]=0 skill.read=0 already=false
skill.getBoredomChange=function() return -10 end
local limited=context(skill,nil) limited.payload.study.leisure=true
local inActivityArea=true
-- This fixture has no live settlement ledger; activity policy is a separate seam.
package.loaded['EmberRoutesProbe/ActivityService']={policyAt=function() return 1 end,
    allowsPoint=function() return inActivityArea end}
local window=Actions.read(limited,skill)
assert(window.run()=='Running')
local timed=queued timed.forceStop=function(self) self:stop() end timed:start()
reads[skill:getFullType()]=12 skill.read=12 readingHours=11
local completedBefore=completeCount timed:update()
check(limited.payload.reading.windowEnded and limited.payload.reading.stopped and not limited.payload.reading.completed
    and completeCount==completedBefore and reads[skill:getFullType()]==12,
    'one-hour leisure window stops with native page progress; never fabricates completion')
assert(window.run()=='Success')
local autonomous=context(skill,nil) local free=Actions.read(autonomous,skill)
assert(free.run()=='Running')
local freeAction=queued freeAction.forceStop=function(self) self:stop() end freeAction:start()
readingHours=12 reads[skill:getFullType()]=24 skill.read=24 freeAction:update()
check(autonomous.payload.reading.windowEnded and not autonomous.payload.reading.completed,
    'ordinary autonomous skill reading shares the leisure time window')
local demandedRead=context(skill,nil) demandedRead.payload.study.orderId='work-order'
local demandedLeaf=Actions.read(demandedRead,skill)
assert(demandedLeaf.run()=='Running') queued:start() readingHours=14 queued:update()
check(not demandedRead.payload.reading.windowEnded and not demandedRead.payload.reading.stopped,
    'work-demanded study retains native duration rather than an idle time cap')
assert(demandedLeaf.halt())
inActivityArea=false
local outside=context(skill,nil) outside.payload.study.leisure=true
check(Actions.read(outside,skill).run()=='Failure' and outside.reason=='READ_ZONE_DISABLED',
    'leisure reading cannot begin outside the current gathering area')
print('PASS '..checks..' P3 reading checks including activity-area boundary; native bodies mocked')
