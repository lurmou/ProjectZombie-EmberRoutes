-- Installed ISApplyBandage start/complete; engine bodies/inventory are explicit hosts.
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local queued,animations,events,serial=nil,{}, {},10
ISBaseTimedAction={}
function ISBaseTimedAction:derive() local c={} c.__index=c return setmetatable(c,{__index=self}) end
function ISBaseTimedAction.new(cls,npc) return setmetatable({character=npc},{__index=cls}) end
function ISBaseTimedAction.perform() queued=nil end function ISBaseTimedAction.stop() queued=nil end
function ISBaseTimedAction:setActionAnim(v) animations[#animations+1]=v end
function ISBaseTimedAction:setAnimVariable() end function ISBaseTimedAction:setOverrideHandModels() end
package.loaded['TimedActions/ISBaseTimedAction']=true
function isClient() return false end function isServer() return false end
function getText(k) return k end function ZombRandFloat(a,b) return (a+b)/2 end
function syncBodyPart() end function syncPlayerStats() end function addXp() end
CharacterTrait={HEMOPHOBIC='HEMOPHOBIC'} CharacterStat={PANIC='PANIC'}
CharacterActionAnims={Bandage='Bandage'} Perks={Doctor='Doctor'}
BodyPartType={Groin=6,ToIndex=function(i) return i end}
ISHealthPanel={DidPatientMove=function() return false end,getBandageType=function() return 'LeftArm' end,
    setBodyPartActionForPlayer=function() end}
package.loaded['XpSystem/ISUI/ISHealthPanel']=true
local part={covered=false,life=0,injury=true,bleed=true}
function part:getIndex() return 1 end function part:bandaged() return self.covered end
function part:getBandageLife() return self.life end function part:getBandageType() return self.kind end
function part:HasInjury() return self.injury end function part:bleeding() return self.bleed end
function part:getBleedingTime() return 5 end function part:isGetBandageXp() return false end
function part:manipulatingUsername() return '' end function part:setManipulatingUsername() end
local root={items={}}
function root:getItems() return self end function root:size() return #self.items end
function root:get(i) return self.items[i+1] end
function root:contains(item) for _,v in ipairs(self.items) do if v==item then return true end end return false end
function root:Remove(item) for i,v in ipairs(self.items) do if v==item then table.remove(self.items,i) item.container=nil return end end end
function root:AddItem(item) self.items[#self.items+1]=item item.container=self return item end
local function material(kind)
    serial=serial+1 local item={id=serial,kind=kind or 'Bandage'}
    function item:getID() return self.id end function item:getContainer() return self.container end
    function item:getFullType() return 'Base.'..self.kind end function item:getModule() return 'Base' end
    function item:getType() return self.kind end function item:getBandagePower() return 2 end
    function item:isAlcoholic() return false end function item:isInfected() return false end
    function item:hasTag() return true end function item:setJobType() end function item:setJobDelta() end
    return root:AddItem(item)
end
function instanceItem(fullType) local item=material(fullType:sub(6)) root:Remove(item) return item end
ItemTag={REUSABLE_BANDAGE='REUSABLE_BANDAGE'}
local parts={size=function() return 2 end,get=function() return part end}
local damage={getBodyParts=function() return parts end}
function damage:SetBandaged(_,covered,life,alcoholic,kind) part.covered,part.life,part.kind=covered,life,kind end
local npc={getInventory=function() return root end,getBodyDamage=function() return damage end,
    isTimedActionInstant=function() return false end,getPerkLevel=function() return 0 end,
    getX=function() return 0 end,getY=function() return 0 end,hasTrait=function() return false end,
    getUsername=function() return 'npc' end,playSound=function() return 0 end,
    playerVoiceSound=function() return 0 end,reportEvent=function(_,event) events[#events+1]=event end,
    getEmitter=function() return {isPlaying=function() return false end} end}
ISTimedActionQueue={hasAction=function(a) return queued==a end}
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/shared/TimedActions/ISApplyBandage.lua')
package.loaded['TimedActions/ISApplyBandage']=true
package.loaded['EmberRoutesProbe/SelfCareCustody']={located=function(c,id)
    return c.items[id] and c.items[id]:getContainer()==root
end}
local Actions=require 'EmberRoutesProbe/MedicalActions'
local Record=require 'EmberRoutesProbe/MedicalRecord'
local function context(item,replace)
    local c={npc=npc,items={[item.id]=item},effects='KNOWN',payload={kind='MEDICAL',itemId=item.id,attemptId='job:1'}}
    c.payload.medical={version=1,partIndex=1,itemId=item.id,fullType=item:getFullType(),attemptId='job:1',
        replace=replace,applied=false,removed=false,phase='PREPARED',effects='KNOWN',outputs={}}
    c.valid=function() return true end c.sameAttempt=c.valid c.persist=function() return Record.valid(c.payload) end
    c.claimOutputs=function(ids) for _,id in ipairs(ids) do check(c.items[id]~=nil,'native replacement output retains its actual instance') end return c.persist() end
    c.body={retained=c.valid,add=function(action) queued=action action:start() return true end,
        clear=function() if queued then queued:stop() end return true end}
    return c
end
local item=material() local c=context(item,false) local leaf=Actions.new(c,item)
check(leaf.run()=='Running' and queued.item==item,'real native action receives the claimed original')
check(animations[1]=='Bandage' and events[1]=='EventBandage','installed start owns animation and event')
local action=queued action:complete() action:complete()
check(leaf.run()=='Running','effect receipt still waits for the original native perform/queue exit')
action:perform()
check(leaf.run()=='Success' and part:bandaged() and not root:contains(item),'one native completion consumes the original and bandages the body part')
check(Record.consumed(c.payload) and c.payload.medical.effects=='KNOWN','positive receipt permits later custody settlement')
item=material() part.covered=false c=context(item,false) leaf=Actions.new(c,item) leaf.run()
queued:complete()
check(leaf.halt() and queued==nil and Record.consumed(c.payload),'stop after native effect still runs native cleanup and preserves its positive receipt')
item=material() part.covered=false c=context(item,false) leaf=Actions.new(c,item) leaf.run()
action=queued action:stop()
check(leaf.run()=='Failure' and root:contains(item) and c.effects=='KNOWN','stop before complete retains unused original without pretending treatment')
part.covered=true part.life=0 part.kind='Base.Bandage'
item=material() c=context(item,true) leaf=Actions.new(c,item) leaf.run()
check(queued.item==nil and queued.doIt==false,'replacement first invokes native removal with no replacement item')
queued:complete() queued:perform()
check(leaf.run()=='Running' and queued.item==item and queued.doIt,'replacement then applies the reserved clean original')
queued:complete() queued:perform()
check(leaf.run()=='Success' and #c.payload.medical.outputs==1,'removed native bandage remains a claimed output')
c.payload.medical.applied=false c.payload.medical.effects='UNKNOWN' c.payload.medical.phase='APPLYING'
check(Actions.observe(c,nil)=='UNKNOWN','missing original without a durable receipt never proves completion')
print('PASS '..checks..' installed bandage action checks; game animation/physics NOT RUN')
