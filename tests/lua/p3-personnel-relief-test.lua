local checks=0 local function check(v,s) checks=checks+1 assert(v,s) end
local function list(values) return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local root={} local Probe={}
package.loaded['EmberRoutesProbe/Boot']=Probe
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() return {id='home'} end}
local skillReads,knowledgeReads=0,0 local level=3 local callbacks={}
Perks={None='none'} PerkFactory={PerkList=list({{getParent=function() return 'crafting' end,
    getName=function() return 'Carpentry' end}})}
Events={LevelPerk={Add=function(f) callbacks[#callbacks+1]=f end}}
getText=function(key,...) return key..':'..table.concat({...},',') end
getTextOrNull=function() return nil end
local npc={getPerkLevel=function() skillReads=skillReads+1 return level end,
    getKnownRecipes=function() knowledgeReads=knowledgeReads+1 return list({'MakeCakeBatter','Generator'}) end,
    getXp=function() return {getMultiplier=function() return 2 end} end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {handle=npc} end,valid=function() return true end}
local job={payload={kind='STUDY',step='SETTLING',sourceId='shelf',
    reading={fullType='Base.CookingMag1',total=0,stopped=true}},effects='KNOWN'}
package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return {job} end} end}
local Personnel=require 'EmberRoutesProbe/PersonnelService'
local d=Personnel.details({},'home','a')
check(d.skills[1].level==3 and #d.knowledge==2 and d.study.borrowed,'actual selected projection has full skills, knowledge and retained loan')
Personnel.details({},'home','a')
check(skillReads==1 and knowledgeReads==1,'unchanged detail refresh does not rescan skill/recipe collections')
level=4 callbacks[1](npc)
check(Personnel.details({},'home','a').skills[1].level==4 and skillReads==2,'level event invalidates only the affected cached member')
local rows=Personnel.rows(d,'knowledge',1)
check(#rows==4,'recipe page includes count, entries and page position')
Personnel.release('a') Personnel.details({},'home','a')
check(skillReads==3,'closing the selected view releases its snapshot')
root={}
Personnel.details({},'home','a') check(skillReads==4,'new world cannot reuse an old personnel snapshot')
-- Actual retained-loan survival leaf, mocked native consumption only.
local sample={hunger=0.6,thirst=0,fatigue=0,endurance=1,safe=true}
getTimestampMs=function() return 1000 end EmberRoutesProbeJava={}
package.loaded['EmberRoutesProbe/NeedsObserver']={sample=function() return sample end}
local main={} local food={getHungChange=function() return -0.5 end}
package.loaded['EmberRoutesProbe/SelfCareResources']={new=function(_,_,kind,ownOnly)
    check(ownOnly and kind=='EAT','survival relief only searches personal supplies')
    return {step=function() return {id=7,item=food,container=main},true end}
end}
local extended=0
package.loaded['EmberRoutesProbe/LaborStore']={extendPersonal=function() extended=extended+1 return true end}
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local saved=Record.create('loan','a')
local p=Record.begin(saved,'STUDY')
p.itemId=1 p.sourceId='shelf' p.settlementId='home' p.study={version=0} p.claims={'item:1'} saved.payload=p
package.loaded['EmberRoutesProbe/SelfCareActions']={consumption=function(c,kind,item,fraction)
    return {run=function()
        c.payload.consumption={attemptId=c.payload.attemptId,kind=kind,itemId=7,fullType='Base.Bread',
            before=0.5,after=0,consumed=0.5,fraction=fraction,started=true,completed=true,effects='KNOWN'}
        assert(c.persist()) return 'Success'
    end,halt=function() return true end}
end}
local c={actor={},npc={getInventory=function() return main end},job=saved,payload=p,items={},token={},effects='KNOWN',
    sameAttempt=function() return true end,valid=function() return true end,body={},
    persist=function() return Record.valid(saved) end,budget={scan=32}}
local Relief=require 'EmberRoutesProbe/StudyRelief'
local leaf=Relief.new(c)
check(leaf.run()=='Running' and extended==1,'borrowed book does not prevent acquiring an own-food claim')
check(leaf.run()=='Success' and Record.valid(saved),'separate survival effect is valid in the saved reading attempt')
check(p.kind=='STUDY' and p.itemId==1 and p.sourceId=='shelf' and p.claims[1]=='item:1',
    'own consumption neither replaces borrowed original nor erases its return responsibility')
check(p.relief.fact.itemId==7 and p.relief.finished,'survival food effect remains distinct from the book')
sample.safe=false
check(Relief.new(c).run()=='Failure','unsafe relief does not start a native action')
print('PASS '..checks..' P3 personnel-cache/retained-loan survival checks; native bodies mocked')
