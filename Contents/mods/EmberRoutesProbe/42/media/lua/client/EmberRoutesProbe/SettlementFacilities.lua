-- Derived, world-local observations shared by all NPCs in one settlement.
-- Discovery never allocates furniture IDs, reserves resources or owns a body.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Geometry=require 'EmberRoutesProbe/SettlementGeometry'
local Config=require 'EmberRoutesProbe/TickConfig'
local Log=require 'EmberRoutesProbe/Log'
local Index={CHUNK_SIZE=8,LIMIT=2048}
function Index.describe(object)
    if not object.getProperties or not object.getSprite or not object:getSprite() then return nil,0 end
    local props=object:getProperties() local quality=props and props:get('BedType')
    if quality~='goodBed' and quality~='averageBed' and quality~='badBed' then quality=nil end
    local seating=_G.SeatingManager or SeatingManager
    local seats=0
    if seating and seating.getInstance then
        local ok, count = pcall(function() return seating.getInstance():getTilePositionCount(object) end)
        if ok and type(count) == 'number' then seats = count end
    end

    local feature=instanceof and (instanceof(object,'IsoWindow') and 'WINDOW' or instanceof(object,'IsoDoor') and 'DOOR') or nil
    if not feature and ComponentType and ComponentType.CraftBench and object.getComponent
        and object:getComponent(ComponentType.CraftBench) then feature='CRAFT_BENCH' end
    if not feature and object.getFluidCapacity and object:getFluidCapacity()>0 then feature='FLUID_SOURCE' end
    if not feature and object.isGenericCraftingSurface and object:isGenericCraftingSurface() then feature='CRAFT_SURFACE' end
    return quality,seats,feature
end
local world,rows,ordered,cursor,nextTick=nil,{},{},0,0
local function load()
    local root=Registry.data()
    if world~=root then world,rows,ordered,cursor,nextTick=root,{},{},0,0 end
end
local function key(x,y) return x..':'..y end
local function resetSweep(row)
    row.area,row.cx,row.cy,row.seen,row.complete=1,nil,nil,{},false
