ERMedicalServiceOnly=function(h)
    function getText(key) return key end
    local part={covered=false,life=0,bleed=true,injury=true,deep=false}
    function part:bandaged() return self.covered end function part:getBandageLife() return self.life end
    function part:bleeding() return self.bleed end function part:HasInjury() return self.injury end
    function part:deepWounded() return self.deep end
    local parts={size=function() return 1 end,get=function() return part end}
    for _,npc in pairs(h.npcs) do npc.getBodyDamage=function() return {getBodyParts=function() return parts end,
        getOverallBodyHealth=function() return 82 end} end end
    local Health=require 'EmberRoutesProbe/SelfCare/HealthAssessment'
    local can,why=Health.canWork(h.npcs.a)
    h.check(not can and why=='HEALTH_NEEDS_CARE','observed untreated injury blocks ordinary work with a precise reason')
    part.covered=true part.life=5
    h.advance(3000)
    h.check(Health.canWork(h.npcs.a),'bandaged shallow injury permits work below the old 95 health cutoff')
    part.deep=true h.advance(5000)
    can,why=Health.canWork(h.npcs.a)
    h.check(not can and why=='HEALTH_NEEDS_DOCTOR','deep injury retains professional-care requirement after first aid')
    part.covered=false part.deep=false
    package.loaded['EmberRoutesProbe/SelfCare/NeedsObserver'].sample=function(_,id,time)
        return {hunger=.99,thirst=.99,fatigue=0,endurance=1,safe=false,externalSafe=true,
            safety='RECENT_DAMAGE',observedAt=time}
    end
    h.item.getFullType=function() return 'Base.Bandage' end
    h.accept() h.offered(false) h.Service.install() h.advance(7000)
    h.check(#h.submitted==0,'missing medical supplies never starts a material-less treatment')
    h.advance(8000)
    h.check(#h.submitted==0,'missing supplies use a bounded retry delay without repeated claims')
    local waiting=require('EmberRoutesProbe/SelfCare/MedicalCare').demands('home')
    h.check(waiting[1].blocker=='MEDICAL_SUPPLY_MISSING','supply blocker survives fresh wound observations')
    h.offered(true) h.advance(13000)
    local job=h.Jobs.current():forNpc('a')[1]
    h.check(job and job.payload.kind=='MEDICAL','bleeding first aid outranks extreme hunger/thirst despite recent damage')
    h.check(#h.submitted==1 and job.payload.medical.itemId==9,'one original admitted through the existing personal claim protocol')
    h.check(h.Jobs.current():forNpc('b')[1].payload.step=='IDLE','second NPC cannot take the claimed supply')
    local rows=require('EmberRoutesProbe/SelfCare/MedicalCare').demands('home')
    h.check(#rows==2 and rows[1].urgency=='urgent','per-person bleeding facts become urgent medical demands')
    h.check(not Health.read({isDead=function() return false end}),'unknown body capabilities never qualify as healthy')
    local p=job.payload
    p.medical.effects='UNKNOWN' p.medical.phase='APPLYING'
    assert(h.Jobs.current():update(job.id,job.revision,{payload=p,effects='UNKNOWN'}))
    part.bleed=false part.injury=false
    require('EmberRoutesProbe/SelfCare/MedicalCare').observe(h.npcs.a,'a',{},13000)
    rows=require('EmberRoutesProbe/SelfCare/MedicalCare').demands('home')
    local retained=false for _,row in ipairs(rows) do if row.id=='DEMAND:medical:a' then retained=row.blocker=='MEDICAL_EFFECT_UNCONFIRMED' end end
    h.check(retained,'unknown treatment responsibility stays visible after wound observation changes')
end
dofile('tests/lua/self-care-service-test.lua')
