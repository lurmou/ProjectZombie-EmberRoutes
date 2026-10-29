-- Durable demand/public offers. Bodies and originals belong to TaskRuntime/LaborStore.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Members=require 'EmberRoutesProbe/MembershipService'
local Store=require 'EmberRoutesProbe/LaborStore'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Service={}
local nextRecovery=0
local scanWorld,scans,discoveryCursor,recoveryCursor=nil,{},{},0
local function integer(n,min,max)
    return type(n)=='number' and n==n and n==math.floor(n) and n>=min and n<=max
end
local function validate(value)
    if type(value)~='table' or value.format~=1 or type(value.orders)~='table' then error('DELIVERY_FORMAT_UNSUPPORTED') end
    local count,jobs=0,{}
    local states={WAITING=true,ASSIGNED=true,DONE=true,CANCELLED=true,RECONCILE_REQUIRED=true}
    for id,o in pairs(value.orders) do
        count=count+1
        if count>128 or type(o)~='table' or type(id)~='string' or o.id~=id or o.format~=1
            or type(o.requesterId)~='string' or type(o.settlementId)~='string' or not states[o.state]
            or not integer(o.revision,1,9007199254740990) or type(o.items)~='table' or #o.items<1 or #o.items>256
            or (o.jobId~=nil and (type(o.jobId)~='string' or type(o.npcId)~='string' or jobs[o.jobId]))
            or (o.jobId==nil and o.npcId~=nil) then error('DELIVERY_ORDER_INVALID') end
        if o.jobId then jobs[o.jobId]=true end
        local seen,total={},0
        for _,l in ipairs(o.items) do
            local key=l.sourceId and (l.fullType..':'..l.sourceId) or l.fullType
            if type(l)~='table' or type(l.fullType)~='string' or #l.fullType<1 or #l.fullType>256 or seen[key]
                or (l.sourceId~=nil and (type(l.sourceId)~='string' or #l.sourceId<1 or #l.sourceId>256))
                or not integer(l.quantity,1,9999) or not integer(l.delivered,0,l.quantity) then error('DELIVERY_ORDER_INVALID') end
            seen[key]=true total=total+l.quantity
        end
        if total>9999 then error('DELIVERY_ORDER_INVALID') end
    end
end
local function data()
    local root=Registry.data()
    root.deliveryOrders=root.deliveryOrders or {format=1,orders={}}
    if root~=scanWorld then
        validate(root.deliveryOrders)
        scanWorld,scans,discoveryCursor,recoveryCursor=root,{},{},0
        nextRecovery=0
    end
    return root.deliveryOrders
end
function Service.data() return data() end
function Service.distanceToSettlement(entry,x,y)
    if not entry or not entry.areas or #entry.areas==0 then return math.huge end
    local best=math.huge
    for _,r in ipairs(entry.areas) do
        local dx=math.max(r.x-x,0,x-(r.x+r.w-1))
        local dy=math.max(r.y-y,0,y-(r.y+r.h-1))
        best=math.min(best,math.sqrt(dx*dx+dy*dy))
    end
    return best
end
function Service.actor(order,actor)
    return actor and not actor:isDead() and Members.character(actor)==order.requesterId and actor or nil
end
function Service.createOrder(actor,scope,items,requestId)
    local entry,why=Ledger.view(actor,scope)
    if not entry then return why end
    if type(items)~='table' or #items<1 or #items>256 then return 'ITEMS_REQUIRED' end
    if requestId~=nil and (type(requestId)~='string' or #requestId<1 or #requestId>128) then return 'INVALID_REQUEST' end
    local requests,seen,total={},{},0
    for _,line in ipairs(items) do
        local q=line.quantity
        local key=line.sourceId and (line.fullType..':'..line.sourceId) or line.fullType
        if type(line.fullType)~='string' or #line.fullType<1 or #line.fullType>256 or seen[key]
            or (line.sourceId~=nil and (type(line.sourceId)~='string' or #line.sourceId<1 or #line.sourceId>256))
            or type(q)~='number' or q~=q or q<1 or q>9999 or q~=math.floor(q) then return 'INVALID_REQUEST' end
        seen[key]=true total=total+q
        requests[#requests+1]={fullType=line.fullType,quantity=q,delivered=0,sourceId=line.sourceId}
    end
    if total>9999 then return 'INVALID_REQUEST' end
    table.sort(requests,function(a,b)
        local ka=a.sourceId and (a.fullType..':'..a.sourceId) or a.fullType
        local kb=b.sourceId and (b.fullType..':'..b.sourceId) or b.fullType
        return ka<kb
    end)
    local requester=Members.character(actor) if not requester then return 'ACTOR_UNAVAILABLE' end
    local count,oldest=0,nil
    for _,o in pairs(data().orders) do
        count=count+1
        if not o.jobId and (o.state=='DONE' or o.state=='CANCELLED')
            and (not oldest or (o.createdAt or 0)<(oldest.createdAt or 0)) then oldest=o end
        if requestId and o.requestId==requestId then
            local same=o.requesterId==requester and o.settlementId==scope and #o.items==#requests
            for i,l in ipairs(requests) do
                local old=o.items[i] same=same and old and old.fullType==l.fullType and old.quantity==l.quantity and old.sourceId==l.sourceId
            end
            return same and 'ORDER_CREATED' or 'REQUEST_CHANGED',same and o.id or nil
        end
    end
    if count>=128 then
        if not oldest then return 'ORDER_LIMIT' end
        data().orders[oldest.id]=nil scans={}
    end
    local id=Registry.id()
    data().orders[id]={id=id,format=1,revision=1,settlementId=scope,requesterId=requester,
        requestId=requestId,items=requests,state='WAITING',reason='WAITING_WORKER',createdAt=getTimestampMs()}
    Signals.changed()
    return 'ORDER_CREATED',id
end
function Service.order(id) return data().orders[id] end
function Service.cancel(actor,id,revision)
    local o=Service.order(id)
    if not o or not Service.actor(o,actor) or o.revision~=revision then return 'ORDER_CHANGED' end
    o.cancelled=true o.revision=o.revision+1
    scans={}
    if not o.jobId then o.state='CANCELLED' end
    Signals.changed(o.npcId) return 'CANCEL_REQUESTED'
end
local function outstanding(o)
    for _,l in ipairs(o.items) do if l.delivered<l.quantity then return true end end
    return false
end
-- One source and <=30 originals per segment, within remaining carry. No asset writes.
local function batch(o,env)
    local ids=require('EmberRoutesProbe/SettlementMembership').query(env.entry)
    if not ids then return end
    local Producers=require 'EmberRoutesProbe/LaborProducers'
    local free=Producers.freeCarry(env.npc)
    local key=env.npcId..':'..o.id
    local state=scans[key] or {source=1,offset=0}
    scans[key]=state
    local scanned=0
    while state.source<=#ids do
        local id=ids[state.source]
        local e=Registry.resolve(id,'take','local-world')
        if e and Registry.logistics(e)=='STORAGE' then
            local picks,types,used,counts={},{},0,{}
            local list=e.container:getItems()
            local i=state.offset
            while i<list:size() and scanned<256 do
                local item=list:get(i) i=i+1 scanned=scanned+1
                for _,l in ipairs(o.items) do
                    local reqKey=l.sourceId and (l.fullType..':'..l.sourceId) or l.fullType
                    if (not l.sourceId or l.sourceId==id)
                        and item:getFullType()==l.fullType and (counts[reqKey] or 0)<l.quantity-l.delivered
                        and not Store.owner(item:getID()) and Producers.eligible(item) then
                        local weight=item:getUnequippedWeight()
                        if weight>env.npc:getMaxWeight() then state.overweight=true
                        elseif weight<=free-used and env.npc:getInventory():hasRoomFor(env.npc,item) then
                            picks[#picks+1]=item:getID() types[tostring(item:getID())]=l.fullType
                            counts[reqKey]=(counts[reqKey] or 0)+1 used=used+weight
                        end
                        break
                    end
                end
                if #picks==30 then break end
            end
            state.offset=i
            if #picks>0 then
                scans[key]=nil
                return {producer='DELIVERY',source=id,destination='player:'..o.requesterId,
                    settlementId=o.settlementId,sourceMode='STORAGE',items=picks,itemTypes=types,
                    orderId=o.id,orderRevision=o.revision,requesterId=o.requesterId}
            end
            if i<list:size() then return nil,'STOCK_OBSERVING' end
        end
        state.source,state.offset=state.source+1,0
        if scanned>=256 then return nil,'STOCK_OBSERVING' end
    end
    scans[key]=nil
    return nil,state.overweight and 'NPC_ITEM_OVERWEIGHT' or 'STOCK_OR_CAPACITY_WAIT' 
end
function Service.discover(env)
    local ids={}
    for id,o in pairs(data().orders) do
        if o.state=='WAITING' and not o.cancelled and not o.jobId and o.settlementId==env.entry.id then ids[#ids+1]=id end
    end
    table.sort(ids)
    if #ids==0 then return end
    local cursor=discoveryCursor[env.npcId] or 0
    cursor=cursor%#ids+1 discoveryCursor[env.npcId]=cursor
    local o=data().orders[ids[cursor]]
    if not Service.actor(o,env.actor) then return end
    local intent,reason=batch(o,env)
    if intent then
        local key='delivery:'..o.id
        local offer=env.upsertOffer(key,o.revision,'hauling',o.settlementId)
        if offer and not offer.jobId then env.candidates[#env.candidates+1]={key=key,revision=o.revision,
            category='hauling',allowed=true,score=0,intent=intent,delivery=true} end
    elseif o.reason~=reason then o.reason=reason Signals.changed() end
end
function Service.claim(selected,npcId,jobId,env)
    local intent=selected.intent local o=Service.order(intent.orderId)
    if not o or o.jobId or o.cancelled or o.revision~=intent.orderRevision or not Service.actor(o,env.actor) then return 'ORDER_CHANGED' end
    o.jobId,o.npcId,o.state=jobId,npcId,'ASSIGNED'
    intent.jobId=jobId
    local Work=require 'EmberRoutesProbe/Work'
    Work.allowAutomation(npcId)
    local result=Work.assign(env.actor,npcId,intent)
    if result~='QUEUED' and result~='STARTED' then o.jobId,o.npcId,o.state=nil,nil,'WAITING' end
    return result
end
-- Existing public coordinator advances retained responsibility; never selects a worker.
function Service.advance(env)
    if env.now<nextRecovery then return end nextRecovery=env.now+1000
    local Work=require 'EmberRoutesProbe/Work'
    local runtime=require('EmberRoutesProbe/TaskRuntime').current()
    local Business=require 'EmberRoutesProbe/BusinessJobs'
    local ids={}
    for id,o in pairs(data().orders) do if o.jobId then ids[#ids+1]=id end end
    table.sort(ids)
    for _=1,math.min(8,#ids) do
        recoveryCursor=recoveryCursor%#ids+1
        local o=data().orders[ids[recoveryCursor]]
        if o.jobId then
            local r=Business.record(o.jobId,'HAUL')
            if r and r.producer=='DELIVERY' then
                if r.state=='DONE' and not runtime:status(o.npcId,o.jobId) then
                    for _,l in ipairs(r.manifest) do
                        if l.deliveryReceipt and l.deliveryReceipt.destinationId=='player:'..o.requesterId then
                            for _,request in ipairs(o.items) do
                                if request.fullType==r.itemTypes[tostring(l.itemId)]
                                    and (not request.sourceId or request.sourceId==r.source)
                                    and request.delivered<request.quantity then
                                    request.delivered=request.delivered+1
                                    break
                                end
                            end
                        end
                    end
                    env.directory:release('delivery:'..o.id,o.jobId,{effects='KNOWN',obligationsCleared=true})
                    o.jobId,o.npcId=nil,nil o.revision=o.revision+1
                    o.cancelled=o.cancelled or r.returning
                    o.state=o.cancelled and 'CANCELLED' or outstanding(o) and 'WAITING' or 'DONE'
                    Signals.changed()
                elseif r.state=='PAUSED' and not r.controlUncertain and not r.activeAttempt and not r.manualPaused
                    and r.reason~='SELF_CARE' and not Work.busy(o.npcId)
                    and not (require('EmberRoutesProbe/Boot').careBlocksWork and require('EmberRoutesProbe/Boot').careBlocksWork(o.npcId)) then
                    Work.resumeFor(env.actor,o.npcId)
                end
                local reason=o.jobId and r.reason or o.state=='WAITING' and 'WAITING_WORKER' or o.state
                if o.reason~=reason or o.phase~=r.phase then
                    o.reason,o.phase=reason,r.phase Signals.changed(o.npcId)
                end
            elseif not r and not runtime:status(o.npcId,o.jobId) then
                o.state='RECONCILE_REQUIRED' o.reason='DELIVERY_JOB_MISSING'
            end
        end
    end
end
function Service.hasWork()
    for _,o in pairs(data().orders) do if o.jobId then return true end end return false
end
function Service.reset() nextRecovery=0 scanWorld,scans,discoveryCursor,recoveryCursor=nil,{},{},0 end
require('EmberRoutesProbe/Boot').resetDelivery=Service.reset
require('EmberRoutesProbe/Boot').tickDelivery=nil
return Service
