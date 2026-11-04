-- Native bandage/remove-bandage actions; one original, one body part, one Session.
require 'TimedActions/ISApplyBandage'
require 'XpSystem/ISUI/ISHealthPanel'
local Health=require 'EmberRoutesProbe/HealthAssessment'
local Record=require 'EmberRoutesProbe/MedicalRecord'
local M={}
local function inventory(npc)
    local list=npc:getInventory():getItems() if list:size()>512 then return end
    local ids={} for i=0,list:size()-1 do local item=list:get(i) ids[item:getID()]=item end return ids
end
local function failed(c,reason)
    c.reason=reason c.effects='UNKNOWN' c.payload.medical.effects='UNKNOWN' c.payload.medical.phase='UNKNOWN'
    c.persist() return 'Failure'
end
function M.observe(c,item)
    local m=c.payload.medical
    if not m then return 'KNOWN' end
    if Record.consumed(c.payload) then return 'KNOWN' end -- Durable positive native receipt.
    if (m.phase=='PREPARED' or m.phase=='STOPPED' or m.phase=='READY') and m.effects=='KNOWN'
        and require('EmberRoutesProbe/SelfCareCustody').located(c,m.itemId) then return 'KNOWN' end
    local part=Health.part(c.npc,m.partIndex)
    local held=item and item:getID()==m.itemId and item:getContainer()==c.npc:getInventory()
        and c.npc:getInventory():contains(item)
    if not part or not held then return 'UNKNOWN' end
    if (m.phase=='REMOVING' or m.phase=='APPLYING') and not m.stopped then return 'UNKNOWN' end
    if m.phase=='REMOVING' and not m.removed and (not part:bandaged() or part:getBandageType()~=m.oldType) then return 'UNKNOWN' end
    if m.phase=='APPLYING' and part:bandaged() then return 'UNKNOWN' end
    m.phase='STOPPED' m.effects='KNOWN'
    return 'KNOWN'
end
function M.new(c,item)
    local m=c.payload.medical local action,completed,stopped,performed
    local leaf={kind='Action'}
    local function persist() return c.persist() end
    local function active() return c.valid() and c.effects~='UNKNOWN' and c.sameAttempt() end
    local function owned()
        return item:getID()==m.itemId and item:getContainer()==c.npc:getInventory()
            and c.npc:getInventory():contains(item)
    end
    function leaf.run()
        if not active() then return 'Failure' end
        if m.applied then
            if action and ISTimedActionQueue.hasAction(action) then return 'Running' end
            return 'Success'
        end
        local part=Health.part(c.npc,m.partIndex)
        if not part or not owned() then return failed(c,'MEDICAL_ORIGINAL_UNCONFIRMED') end
        if action then
            if ISTimedActionQueue.hasAction(action) then return 'Running' end
            if not completed then
                if not stopped then return failed(c,'MEDICAL_EFFECT_UNCONFIRMED') end
                c.reason='MEDICAL_INTERRUPTED' return 'Failure'
            end
            action=nil completed,stopped,performed=false,false,false
        elseif m.phase=='APPLYING' or m.phase=='REMOVING' or m.phase=='UNKNOWN' then
            return failed(c,'MEDICAL_EFFECT_UNCONFIRMED') -- Never rebuild an interrupted native effect.
        end
        if m.applied then return 'Success' end
        local remove=m.replace and not m.removed
        if remove and (not part:bandaged() or part:getBandageLife()>0) then
            c.reason='MEDICAL_WOUND_CHANGED' return 'Failure'
        end
        if not remove and part:bandaged() then c.reason='MEDICAL_WOUND_CHANGED' return 'Failure' end
        m.oldType=remove and part:getBandageType() or m.oldType
        m.stopped=nil
        m.phase=remove and 'REMOVING' or 'APPLYING' m.effects='UNKNOWN'
        if not persist() then return 'Failure' end
        local medicalItem
        if not remove then medicalItem=item end
        action=ISApplyBandage:new(c.npc,c.npc,medicalItem,part,not remove)
        local nativeStart,nativeValid,nativeUpdate=action.start,action.isValid,action.update
        local nativeComplete,nativePerform,nativeStop=action.complete,action.perform,action.stop
        action.useProgressBar,action.forceProgressBar=false,false
        action.isValid=function(self)
            return active() and owned() and Health.part(c.npc,m.partIndex)==part and nativeValid(self)
        end
        action.start=function(self) if active() then nativeStart(self) end end
        action.update=function(self) if active() then nativeUpdate(self) end end
        action.complete=function(self)
            if completed or stopped or not active() or not self:isValid() then return false end
            local before=inventory(c.npc) if not before then failed(c,'MEDICAL_INVENTORY_UNCONFIRMED') return false end
            completed=true -- Fence duplicate callbacks before invoking vanilla.
            local result=nativeComplete(self)
            if remove then
                if part:bandaged() then failed(c,'MEDICAL_EFFECT_UNCONFIRMED') return false end
                local after=inventory(c.npc) if not after then failed(c,'MEDICAL_INVENTORY_UNCONFIRMED') return false end
                local outputs={}
                for id,value in pairs(after) do if not before[id] then
                    if #outputs>=1 or value:getFullType()~=m.oldType then failed(c,'MEDICAL_OUTPUT_UNCONFIRMED') return false end
                    outputs[#outputs+1]=id c.items[id]=value
                end end
                m.outputs=outputs m.removed=true m.phase='READY' m.effects='KNOWN'
                if not c.claimOutputs(outputs) then failed(c,'MEDICAL_OUTPUT_UNCONFIRMED') return false end
            else
                if owned() or not part:bandaged() or part:getBandageType()~=m.fullType then
                    failed(c,'MEDICAL_EFFECT_UNCONFIRMED') return false
                end
                m.applied=true m.phase='APPLIED' m.effects='KNOWN'
            end
            if not persist() then error('MEDICAL_RECEIPT_FAILED') end
            return result
        end
        action.perform=function(self)
            if performed or stopped or not active() then return end
            performed=true nativePerform(self)
        end
        action.stop=function(self)
            if stopped or not c.body.retained() then return end
            stopped=true m.stopped=true nativeStop(self)
            if M.observe(c,item)~='KNOWN' then failed(c,'MEDICAL_EFFECT_UNCONFIRMED') else persist() end
        end
        if not c.body.add(action) then
            stopped=true m.stopped=true
            if M.observe(c,item)~='KNOWN' then return failed(c,'MEDICAL_EFFECT_UNCONFIRMED') end
            persist() return 'Failure'
        end
        return 'Running'
    end
    function leaf.halt()
        if not c.body.retained() or not c.body.clear() then return false end
        if M.observe(c,item)~='KNOWN' then failed(c,'MEDICAL_EFFECT_UNCONFIRMED') return false end
        return persist()
    end
    return leaf
end
return M
