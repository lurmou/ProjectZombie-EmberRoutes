-- Durable business facts, never an inventory or a body owner.
local M={}
local states={UNCOLLECTED=true,CARRIED=true,RECONCILE=true,DELIVERED=true,WITHDRAWN=true}
function M.pending(line) return line.custodyState~='DELIVERED' and line.custodyState~='WITHDRAWN' end
function M.valid(r)
    if r.format~=2 or (r.producer~='LOGISTICS' and r.producer~='DELIVERY') or type(r.source)~='string' or type(r.destination)~='string'
        or type(r.settlementId)~='string' or type(r.items)~='table' or #r.items<1 or #r.items>30
        or type(r.manifest)~='table' or #r.manifest~=#r.items or r.plannedCount~=#r.items
        or type(r.routeRevision)~='number' or r.routeRevision<0 or r.routeRevision>=9007199254740991 or r.routeRevision~=math.floor(r.routeRevision)
        or type(r.attemptSequence)~='number' or r.attemptSequence<0 or r.attemptSequence>=9007199254740991 or r.attemptSequence~=math.floor(r.attemptSequence) then return false end
    local seen={}
    for i,id in ipairs(r.items) do
        local l=r.manifest[i]
        if type(id)~='number' or id~=id or math.abs(id)==math.huge or seen[id] or type(l)~='table'
            or l.itemId~=id or not states[l.custodyState] or l.deliveryPolicy~=(r.producer=='DELIVERY' and 'PLAYER' or 'AUTO_STORAGE')
            or l.sourceId~=r.source then return false end
        if l.custodyState=='DELIVERED' and (type(l.deliveryReceipt)~='table'
            or type(l.deliveryReceipt.destinationId)~='string' or type(l.deliveryReceipt.attemptId)~='string') then return false end
        seen[id]=true
        if r.producer=='DELIVERY' and (type(r.itemTypes)~='table' or type(r.itemTypes[tostring(id)])~='string') then return false end
    end
    if r.producer=='DELIVERY' and (type(r.orderId)~='string' or type(r.orderRevision)~='number' or r.orderRevision<1
        or r.orderRevision~=math.floor(r.orderRevision) or r.orderRevision>=9007199254740991
        or type(r.requesterId)~='string' or type(r.itemTypes)~='table') then return false end
    local a=r.activeAttempt
    if a and (type(a)~='table' or not seen[a.itemId] or (a.kind~='TAKE' and a.kind~='PUT')
        or type(a.attemptId)~='string' or type(a.fromId)~='string' or type(a.toId)~='string') then return false end
    return true
end
function M.create(r,locations)
    local lines={}
    for _,id in ipairs(r.items) do
        local where=locations and locations[id] or 1
        local l={itemId=id,sourceId=r.source,sourceMode=r.sourceMode,deliveryPolicy=r.producer=='DELIVERY' and 'PLAYER' or 'AUTO_STORAGE',
            custodyState=where==2 and 'CARRIED' or where==3 and 'DELIVERED' or 'UNCOLLECTED'}
        if where==3 then l.deliveryReceipt={destinationId=r.destination,attemptId=r.id..':upgrade:'..tostring(id)} end
        lines[#lines+1]=l
    end
    return lines
end
function M.claimItemIds(r)
    if r.format~=2 then return r.items end
    local ids={} for _,l in ipairs(r.manifest) do if M.pending(l) then ids[#ids+1]=l.itemId end end return ids
end
function M.line(r,id) for _,l in ipairs(r.manifest) do if l.itemId==id then return l end end end
function M.count(r)
    local delivered,withdrawn,held=0,0,0
    for _,l in ipairs(r.manifest) do
        if l.custodyState=='DELIVERED' then delivered=delivered+1
        elseif l.custodyState=='WITHDRAWN' then withdrawn=withdrawn+1
        elseif l.custodyState=='CARRIED' then held=held+1 end
    end
    return delivered,withdrawn,held
end
return M
