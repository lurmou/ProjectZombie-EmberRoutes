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
            or (o.destinationId~=nil and (type(o.destinationId)~='string' or #o.destinationId<1 or #o.destinationId>256))
            or type(o.requesterId)~='string' or type(o.settlementId)~='string' or not states[o.state]
            or (o.overlapSequence~=nil and not integer(o.overlapSequence,1,1e12))
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
-- UI consumes detached registered endpoints, never Registry roots or Java bridges.
function Service.containers(actor,scope,mode)
    local entry=Ledger.view(actor,scope) local result={}
    if not entry then return result end
    for _,id in ipairs(require('EmberRoutesProbe/SettlementMembership').query(entry) or {}) do
        local e=Registry.resolve(id,mode,'local-world')
        local p=e and Registry.describe(id)
        if p and (mode=='put' or Registry.logistics(e)=='INPUT' or Registry.logistics(e)=='STORAGE') then
            result[#result+1]={id=id,x=p.x,y=p.y,z=p.z}
        end
    end
    table.sort(result,function(a,b) return a.id<b.id end)
    return result
end
local function destinationCheck(entry,items,destinationId,actor)
    if destinationId==nil then return end
    local target=Registry.resolve(destinationId,'put','local-world')
    local p=target and Registry.describe(destinationId)
    if not p or not require('EmberRoutesProbe/SettlementGeometry').inside(entry,p.x,p.y) then return 'DESTINATION_UNREGISTERED' end
    local used=0
    local ids=require('EmberRoutesProbe/SettlementMembership').query(entry) or {}
    for _,line in ipairs(items) do
        local remaining=line.quantity
        for _,id in ipairs(ids) do
            if id~=destinationId and (not line.sourceId or line.sourceId==id) then
                local e=Registry.resolve(id,'take','local-world')
                if e and (Registry.logistics(e)=='STORAGE' or line.sourceId and Registry.logistics(e)=='INPUT') then
                    local list=e.container:getItems()
                    for i=0,list:size()-1 do
                        local item=list:get(i)
                        if remaining>0 and item:getFullType()==line.fullType then
                            if not Registry.accepts(target,item) then return 'DESTINATION_FILTER_REJECTED' end
                            used=used+item:getUnequippedWeight() remaining=remaining-1
                            if not target.container:hasRoomFor(actor,item) or used>target.container:getFreeCapacity(actor) then return 'DESTINATION_FULL' end
                        end
                    end
                end
            end
        end
    end
end
function Service.createOrder(actor,scope,items,requestId,destinationId)
    local entry,why=Ledger.view(actor,scope)
    if not entry then return why end
    if destinationId~=nil then
        if type(destinationId)~='string' or #destinationId<1 or #destinationId>256 then return 'INVALID_REQUEST' end
        local target=Registry.resolve(destinationId,'put','local-world')
        local position=target and Registry.describe(destinationId)
        if not target or not position or not require('EmberRoutesProbe/SettlementGeometry').inside(entry,position.x,position.y) then return 'DESTINATION_UNREGISTERED' end
    end
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
            local same=o.requesterId==requester and o.settlementId==scope and o.destinationId==destinationId and #o.items==#requests
            for i,l in ipairs(requests) do
                local old=o.items[i] same=same and old and old.fullType==l.fullType and old.quantity==l.quantity and old.sourceId==l.sourceId
            end
            if same then return 'ORDER_CREATED',o.id end
        end
    end
    for _,line in ipairs(requests) do
        if line.sourceId then
            local source=Registry.resolve(line.sourceId,'take','local-world')
            local pos=source and Registry.describe(line.sourceId)
            if not source or not pos or not require('EmberRoutesProbe/SettlementGeometry').inside(entry,pos.x,pos.y)
                or (Registry.logistics(source)~='INPUT' and Registry.logistics(source)~='STORAGE') then return 'SOURCE_UNAVAILABLE' end
            if line.sourceId==destinationId then return 'INVALID_REQUEST' end
        end
    end
    local blocked=destinationCheck(entry,requests,destinationId,actor)
    if blocked then return blocked end
    if count>=128 then
        if not oldest then return 'ORDER_LIMIT' end
        data().orders[oldest.id]=nil scans={}
    end
    local id=Registry.id()
    data().orders[id]={id=id,format=1,revision=1,settlementId=scope,requesterId=requester,
        requestId=requestId,destinationId=destinationId,overlapSequence=require('EmberRoutesProbe/PublicWork').nextDemandSequence(),items=requests,state='WAITING',reason='WAITING_WORKER',createdAt=getTimestampMs()}
    Signals.changed()
    return 'ORDER_CREATED',id
end
function Service.order(id) return data().orders[id] end
function Service.cancel(actor,id,revision)
    local o=Service.order(id)
    if not o or not Service.actor(o,actor) or o.revision~=revision then return 'ORDER_CHANGED' end
    o.cancelled=true o.revision=o.revision+1
    scans={}
    o.state='CANCELLED'
    -- Stop through the existing owner; retained originals and manifest are not settled.
    if o.jobId then require('EmberRoutesProbe/Work').pause('USER',o.npcId) end
    Signals.changed(o.npcId) return 'CANCEL_REQUESTED'
end
local function outstanding(o)
    for _,l in ipairs(o.items) do if l.delivered<l.quantity then return true end end
    return false
end
-- A single bounded manifest spans source containers; observation slices do not
-- become delivery trips. Only the Job/Claims layer owns selected originals.
local function batch(o,env)
    local overlap=require('EmberRoutesProbe/PublicWork').deliveryOverlapReason
    local suppressed={} local suppression='' local hasSuppressed=false
    for i,line in ipairs(o.items) do
        suppressed[i]=overlap and overlap(o,line) or nil
        suppression=suppression..':'..(suppressed[i] or '')
        hasSuppressed=hasSuppressed or suppressed[i]~=nil
    end
    for i,line in ipairs(o.items) do line.reason=suppressed[i] end
    local target
    if o.destinationId then
        target=Registry.resolve(o.destinationId,'put','local-world')
        local pos=target and Registry.describe(o.destinationId)
        if not target or not pos or not require('EmberRoutesProbe/SettlementGeometry').inside(env.entry,pos.x,pos.y) then return nil,'DESTINATION_UNREGISTERED' end
    end
    local ids=require('EmberRoutesProbe/SettlementMembership').query(env.entry)
    if not ids then return end
    local Producers=require 'EmberRoutesProbe/LaborProducers'
    local free=Producers.freeCarry(env.npc)
    local key=env.npcId..':'..o.id
    local state=scans[key]
    local same=state and state.revision==o.revision and state.suppression==suppression and state.free==free and #state.ids==#ids
    if same then for i,id in ipairs(ids) do if state.ids[i]~=id then same=false break end end end
    if not same then
	local sources={} for i,id in ipairs(ids) do sources[i]=id end
	state={ids=sources,revision=o.revision,suppression=suppression,free=free,source=1,offset=0,
	    picks={},types={},origins={},used=0,counts={},seen={}}
	scans[key]=state
    end
    local scanned=0
    while state.source<=#ids and #state.picks<256 do
        local id=ids[state.source]
        local e=Registry.resolve(id,'take','local-world')
        local explicit=false for _,line in ipairs(o.items) do if line.sourceId==id then explicit=true break end end
        if e and (Registry.logistics(e)=='STORAGE' or explicit and Registry.logistics(e)=='INPUT') and id~=o.destinationId then
	    local list=e.container:getItems() local i=state.offset
	    if not target and Registry.logistics(e)=='STORAGE' and not hasSuppressed and EmberRoutesProbeJava and EmberRoutesProbeJava.deliverySelectSlice then
		while scanned<256 and #state.picks<256 do
		    local result=EmberRoutesProbeJava.deliverySelectSlice(e.container,env.npc,id,o.items,
			Store.claimsInstance().owners,state,256-scanned)
		    scanned=scanned+result.scanned i=state.offset
		    if not result.virtualItem then break end
		    -- Only mod-defined virtual ModData reads need a Lua decision.
		    state.virtualEligibility[result.virtualItem:getID()]=not not Producers.eligible(result.virtualItem)
		end
	    else
	    while i<list:size() and scanned<256 and #state.picks<256 do
                local item=list:get(i) i=i+1 scanned=scanned+1
		local match
		-- A source-specific line gets first use of that source's stock.
		-- General lines consume remaining stock, never count an original twice.
		for pass=1,2 do
		    for n,l in ipairs(o.items) do
			if not suppressed[n] and (pass==1 and l.sourceId==id or pass==2 and not l.sourceId and Registry.logistics(e)=='STORAGE')
			    and item:getFullType()==l.fullType
			    and (state.counts[n] or 0)<l.quantity-l.delivered then match=n break end
		    end
		    if match then break end
		end
		local itemId=item:getID()
		if match and not state.seen[itemId] and not Store.owner(itemId) and Producers.eligible(item) then
		    if target then
                        if not Registry.accepts(target,item) then scans[key]=nil return nil,'DESTINATION_FILTER_REJECTED' end
                        if not target.container:hasRoomFor(env.npc,item) or target.container:getFreeCapacity(env.npc)<item:getUnequippedWeight()+state.used then scans[key]=nil return nil,'DESTINATION_FULL' end
                    end
                    local weight=item:getUnequippedWeight()
		    if weight>env.npc:getMaxWeight() then state.overweight=true
		    elseif weight<=free-state.used and env.npc:getInventory():hasRoomFor(env.npc,item) then
			state.picks[#state.picks+1]=itemId state.types[tostring(itemId)]=item:getFullType()
			state.origins[tostring(itemId)]=id state.used=state.used+weight
			state.counts[match]=(state.counts[match] or 0)+1 state.seen[itemId]=true
                    end
                end
            end
            end
	    state.offset=i
	    if i<list:size() and #state.picks<256 then return nil,'STOCK_OBSERVING' end
        end
        state.source,state.offset=state.source+1,0
	if scanned>=256 and state.source<=#ids and #state.picks<256 then return nil,'STOCK_OBSERVING' end
    end
    scans[key]=nil
    if #state.picks>0 then
	return {producer='DELIVERY',source=state.origins[tostring(state.picks[1])],destination=o.destinationId or 'player:'..o.requesterId,
	    settlementId=o.settlementId,sourceMode='STORAGE',items=state.picks,itemTypes=state.types,itemSources=state.origins,
	    orderId=o.id,orderRevision=o.revision,requesterId=o.requesterId}
    end
    for _,reason in pairs(suppressed) do return nil,reason end
    return nil,state.overweight and 'NPC_ITEM_OVERWEIGHT' or 'STOCK_OR_CAPACITY_WAIT'
end
-- Pure projection shared by execution and terminal order settlement. A receipt
-- credits exactly one request; source-specific demand precedes general demand.
function Service.projectDelivery(o,r)
    if not o.destinationId and EmberRoutesProbeJava and EmberRoutesProbeJava.deliveryReceived then return EmberRoutesProbeJava.deliveryReceived(o,r) end
    local counts={} for i,l in ipairs(o.items) do counts[i]=l.delivered end
    for _,line in ipairs(r.manifest) do
	if (not o.destinationId or line.custodyState=='DELIVERED') and line.deliveryReceipt and line.deliveryReceipt.destinationId==(o.destinationId or 'player:'..o.requesterId) then
	    local credited=false
	    for pass=1,2 do
		for i,request in ipairs(o.items) do
		    if (pass==1 and request.sourceId==line.sourceId or pass==2 and not request.sourceId)
			and request.fullType==r.itemTypes[tostring(line.itemId)] and counts[i]<request.quantity then
			counts[i]=counts[i]+1 credited=true break
		    end
		end
		if credited then break end
	    end
	end
    end
    return counts
end
function Service.hasOutstanding(o,r)
    local counts=Service.projectDelivery(o,r)
    for i,line in ipairs(o.items) do if counts[i]<line.quantity then return true end end
    return false
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
    for _,line in ipairs(o.items) do
        local why=require('EmberRoutesProbe/PublicWork').deliveryOverlapReason(o,line)
        if why then
            for _,fullType in pairs(intent.itemTypes or {}) do
                if fullType==line.fullType then o.reason=why Signals.changed() return why end
            end
        end
    end
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
		    local counts=Service.projectDelivery(o,r)
		    for i,request in ipairs(o.items) do request.delivered=counts[i] end
                    env.directory:release('delivery:'..o.id,o.jobId,{effects='KNOWN',obligationsCleared=true})
                    o.jobId,o.npcId=nil,nil o.revision=o.revision+1
                    o.cancelled=o.cancelled or r.returning
                    o.state=o.cancelled and 'CANCELLED' or outstanding(o) and 'WAITING' or 'DONE'
                    Signals.changed()
                elseif not o.cancelled and r.state=='PAUSED' and not r.controlUncertain and not r.activeAttempt and not r.manualPaused
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
