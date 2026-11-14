-- Cross-job tool custody lives in the obligation ledger; claims remain separate.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local View=require 'EmberRoutesProbe/Field/ToolCustodyView'
local C={}
local inInventory
local indexedDoc,byId,byItem,byNpc=nil,{},{},{}
local function store() return require 'EmberRoutesProbe/Work/LaborStore' end
local function index()
    local root=store().data() local doc=root.obligations
    if doc~=indexedDoc then
        local ids,items,npcs={},{},{}
        for id,record in pairs(doc.byId) do
            local view=View.fromRecord(record)
            if view then
                if items[view.itemId]~=nil then items[view.itemId]=false else items[view.itemId]=record end
                ids[id]=record
                npcs[view.npcId]=npcs[view.npcId] or {} npcs[view.npcId][id]=record
            end
        end
        indexedDoc,byId,byItem,byNpc=doc,ids,items,npcs
    end
end
local function record(id) index() return byId[id] end
local function write(op)
    local ok,why,evidence=store().commitCustody(op)
    if not ok then return false,why,evidence end
    return true
end
local function canRetire(record)
    if record.type~='TOOL_CUSTODY' or record.state~='SETTLED' then return false end
    local owner=store().owner(record.data.itemId)
    if owner and owner.taskId==record.id then return false end
    local jobId=record.data.activeJobId
    if jobId then
        local job=require('EmberRoutesProbe/Runtime/TaskJobs').current():peek(jobId)
        if job and (not require('EmberRoutesProbe/Kernel/JobState').isTerminal(job.state) or job.effects~='KNOWN') then return false end
    end
    local runtime=require('EmberRoutesProbe/Runtime/TaskRuntime').current()
    if not runtime then return false end
    if record.data.returnJobId and runtime:status(record.npcId,record.data.returnJobId) then return false end
    local live=require('EmberRoutesProbe/Field/ToolReturnService').liveTask(record.npcId)
    return not live or live.custodyId~=record.id
end
local function pruneSettled(limit)
    local root=store().data() local count=0
    for id,r in pairs(root.obligations.byId) do
        if r.type=='TOOL_CUSTODY' and r.state=='SETTLED' then
            local ok=store().commitCustody({action='RETIRE',id=id,expectedRevision=r.revision},canRetire)
            if ok then count=count+1 if count>=limit then break end end
        end
    end
end
function C.byItem(itemId)
    index()
    if byItem[itemId]==false then return nil,'TOOL_CUSTODY_CONFLICT' end
    return View.fromRecord(byItem[itemId])