end
function Index.watch(entry,classify)
    load()
    local row=rows[entry.id]
    if not row or row.revision~=entry.revision then
        if not row and #ordered>=32 then
            local oldest=1
            for i=2,#ordered do
                if rows[ordered[i]].lastUsed<rows[ordered[oldest]].lastUsed then oldest=i end
            end
            rows[ordered[oldest]]=nil table.remove(ordered,oldest) cursor=0
        end
        row={entry=entry,revision=entry.revision,classify=classify,slots={},byObject={},chunks={},free={},
            dirty={},queue={},queueAt=1,dirtyCount=0,unknown=0,limited=0,version=0}
        resetSweep(row)
        if not rows[entry.id] then ordered[#ordered+1]=entry.id end
        rows[entry.id]=row
        nextTick=0
        Log.write('FACILITIES','Watch initialized for settlement='..tostring(entry.id)..' revision='..tostring(entry.revision))
    end
    row.lastUsed=getTimestampMs()
    return row
end
local function commit(row,frame,unloaded,limited)
    local previous=row.chunks[frame.key] or {slots={}}
    if previous.unloaded then row.unknown=row.unknown-1 end
    if previous.limited then row.limited=row.limited-1 end
    for _,slot in ipairs(previous.slots) do
        local record=row.slots[slot]
        if record and not frame.objects[record.object] then
            row.byObject[record.object]=nil row.slots[slot]=false row.free[#row.free+1]=slot
        end
    end
    local bucket={slots={},unloaded=unloaded,limited=limited}
    for _,record in ipairs(frame.found) do
        local slot=row.byObject[record.object]
        if not slot then
            if #row.free>0 then slot=table.remove(row.free)
            elseif #row.slots<Index.LIMIT then slot=#row.slots+1 end
        end
        if slot then
            row.slots[slot]=record row.byObject[record.object]=slot bucket.slots[#bucket.slots+1]=slot
        else bucket.limited=true end
    end
    if #frame.found>0 then
        local seatsFound=0
        for _,rec in ipairs(frame.found) do if rec.seats and rec.seats>0 then seatsFound=seatsFound+1 end end
        if seatsFound>0 then
            Log.write('FACILITIES','Indexed '..tostring(seatsFound)..' seat(s) in chunk '..tostring(frame.key)..' settlement='..tostring(row.entry.id))
        end
    end
    row.chunks[frame.key]=bucket
    if bucket.unloaded then row.unknown=row.unknown+1 end
    if bucket.limited then row.limited=row.limited+1 end
    row.version=row.version+1
end
local function nextChunk(row)
    if row.dirtyCount>0 then
        local value=row.queue[row.queueAt] row.queue[row.queueAt]=false row.queueAt=row.queueAt+1
        row.dirty[value.key]=nil row.dirtyCount=row.dirtyCount-1
        if row.dirtyCount==0 then row.queue={} row.queueAt=1 end
        return value
    end
    if row.complete then
        if getTimestampMs()<row.nextSweep then return end
        resetSweep(row)
    end
    local area=row.entry.areas[row.area]
    if not area then
        if not row.complete then
            local seatCount=0
            for _,slot in pairs(row.slots) do
                if slot and slot.seats and slot.seats>0 then seatCount=seatCount+1 end
            end
            Log.write('FACILITIES','Sweep complete for settlement='..tostring(row.entry.id)..' totalSlots='..tostring(#row.slots)..' seats='..tostring(seatCount))
        end
        row.complete=true row.nextSweep=getTimestampMs()+60000 return
    end
    local size=Index.CHUNK_SIZE
    row.cx=row.cx or math.floor(area.x/size) row.cy=row.cy or math.floor(area.y/size)
    local x,y=row.cx,row.cy
    row.cy=row.cy+1
    if row.cy>math.floor((area.y+area.h-1)/size) then
        row.cy=math.floor(area.y/size) row.cx=row.cx+1
        if row.cx>math.floor((area.x+area.w-1)/size) then row.area=row.area+1 row.cx=nil row.cy=nil end
    end
    local id=key(x,y)
    if row.seen[id] then return false end
    row.seen[id]=true
    return {x=x,y=y,key=id}
end
local function pump(row)
    local cell=getCell()
    if not cell or not cell.getChunkForGridSquare then row.apiUnavailable=true return false end
    row.apiUnavailable=nil
    local frame=row.frame
    if not frame then
        local next=nextChunk(row)
        if next==false then return true end
        if not next then return false end
        local size=Index.CHUNK_SIZE
        frame={key=next.key,x=next.x*size,y=next.y*size,position=0,found={},objects={}}
        frame.chunk=cell:getChunkForGridSquare(frame.x,frame.y,0)
        if not frame.chunk then commit(row,frame,true,false) return true end
        local low,high=frame.chunk:getMinLevel(),frame.chunk:getMaxLevel()
        if type(low)~='number' or type(high)~='number' or low~=math.floor(low) or high~=math.floor(high)
            or high<low or high-low>127 then commit(row,frame,false,true) return true end
        frame.low,frame.high=low,high row.frame=frame
        return true
    end
    -- Recheck loading identity while an incremental scan spans game ticks.
    if cell:getChunkForGridSquare(frame.x,frame.y,0)~=frame.chunk then
        frame.found={} frame.objects={} commit(row,frame,true,false) row.frame=nil return true
    end
    if frame.list then
        if frame.list:size()~=frame.listSize then
            row.frame=nil
            Index.invalidate(frame.x,frame.y)
            return true
        end
        if frame.offset<frame.listSize then
            local object=frame.list:get(frame.offset) frame.offset=frame.offset+1
            local quality,seats,feature=row.classify(object)
            if (quality or seats and seats>0 or feature) and not frame.objects[object] then
                if #frame.found>=256 then frame.limited=true
                else
                    frame.objects[object]=true
                    frame.found[#frame.found+1]={object=object,x=frame.tileX,y=frame.tileY,z=frame.tileZ,quality=quality,seats=seats,feature=feature}
                end
            end
            return true
        end
        frame.list=nil return true
    end
    local size=Index.CHUNK_SIZE local plane=size*size
    if frame.position>=plane*(frame.high-frame.low+1) then
        commit(row,frame,false,frame.limited) row.frame=nil return true
    end
    local n=frame.position frame.position=n+1
    local x,y,z=frame.x+n%size,frame.y+math.floor(n/size)%size,frame.low+math.floor(n/plane)
    if Geometry.inside(row.entry,x,y) then
        local square=cell:getGridSquare(x,y,z)
        if square then
            local objects=square:getObjects()
            if objects:size()>64 then frame.limited=true
            elseif objects:size()>0 then
                frame.list,frame.listSize,frame.offset=objects,objects:size(),0
                frame.tileX,frame.tileY,frame.tileZ=x,y,z
            end
        end
    end
    return true
end
function Index.advance(row,budget)
    local used=0
    for _=1,budget do if not pump(row) then break end used=used+1 end
    return used
end
function Index.due(now) return #ordered>0 and now>=nextTick end
function Index.tick(budget,now)
    if #ordered==0 then return end
    now=now or getTimestampMs()
    if now<nextTick then return end
    load()
    if #ordered==0 then return end
    nextTick=now+Config.facilitiesMs
    local idle=0
    for _=1,budget do
        cursor=cursor%#ordered+1
        local row=rows[ordered[cursor]]
        -- Pump only rows with actual work: a frame in flight, dirty chunks, an
        -- unfinished sweep, or the long-interval resweep deadline. unknown and
        -- limited are reported conditions, not work — chunk loads and object
        -- events push dirty chunks, so they never need blind polling.
        if row and now-row.lastUsed<=60000
            and (row.frame~=nil or row.dirtyCount>0 or not row.complete
                or (row.complete and row.nextSweep and now>=row.nextSweep)) then
            pump(row)
            idle=0
        else idle=idle+1 if idle>=#ordered then break end end
    end
end
function Index.pending(row)
    return not row.complete or row.frame~=nil or row.dirtyCount>0 or row.unknown>0 or row.limited>0 or row.apiUnavailable==true
end
function Index.reason(row)
    if row.apiUnavailable then return 'SITE_API_UNAVAILABLE' end
    if row.unknown>0 then return 'SITE_UNLOADED' end
    if row.limited>0 then return 'SITE_OBSERVATION_LIMIT' end
    return Index.pending(row) and 'SITE_OBSERVING' or 'SITE_UNAVAILABLE'
end
function Index.invalidate(x,y)
    if #ordered==0 then return end
    load()
    local size=Index.CHUNK_SIZE local cx,cy=math.floor(x/size),math.floor(y/size) local id=key(cx,cy)
    for _,row in pairs(rows) do
        -- A chunk corner may lie outside a narrow area. Test chunk overlap,
        -- rather than requiring that corner itself to belong to the settlement.
        if not row.dirty[id] and row.dirtyCount<8192 then
            local inside=false
            for _,area in ipairs(row.entry.areas) do
                if area.x<cx*size+size and area.x+area.w>cx*size and area.y<cy*size+size and area.y+area.h>cy*size then inside=true break end
            end
            if inside then
                row.dirty[id]=true row.queue[#row.queue+1]={x=cx,y=cy,key=id} row.dirtyCount=row.dirtyCount+1
                nextTick=0
            end
        end
    end
end
-- Event-driven invalidation runs OUTSIDE every service bucket; during chunk
-- streaming storms these handlers fire thousands of times per second, so they
-- get their own sampling row to stay attributable. The metrics module is
-- resolved once — a per-event require would itself become the hot path.
local Performance=require 'EmberRoutesProbe/RuntimeMetrics'
local function sampled(handler)
    return function(payload)
        if not Performance.active() then handler(payload) return end
        local started=Performance.now()
        handler(payload)
        Performance.measureSpan('ModEvents',started)
    end
end
local function squareChanged(square)
    if square then Index.invalidate(square:getX(),square:getY()) end
end
local function objectChanged(object)
    if object and object.getSquare then squareChanged(object:getSquare()) end
end
if Events then
    if Events.LoadGridsquares then Events.LoadGridsquares.Add(sampled(squareChanged)) end
    if Events.OnObjectAdded then Events.OnObjectAdded.Add(sampled(objectChanged)) end
    if Events.OnObjectAboutToBeRemoved then Events.OnObjectAboutToBeRemoved.Add(sampled(objectChanged)) end
end
return Index
