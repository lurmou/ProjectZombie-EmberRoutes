-- Reuse the production-contract host, not a second personal service implementation.
ERMedicalLoopOnly=function(h)
    package.loaded['TimedActions/ISApplyBandage']=true
    package.loaded['XpSystem/ISUI/ISHealthPanel']=true
    local part={covered=false,life=0,kind=nil}
    function part:bandaged() return self.covered end
    function part:getBandageLife() return self.life end
    function part:getBandageType() return self.kind end
    function part:HasInjury() return true end function part:bleeding() return not self.covered end
    local parts={size=function() return 1 end,get=function() return part end}
    h.npc.getBodyDamage=function() return {getBodyParts=function() return parts end,getOverallBodyHealth=function() return 80 end} end
    local serial=500
    local function bandage(where)
        serial=serial+1 local item=h.food(serial,where)
        item.getFullType=function() return 'Base.Bandage' end
        return item
    end
    local applied=0
    ISApplyBandage={new=function(_,doctor,patient,item,bodyPart,apply)
        return {item=item,doIt=apply,isValid=function() return apply and item:getContainer()==h.main or not apply and part.covered end,
            start=function() end,update=function() end,stop=h.removeQueued,perform=h.removeQueued,
            complete=function()
                if apply then applied=applied+1 h.move(item,nil) part.covered=true part.life=10 part.kind=item:getFullType()
                else part.covered=false part.life=0 bandage(h.main) end
                return true
            end}
    end}
    local facts={partIndex=0,needsCare=true,replace=false}
    local item=bandage(h.source)
    local spec,c=h.begin(item,true,nil,facts)
    h.tick(spec) h.check(h.queued() and item.where==h.source,'warehouse original is transferred before medical action') h.native()
    h.tick(spec) h.check(h.queued().item==item and h.Store.owner(item.id),'same claimed original reaches native bandage')
    -- A different personal Job cannot reserve the same original.
    local other=h.Record.create('other-care','b')
    other.payload=assert(h.Record.begin(other,'MEDICAL')) other.payload.itemId=item.id other.payload.claims={'item:'..item.id}
    assert(require('EmberRoutesProbe/MedicalCare').begin(other.payload,{medical=facts},item))
    assert(h.jobs:create(other))
    h.check(not h.Store.claimPersonal(h.jobs:get(other.id)),'two NPCs cannot claim one bandage')
    h.native() h.tick(spec)
    h.check(spec.finished() and item.where==nil and applied==1,'consumed warehouse material needs no fabricated return')
    h.check(h.stop(spec).effects=='KNOWN' and not h.Store.owner(item.id),'positive treatment and stopped body release exactly the claimed input')
    h.check(h.jobs:get('care').payload.step=='IDLE','treated personal task settles normally')
    item=bandage(h.main) part.covered=false
    spec,c=h.begin(item,false,nil,facts) h.tick(spec)
    h.check(h.stop(spec).effects=='KNOWN' and item.where==h.main and not part.covered,'interrupted own bandage remains intact and wound remains untreated')
    item=bandage(h.source) part.covered=true part.life=0 part.kind='Base.Bandage' facts.replace=true
    spec,c=h.begin(item,true,nil,facts) h.tick(spec) h.native() h.tick(spec) h.native()
    h.tick(spec) h.native() h.tick(spec)
    local output=c.payload.medical.outputs[1]
    h.check(output and h.Store.owner(output) and h.queued(),'native removed bandage output is claimed before its return')
    h.native() h.tick(spec)
    h.check(c.items[output].where==h.source and spec.finished(),'dirty replacement output returns as its actual original instance')
    h.stop(spec)
    h.check(not h.Store.owner(output) and h.jobs:get('care').payload.step=='IDLE','replacement output release follows confirmed physical return')
    local saved=h.jobs:get('care')
    h.check(h.Execute.reconcile(saved,h.npc,{[output]=c.items[output]}),'cold positive receipt reconciles without replaying native treatment')
    saved.payload.medical.applied=false saved.payload.medical.effects='UNKNOWN' saved.payload.medical.phase='APPLYING'
    h.check(not h.Execute.reconcile(saved,h.npc,{[output]=c.items[output]}),'cold missing input without positive receipt remains unknown')
    -- Emergency relief must use the same Session while a borrowed meal cannot return.
    local meal=h.food(900,h.source)
    spec,c=h.begin(meal,true) h.tick(spec) h.native() h.tick(spec) h.native()
    h.accepted(false) h.tick(spec) h.stop(spec)
    saved=h.jobs:get('care')
    h.check(saved.payload.step=='SETTLING' and h.Store.owner(900),'blocked meal original remains a real obligation')
    item=bandage(h.main) part.covered=false
    package.loaded['EmberRoutesProbe/NeedsObserver']={sample=function()
        return {hunger=0,thirst=0,fatigue=0,endurance=1,safe=false,externalSafe=true}
    end}
    package.loaded['EmberRoutesProbe/SelfCareResources'].new=function()
        return {step=function() return {id=item.id,item=item,container=h.main,npc=h.npc},true end}
    end
    local recovery,rc=h.recover(saved,{[900]=meal})
    for i=1,4 do h.tick(recovery) if h.queued() then break end end
    h.check(h.queued() and h.queued().item==item,'blocked unrelated return does not prevent own-material emergency bandaging')
    h.native() h.tick(recovery) h.stop(recovery)
    saved=h.jobs:get('care')
    h.check(saved.payload.relief.medical.applied and saved.payload.relief.finished,'medical relief persists its distinct positive receipt')
    h.check(saved.payload.step=='SETTLING' and meal.where==h.main and h.Store.owner(900),
        'treatment does not erase or replace the blocked meal original')
end
dofile('tests/lua/self-care-loop-test.lua')
