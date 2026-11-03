-- Persistent roster and furniture policy meet here. Short-lived body/slot claims
-- remain exclusively owned by the existing self-care stop protocol.
local Sites=require 'EmberRoutesProbe/ReposeSites'
local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local B={}
local function clear(row,reason)
    row.bedId=nil row.bedLocation=nil row.bedReason=reason
end
function B.validate(row,entry)
    if not row.bedId then return nil,'BED_NONE' end
    local at=row.bedLocation
    local square=getCell() and getCell():getGridSquare(at.x,at.y,at.z)
    if not square then return nil,'SITE_UNLOADED' end
    local objects=square:getObjects()
    for i=0,objects:size()-1 do
        local object=objects:get(i) local meta=object:getModData().EmberRoutesRepose
        if meta and meta.id==row.bedId then
            local parts,why=Sites.group(object)
            if not parts then return nil,why end
            local p=Sites.policy(parts)
            if not p then return nil,'SITE_CONFLICT' end
            if not entry or not Sites.isBed(object) or p.mode~='ASSIGNED' or p.npcId~=row.npcId then
                return nil,'BED_INVALID'
            end
            for _,part in ipairs(parts) do local s=part:getSquare()
                if not Geometry.inside(entry,s:getX(),s:getY()) then return nil,'BED_INVALID' end
            end
            return object,nil,parts,p
        end
    end
    return nil,'BED_INVALID'
end
function B.reconcile(row,entry)
    if not row.bedId then return end
    local object,why=B.validate(row,entry)
    if object then row.bedReason=nil
    elseif why=='BED_INVALID' then clear(row,'BED_INVALID')
    else row.bedReason=why end -- Unknown/unloaded/conflicting policy is never overwritten.
end
function B.release(row,entry)
    if not row.bedId then return true end
    local object,why,parts,p=B.validate(row,entry)
    if object then Sites.writePolicy(parts,{id=p.id,mode='PUBLIC',revision=p.revision+1})
    elseif why~='BED_INVALID' then row.bedReason=why return false end
    clear(row,'BED_NONE') return true
end
local function attach(row,object,parts,p)
    if p.mode~='ASSIGNED' or p.npcId~=row.npcId then
        Sites.writePolicy(parts,{id=p.id,mode='ASSIGNED',npcId=row.npcId,revision=p.revision+1})
    end
    local s=parts[1]:getSquare()
    row.bedId=parts[1]:getModData().EmberRoutesRepose.id
    row.bedLocation={x=s:getX(),y=s:getY(),z=s:getZ()} row.bedReason=nil
end
-- Called while SETTLE is pending. A finite sweep may span ticks, but missing
-- beds or unloaded chunks never prevent the eventual membership commit.
function B.observe(entry)
    local index=Facilities.watch(entry,Facilities.describe)
    Facilities.advance(index,256)
    if not index.apiUnavailable and (not index.complete or index.frame or index.dirtyCount>0) then
        return false,index
    end
    return true,index
end
function B.settle(row,entry,index)
    local previous=row.bedId
    B.reconcile(row,entry)
    if previous then return true end -- An inconsistent roster is visibly cleared, never silently rerolled.
    local chosen,parts,p
    for _,record in ipairs(index.slots) do
        if record and Sites.isBed(record.object) then
            local group=Sites.group(record.object) local policy=group and Sites.policy(group)
            local inside=group~=nil
            for _,part in ipairs(group or {}) do local s=part:getSquare()
                if not Geometry.inside(entry,s:getX(),s:getY()) then inside=false end
            end
            if inside and policy and (policy.mode=='PUBLIC' or policy.mode=='ASSIGNED' and policy.npcId==row.npcId) then
                -- Adopt the owner's existing assignment before any public bed.
                if not chosen or policy.mode=='ASSIGNED' then chosen,parts,p=record.object,group,policy end
                if policy.mode=='ASSIGNED' then break end
            end
        end
    end
    if chosen then attach(row,chosen,parts,p)
    else row.bedReason=Facilities.pending(index) and Facilities.reason(index) or 'BED_NONE' end
    return true
end
function B.configure(row,entry,object,parts,p,mode)
    if mode=='ASSIGNED' then
        if row.bedId and row.bedId~=p.id and not B.release(row,entry) then return 'BED_RELEASE_BLOCKED' end
        attach(row,object,parts,p)
    else
        Sites.writePolicy(parts,{id=p.id,mode=mode,revision=p.revision+1})
        if row and row.bedId==p.id then clear(row,'BED_CLEARED') end
    end
    return 'SITE_POLICY_SAVED'
end
return B