end
function C.forNpc(npcId)
    index() local result={}
    for _,r in pairs(byNpc[tostring(npcId)] or {}) do result[#result+1]=View.fromRecord(r) end
    return result
end
function C.all()
    index() local result={}
    for _,r in pairs(byId) do result[#result+1]=View.fromRecord(r) end
    return result
end
function C.canClaim(npcId,itemId)
    local owner=store().owner(itemId)
    local custody,conflict=C.byItem(itemId)
    if conflict or custody and not owner then return false end
    if not owner then return true end
    return custody and custody.npcId==tostring(npcId) and owner.taskId==custody.id
        and (custody.state=='HELD' or custody.state=='RESERVED') or false
end
function C.validUse(npcId,jobId,itemId)
    local owner=store().owner(itemId)
    if not owner then return false end
    if owner.taskId==jobId then return true end
    local custody=C.byItem(itemId)
    return custody and custody.npcId==tostring(npcId) and owner.taskId==custody.id
        and custody.activeJobId==jobId and (custody.state=='HELD' or custody.state=='RESERVED') or false
end
function C.claim(npcId,itemId,role,sourceId,activeJobId,npc,item)
    npcId=tostring(npcId)
    local existing,conflict=C.byItem(itemId)
    if conflict then return nil,conflict end
    if existing then
        local owner=store().owner(itemId)
        if not owner or owner.taskId~=existing.id then return nil,'CUSTODY_CLAIM_MISSING' end
        if existing.npcId~=npcId or (existing.state~='HELD' and existing.state~='RESERVED') then return nil,'TOOL_CUSTODY_UNRESOLVED' end
        if existing.activeJobId and existing.activeJobId~=activeJobId then return nil,'TOOL_ALREADY_ASSIGNED' end
        if activeJobId~=existing.activeJobId then
            local ok,why=C.assignUse(existing.id,activeJobId) if not ok then return nil,why end
        end
        return C.byItem(itemId)
    end
    if sourceId==nil and not inInventory(npc,itemId,item,npcId) then return nil,'INITIAL_INVENTORY_UNPROVEN' end
    local doc=store().data().obligations local total=0
    for _ in pairs(doc.byId) do total=total+1 end
    if total>=4095 then pruneSettled(32) end
    local id='custody:'..npcId..':'..tostring(itemId)..':'..Registry.id()
    local obligation={id=id,type='TOOL_CUSTODY',npcId=npcId,revision=1,state='ACTIVE',
        data={itemId=itemId,role=role,sourceId=sourceId,custodyState='RESERVED',sequence=1,
            claimId=id..':c1',activeJobId=activeJobId,initialInventory=sourceId==nil and true or nil}}
    local ok,why,evidence=write({action='CREATE',id=id,record=obligation})
    if not ok then return nil,why,evidence end
    return C.byItem(itemId)
end
function C.assignUse(id,jobId)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    return write({action='ASSIGN_TOOL',id=id,expectedRevision=r.revision,jobId=jobId})
end
inInventory=function(npc,itemId,item,npcId)
    if not npc or not npc.getInventory then return false end
    local bridge=EmberRoutesProbeJava
    if not bridge or not bridge.carrierId or bridge.carrierId(npc)~=npcId then return false end
    local inventory=npc:getInventory()
    if not inventory or not inventory.getFirstEvalRecurse then return false end
    local found=inventory:getFirstEvalRecurse(function(candidate) return candidate:getID()==itemId end)
    return found~=nil and (not item or found==item)
end
function C.markHeld(id,npc,item)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    if not inInventory(npc,r.data.itemId,item,r.npcId) then return false,'TOOL_HELD_UNPROVEN' end
    if r.data.custodyState=='HELD' and r.state=='ACTIVE' then return true end
    return write({action='TOOL_HELD',id=id,expectedRevision=r.revision,
        evidence={itemId=r.data.itemId,npcId=r.npcId,inInventory=true}})
end
function C.assignReturn(id,returnJobId,intent,npc,item)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    if not inInventory(npc,r.data.itemId,item,r.npcId) then return false,'TOOL_HELD_UNPROVEN' end
    if type(intent)~='table' or intent.jobId~=returnJobId then return false,'RETURN_INTENT_INVALID' end
    local ok,why=write({action='TOOL_RETURN',id=id,expectedRevision=r.revision,intent=intent})
    if not ok then return false,why end
    return true,C.byItem(r.data.itemId)
end
function C.abortReturn(id,returnJobId,npc,item)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    if not inInventory(npc,r.data.itemId,item,r.npcId) then return false,'TOOL_ABORT_UNPROVEN' end
    return write({action='TOOL_ABORT',id=id,expectedRevision=r.revision,returnJobId=returnJobId,
        evidence={itemId=r.data.itemId,npcId=r.npcId,inInventory=true}})
end
function C.reconcile(id,reason)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    return write({action='RECONCILE',id=id,expectedRevision=r.revision,reason=reason})
end
-- Only initial, unchanged custody can be rolled back. A held or missing original
-- is not evidence of a warehouse return.
function C.releaseUncollected(id,npc)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    local d=r.data local destination,initialInventory
    if d.custodyState~='RESERVED' then return false,'TOOL_RETURN_REQUIRED' end
    if d.activeJobId then
        local job=require('EmberRoutesProbe/Runtime/TaskJobs').current():peek(d.activeJobId)
        if not job or job.state~='PREPARING' or job.effects~='KNOWN' then return false,'TOOL_JOB_UNCONFIRMED' end
    end
    if d.sourceId then
        local endpoint=Registry.resolve(d.sourceId,'take','local-world')
        if not endpoint or not endpoint.container or not Registry.revalidate(endpoint,'take','local-world') then return false,'SOURCE_UNAVAILABLE' end
        local items=endpoint.container:getItems() local found=false
        for i=0,items:size()-1 do local item=items:get(i)
            if item:getID()==d.itemId and item:getContainer()==endpoint.container then found=true break end
        end
        if not found then return false,'ORIGINAL_NOT_AT_SOURCE' end
        destination=d.sourceId
    else
        if not npc then
            local bridge=EmberRoutesProbeJava
            local actor=type(getSpecificPlayer)=='function' and getSpecificPlayer(0) or nil
            npc=bridge and bridge.carrierFor and bridge.carrierFor(r.npcId,actor)
        end
        if not inInventory(npc,d.itemId,nil,r.npcId) then return false,'ORIGINAL_NOT_IN_INITIAL_INVENTORY' end
        if d.initialInventory~=true then return false,'INITIAL_INVENTORY_UNPROVEN' end
        destination='npc:'..r.npcId initialInventory=true
    end
    return write({action='SETTLE',id=id,expectedRevision=r.revision,evidence={kind='UNCHANGED',effects='KNOWN',
        itemId=d.itemId,destinationId=destination,originalPresent=true,initialInventory=initialInventory,npcId=r.npcId}})
end
function C.completeReturn(id,returnJobId,destinationId,item)
    local r=record(id) if not r then return false,'CUSTODY_NOT_FOUND' end
    local d=r.data
    if d.returnJobId~=returnJobId or not d.returnIntent or d.returnIntent.destinationId~=destinationId then return false,'RETURN_JOB_MISMATCH' end
    if not item or item:getID()~=d.itemId then return false,'RETURN_ITEM_MISMATCH' end
    local endpoint=Registry.resolve(destinationId,'put','local-world')
    if not endpoint or not endpoint.container or not Registry.revalidate(endpoint,'put','local-world')
        or Registry.logistics(endpoint)~='STORAGE' then return false,'DESTINATION_NOT_RESOLVED' end
    if item:getContainer()~=endpoint.container or not endpoint.container:getItems():contains(item) then return false,'ITEM_NOT_IN_DESTINATION' end
    local ok,why=write({action='SETTLE',id=id,expectedRevision=r.revision,evidence={effects='KNOWN',itemId=d.itemId,
        destinationId=destinationId,destinationKind='STORAGE',originalPresent=true,returnJobId=returnJobId}})
    if ok then Registry.inventoryChanged(endpoint.container) end
    return ok,why
end
function C.retainOnDeath() return 0,'DEAD_CARRIER_OBLIGATION_RETAINED' end
return C
