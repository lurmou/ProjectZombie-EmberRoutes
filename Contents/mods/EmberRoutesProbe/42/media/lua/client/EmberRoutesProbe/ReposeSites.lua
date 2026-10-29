-- Furniture facts and policies. Candidates are read-only; identity is assigned
-- only by an authorized configuration or a revalidated personal preparation.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Store=require 'EmberRoutesProbe/LaborStore'
local Facilities=require 'EmberRoutesProbe/SettlementFacilities'
local Sites={}
local Seating=_G.SeatingManager
local function hasSeatData(object)
    local sm = Seating or _G.SeatingManager or SeatingManager
    if not sm or not sm.getInstance then return false end
    local ok, count = pcall(function() return sm.getInstance():getTilePositionCount(object) end)
    return ok and type(count) == 'number' and count > 0 or false
end
local modes={PUBLIC=true,ASSIGNED=true,DISABLED=true}
local function live(object)
    local square=object and object.getSquare and object:getSquare()
    return square and getCell() and getCell():getGridSquare(square:getX(),square:getY(),square:getZ())==square
        and square:getObjects():contains(object)
end
local function position(object)
    local s=object:getSquare() return {x=s:getX(),y=s:getY(),z=s:getZ()}
end
local function locationKey(object)
    local p=position(object) return p.x..':'..p.y..':'..p.z
