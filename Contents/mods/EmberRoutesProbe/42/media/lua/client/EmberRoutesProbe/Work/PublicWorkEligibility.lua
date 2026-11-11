-- Worker eligibility for PublicWork (split of PublicWork.lua).
-- Cheap eligibility shared by discovery and precheck admission.
local S=require 'EmberRoutesProbe/Work/PublicWorkState'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Work=require 'EmberRoutesProbe/Work/Work'
local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Providers=require 'EmberRoutesProbe/Work/PublicWorkProviders'

local function eligible(actor,npcId,scope)
    if require('EmberRoutesProbe/Activity/ActivityAttendance').blocksOrdinary(npcId) then return end
    local binding=Driver.bindId(actor,npcId)
    -- A parked carrier keeps its binding but must not receive new work: its
    -- world is gone. Already claimed jobs keep running on their own path.
    if binding and Driver.suspended(binding.handle) then return end
    local probing=Probe.careProbeWork and Probe.careProbeWork(npcId)
    local ToolReturnService=require 'EmberRoutesProbe/Field/ToolReturnService'
    local returningInterruptible=ToolReturnService and ToolReturnService.canInterrupt and ToolReturnService.canInterrupt(npcId)
    if not binding or not binding.handle or (Work.busy(npcId) and not returningInterruptible and not probing)
        or Probe.careBlocksWork and Probe.careBlocksWork(npcId) and not probing then return end
    if Providers.retained(npcId) then return end
    local existing=S.business().crafts()[npcId]
    if existing and not existing.released then return end
    local npc=binding.handle
    if not probing and not returningInterruptible and not npc:getCharacterActions():isEmpty()
        or not require('EmberRoutesProbe/SelfCare/HealthAssessment').canWork(npc) then return end
    S.Members=S.Members or require 'EmberRoutesProbe/Settlement/MembershipService'
    local M=S.Members
    local eligible=M.check(npcId,'WORK',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=scope})
    if not eligible.allowed then return end
    local entry=M.entry(npcId,scope)
    if not entry then return end
    return binding,entry
end

return {eligible=eligible}