end
function Sites.group(object)
    if not live(object) then return nil,'SITE_UNAVAILABLE' end
    local parts={object}
    if object.hasSpriteGrid and object:hasSpriteGrid() then
        local sprite=object:getSprite() local grid=sprite and sprite:getSpriteGrid()
        if not grid or grid:getSpriteCount()>16 then return nil,'SITE_UNAVAILABLE' end
        local list=ArrayList.new() object:getSpriteGridObjectsIncludingSelf(list)
        if list:size()~=grid:getSpriteCount() then return nil,'SITE_UNLOADED' end
        parts={} for i=0,list:size()-1 do parts[#parts+1]=list:get(i) end
    end
    if #parts>16 then return nil,'SITE_UNAVAILABLE' end
    for _,part in ipairs(parts) do if not live(part) then return nil,'SITE_UNLOADED' end end
    table.sort(parts,function(a,b) return locationKey(a)<locationKey(b) end)
    return parts
end
local function capability(object) return Facilities.describe(object) end

local function policy(parts)
    local first=parts[1]:getModData().EmberRoutesRepose
    if not first then
        for _,part in ipairs(parts) do if part:getModData().EmberRoutesRepose then return nil end end
        return {mode='PUBLIC',revision=0}
    end
    local seen={}
    for _,part in ipairs(parts) do
        local p=part:getModData().EmberRoutesRepose
        if type(p)~='table' or p.format~=1 or type(p.id)~='string' or type(p.partId)~='string'
            or seen[p.partId] or p.id~=first.id or p.revision~=first.revision or p.mode~=first.mode
            or p.npcId~=first.npcId or not modes[p.mode] or type(p.revision)~='number' or p.revision<1
            or p.revision>1e12 or p.revision~=math.floor(p.revision)
            or p.mode=='ASSIGNED' and type(p.npcId)~='string' then return nil end
        seen[p.partId]=true
    end
    return first
end
local function permits(p,npcId)
    return p and (p.mode=='PUBLIC' or p.mode=='ASSIGNED' and p.npcId==npcId)
end
local function entryAt(actor,parts)
    if not Ledger.authorized(actor) then return end
    local p=position(parts[1]) local entries=Ledger.at(p.x,p.y)
    if #entries~=1 then return end
    local entry=entries[1]
    for _,part in ipairs(parts) do
        local at=position(part) if not Geometry.inside(entry,at.x,at.y) then return end
    end
    return entry
end
local function entryForNpc(npcId,parts,scope)
    local entry=require('EmberRoutesProbe/MembershipService').entry(npcId,scope)
    if not entry then return end
    for _,part in ipairs(parts) do local p=position(part) if not Geometry.inside(entry,p.x,p.y) then return end end
    return entry
end
function Sites.view(actor,object)
    local parts,why=Sites.group(object) if not parts then return nil,why end
    local quality,seats=capability(object)
    if not quality and seats<1 then return nil,'SITE_UNAVAILABLE' end
    if not entryAt(actor,parts) then return nil,'ACCESS_DENIED' end
    local p=policy(parts) if not p then return nil,'SITE_CONFLICT' end
    return {mode=p.mode,npcId=p.npcId,revision=p.revision,id=p.id}
end
local function register(parts,p)
    local id=p.id or Registry.id()
    for _,part in ipairs(parts) do
        local old=part:getModData().EmberRoutesRepose
        part:getModData().EmberRoutesRepose={format=1,id=id,partId=old and old.partId or Registry.id(),
            mode=p.mode,npcId=p.npcId,revision=math.max(1,p.revision)}
    end
end
function Sites.configure(actor,object,revision,mode,npcId)
    local current,why=Sites.view(actor,object) if not current then return why end
    local p=position(object)
    if actor:getZ()~=p.z or (actor:getX()-p.x-0.5)^2+(actor:getY()-p.y-0.5)^2>16 then return 'SITE_TOO_FAR' end
    if current.revision~=revision then return 'SITE_CHANGED' end
    if not modes[mode] then return 'SITE_POLICY_INVALID' end
    if mode=='ASSIGNED' and (type(npcId)~='string' or not require('EmberRoutesProbe/Driver').bindId(actor,npcId)) then
        return 'SITE_NPC_UNAVAILABLE'
    end
    if mode~='ASSIGNED' then npcId=nil end
    if current.mode==mode and current.npcId==npcId and current.revision>0 then return 'SITE_POLICY_SAVED' end
    local parts=Sites.group(object)
    register(parts,{id=current.id,mode=mode,npcId=npcId,revision=current.revision+1})
    require('EmberRoutesProbe/LaborSignals').changed()
    return 'SITE_POLICY_SAVED'
end
local function occupied(parts,target,npc,kind,owner)
    local player=getSpecificPlayer(0)
    local playerBed=player and player~=npc and player.getBed and player:getBed()
    if playerBed and player.isAsleep and player:isAsleep() then
        for _,part in ipairs(parts) do if playerBed==part then return true end end
    end
    for _,part in ipairs(parts) do if kind=='SLEEP' or part==target then
        -- Vanilla isFurnitureOccupied checks sitting Idle only. Sleeping players
        -- may stand adjacent to the bed and require their actual bed reference.
        if not part.isFurnitureOccupied or part:isFurnitureOccupied(npc) then return true end
        if playerBed==part then return true end
        local p=part:getModData().EmberRoutesRepose
        local claim=p and Store.resourceOwner('repose:'..p.id..':'..p.partId)
        if claim and claim.taskId~=owner or owner and not claim then return true end
    end end
    return false
end
function Sites.keys(proof,kind)
    local result={}
    for _,p in ipairs(proof.parts) do
        if kind=='SLEEP' or p.id==proof.partId then result[#result+1]='repose:'..proof.id..':'..p.id end
    end
    return result
end
Sites.validProof=require('EmberRoutesProbe/ReposeRecord').valid
function Sites.resolve(proof,actor,npc,npcId,kind,owner)
    if not Sites.validProof(proof) then return nil,'SITE_CONFLICT' end
    local parts,target={},nil
    for _,p in ipairs(proof.parts) do
        local square=getCell() and getCell():getGridSquare(p.x,p.y,p.z)
        if not square then return nil,'SITE_UNLOADED' end
        local found local objects=square:getObjects()
        if objects:size()>64 then return nil,'SITE_UNAVAILABLE' end
        for i=0,objects:size()-1 do
            local object=objects:get(i) local m=object:getModData().EmberRoutesRepose
            if m and m.id==proof.id and m.partId==p.id then if found then return nil,'SITE_CONFLICT' end found=object end
        end
        if not found then return nil,'SITE_UNAVAILABLE' end
        parts[#parts+1]=found if p.id==proof.partId then target=found end
    end
    local group=target and Sites.group(target)
    if not group or #group~=#parts then return nil,'SITE_CHANGED' end
    for _,part in ipairs(group) do
        local found=false for _,saved in ipairs(parts) do if saved==part then found=true break end end
        if not found then return nil,'SITE_CHANGED' end
    end
    local p=policy(parts)
    if not p or p.revision~=proof.revision or not permits(p,npcId) then return nil,'SITE_CHANGED' end
    local entry=entryForNpc(npcId,parts,proof.settlementId)
    if not entry or not Geometry.inside(entry,npc:getX(),npc:getY()) then return nil,'ACCESS_DENIED' end
    local quality,seats=capability(target)
    if kind=='SLEEP' and not quality or kind=='REST' and not quality and seats<1 then return nil,'SITE_CHANGED' end
    if occupied(parts,target,npc,kind,owner) then return nil,'SITE_OCCUPIED' end
    return {object=target,parts=parts,quality=quality or 'averageBed'}
end
function Sites.prepare(candidate,actor,npc,npcId,kind)
    local at=live(candidate.object) and position(candidate.object)
    if not at then return nil,'SITE_CHANGED' end
    local parts=Sites.group(candidate.object)
    local p=parts and policy(parts)
    local entry=parts and entryForNpc(npcId,parts,candidate.settlementId)
    if not p or not permits(p,npcId) or p.revision~=candidate.revision or not entry
        or candidate.settlementId and candidate.settlementId~=entry.id
        or not Geometry.inside(entry,npc:getX(),npc:getY())
        or occupied(parts,candidate.object,npc,kind) then return nil,'SITE_CHANGED' end
    register(parts,p)
    local meta=candidate.object:getModData().EmberRoutesRepose
    local proof={id=meta.id,partId=meta.partId,revision=meta.revision,parts={},key=candidate.key,settlementId=entry.id}
    for _,part in ipairs(parts) do local at=position(part) at.id=part:getModData().EmberRoutesRepose.partId proof.parts[#proof.parts+1]=at end
    local resolved,why=Sites.resolve(proof,actor,npc,npcId,kind)
    return resolved and proof or nil,why
end
function Sites.new(actor,npc,npcId,kind,blocked,options)
    -- Freeze exclusions for this scan: budgeted discovery may outlive the
    -- cooldown and must still try an alternative to the failed approach.
    local excluded={} local started=getTimestampMs()
    for key,untilTime in pairs(blocked or {}) do if untilTime>started then excluded[key]=true end end
    local M=require 'EmberRoutesProbe/MembershipService'
    local entry=M.entry(npcId)
    local entryRevision=entry and entry.revision
    local member=M.view(npcId) local revision=member and member.revision
    local index,best=1,nil
    local self={}
    -- Optional consumers with a discovery deadline may use an already observed
    -- valid candidate without asserting that the remaining area has no seats.
    function self:knownBest() return best and live(best.object) and best or nil end
    function self:step(budget)
        if not entry or not M.check(npcId,'SELF_CARE',{x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=entry.id},revision).sharedResources then
            return nil,true,'SETTLEMENT_REQUIRED'
        end
        local current=M.entry(npcId)
        if not current or current.id~=entry.id or current.revision~=entryRevision then
            return nil,true,'SITE_CHANGED'
        end
        local row=Facilities.watch(entry,capability)
        local used=Facilities.advance(row,math.floor(budget/2))
        for _=used+1,budget do
            local record=row.slots[index] index=index+1
            if record==nil then
                local chosen=best index,best=1,nil
                if chosen and live(chosen.object) then return chosen,true end
                if Facilities.pending(row) then return nil,false,Facilities.reason(row) end
                return nil,true,'SITE_UNAVAILABLE'
            elseif record then
                local object=record.object
                if live(object) then
                    local quality,seats=record.quality,record.seats
                    if quality or kind=='REST' and seats>0 then
                        local parts=Sites.group(object) local p=parts and policy(parts)
                        local key=parts and locationKey(parts[1])..':'..locationKey(object)..':'..kind
                        if key then
                            local scope=entryForNpc(npcId,parts,entry.id)
                            local distance=(record.x+0.5-npc:getX())^2+(record.y+0.5-npc:getY())^2+(record.z-npc:getZ())^2*4
                            local within=not options or (not options.maxDistance or distance<=options.maxDistance^2)
                                and (not options.sameFloor or record.z==math.floor(npc:getZ()))
                                and (not options.seatingOnly or hasSeatData(object))
                                and (not options.excludeBeds or not object:getProperties():has(IsoFlagType.bed))
                            if within and scope and scope.id==entry.id and permits(p,npcId)
                                and not excluded[key]
                                and not occupied(parts,object,npc,kind) then
                                local qualityScore=kind=='SLEEP' and ({goodBed=3,averageBed=2,badBed=1})[quality] or 0
                                if kind=='SLEEP' then
                                    qualityScore=qualityScore+(object:getProperties():has(IsoFlagType.bed) and 20 or #parts>1 and 10 or 0)
                                end
                                local assigned=p.mode=='ASSIGNED' and 1 or 0
                                local preferred=options and options.preferredPoint
                                local preference=preferred and record.x==preferred.x and record.y==preferred.y and record.z==preferred.z and 1 or 0
                                if not best or assigned>best.assigned or assigned==best.assigned and
                                    (preference>(best.preference or 0) or preference==(best.preference or 0) and
                                    (qualityScore>best.quality or qualityScore==best.quality and distance<best.distance)) then
                                    best={object=object,revision=p.revision,key=key,settlementId=entry.id,
                                        assigned=assigned,preference=preference,quality=qualityScore,distance=distance}
                                end
                            end
                        end
                    end
                else Facilities.invalidate(record.x,record.y) end
            end
        end
        -- Remaining indexed candidates still need a bounded comparison even
        -- when an unrelated chunk is unloaded or observation-limited.
        return nil,false,'SITE_OBSERVING'
    end
    return self
end
return Sites
