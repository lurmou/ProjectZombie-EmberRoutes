-- Sole writer of world-local identity and macro intentions. Execution lives in MembershipRuntime.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Ledger=require 'EmberRoutesProbe/SettlementLedger'
local Policy=require 'EmberRoutesProbe/MembershipPolicy'
local S={}
local indexWorld,index,dirty=nil,{},true
local contexts={WAIT=true,FOLLOW=true,RETURN=true,SETTLEMENT=true}
local kinds={SETTLE=true,FOLLOW=true,WAIT=true,RETURN=true,TRANSFER=true,UNASSIGN=true}
local function copy(v)
    if type(v)~='table' then return v end
    local r={} for k,x in pairs(v) do r[k]=copy(x) end return r
end
local function store()
    local value=Registry.data().npcMembership
    if type(value)~='table' or value.format~=1 or type(value.byNpc)~='table'
        or type(value.receipts)~='table' or type(value.receiptOrder)~='table' then return nil end
    return value
end
local function notify(id)
    dirty=true
    require('EmberRoutesProbe/LaborSignals').changed(id)
    if S.changed then S.changed(id) end
end
local function receipt(data,key,value)
    if not data.receipts[key] then data.receiptOrder[#data.receiptOrder+1]=key end
    data.receipts[key]=value
    -- Pending requests remain in the member row even if their technical receipt is evicted.
    while #data.receiptOrder>128 do local old=table.remove(data.receiptOrder,1) data.receipts[old]=nil end
end
local function validRow(id,r)
    return type(id)=='string' and id~='' and type(r)=='table' and r.npcId==id
        and type(r.factionId)=='string' and contexts[r.context] and type(r.revision)=='number'
        and r.revision>=1 and r.revision<9007199254740000 and r.revision==math.floor(r.revision)
        and (r.settlementId==nil or type(r.settlementId)=='string')
        and (r.context~='FOLLOW' or type(r.leaderId)=='string')
        and (r.pendingCommand==nil or type(r.pendingCommand)=='table' and kinds[r.pendingCommand.kind]
            and type(r.pendingCommand.requestId)=='string' and r.pendingCommand.acceptedRevision==r.revision
            and type(r.pendingCommand.expectedRevision)=='number'
            and (r.pendingCommand.kind~='FOLLOW' or type(r.pendingCommand.leaderId)=='string'))
end
function S.load()
    local data=store() if not data then return false,'MEMBERSHIP_NEW_WORLD_REQUIRED' end
    local n=0 for id,r in pairs(data.byNpc) do n=n+1 if n>512 or not validRow(id,r) then return false,'MEMBERSHIP_FORMAT_INVALID' end end
    return true
end
function S.newWorld(freshRoot)
    local root=freshRoot or Registry.data()
    if root.npcMembership~=nil then return S.load() end
    -- A character creation event in an old world is NOT a migration grant.
    for _,key in ipairs({'containers','jobs','companionIntents','executionSave','production','publicWork'}) do
        local value=root[key]
        if type(value)=='table' then for _ in pairs(value) do return false,'MEMBERSHIP_NEW_WORLD_REQUIRED' end end
    end
    if root.taskJobs then for _ in pairs(root.taskJobs.byId or {}) do return false,'MEMBERSHIP_NEW_WORLD_REQUIRED' end end
    root.npcMembership={format=1,byNpc={},receipts={},receiptOrder={}}
    return true
end
function S.register(id)
    local data=store() if not data or type(id)~='string' or id=='' then return false end
    if data.byNpc[id] then return true end
    local n=0 for _ in pairs(data.byNpc) do n=n+1 end if n>=512 then return false,'MEMBERSHIP_LIMIT' end
    data.byNpc[id]={npcId=id,factionId=Ledger.data().factionId,context='WAIT',revision=1}
    notify(id) return true
end
function S.character(actor)
    if not actor or actor:isDead() or not actor.getModData then return nil end
    local md=actor:getModData()
    if not md.EmberRoutesCharacterId then md.EmberRoutesCharacterId=Registry.id() end
    return md.EmberRoutesCharacterId
end
function S.entry(id,scope)
    local data=store() local row=data and data.byNpc[id]
    if not row or not row.settlementId then return nil,'NO_MEMBERSHIP',row and row.revision end
    local root=Ledger.data() local e=root.entries[row.settlementId]
    if not e then return nil,'TARGET_LOST',row.revision end
    if row.factionId~=root.factionId or e.factionId~=row.factionId then return nil,'ACCESS_DENIED',row.revision end
    if scope and scope~=e.id then return nil,'SCOPE_MISMATCH',row.revision end
    return e,nil,row.revision
end
function S.check(id,purpose,observation,expected)
    local data=store() local row=data and data.byNpc[id]
    local e=S.entry(id)
    return Policy.evaluate(row,e,purpose,observation,expected)
end
function S.view(id)
    local data=store() local r=data and data.byNpc[id] if not r then return nil,'NO_MEMBERSHIP' end
    local value=copy(r) value.pending=value.pendingCommand value.pendingCommand=nil
    local e,why=S.entry(id)
    value.settlementName=e and e.name value.reason=r.reason or (r.settlementId and why)
    return value
end
-- Rebuild only on membership changes/world replacement; UI receives detached stable IDs.
function S.members(scope)
    local data=store() if not data then return {} end
    if dirty or indexWorld~=data then
        indexWorld,index,dirty=data,{},false
        for id,r in pairs(data.byNpc) do
            if not r.retired then
                local key=r.settlementId or '' index[key]=index[key] or {} index[key][#index[key]+1]=id
            end
        end
        for _,ids in pairs(index) do table.sort(ids) end
    end
    local result={} for _,id in ipairs(index[scope or ''] or {}) do result[#result+1]=id end return result
end
local function reject(why) return {state='REJECTED',reason=why} end
function S.request(actor,id,c)
    local data=store() local row=data and data.byNpc[id]
    if not data then return reject('MEMBERSHIP_NEW_WORLD_REQUIRED') end
    if not Ledger.authorized(actor) then return reject('ACCESS_DENIED') end
    if not row or row.retired then return reject('NO_MEMBERSHIP') end
    if row.factionId~=Ledger.data().factionId then return reject('ACCESS_DENIED') end
    if not require('EmberRoutesProbe/Driver').bindId(actor,id) then return reject('CARRIER_UNAVAILABLE') end
    if type(c)~='table' or not kinds[c.kind] or type(c.requestId)~='string' or c.requestId=='' or #c.requestId>128
        or type(c.expectedRevision)~='number' then return reject('INVALID_COMMAND') end
    local key=id..':'..c.requestId
    local prior=data.receipts[key]
    if prior then
        if prior.kind~=c.kind or prior.settlementId~=c.settlementId then return reject('REQUEST_CONFLICT') end
        return copy(prior)
    end
    if row.pendingCommand and row.pendingCommand.requestId==c.requestId then
        local p=row.pendingCommand
        if p.kind~=c.kind or p.settlementId~=c.settlementId then return reject('REQUEST_CONFLICT') end
        return copy(p)
    end
    if row.revision~=c.expectedRevision then return reject('STALE_MEMBERSHIP') end
    local target=c.kind=='SETTLE' or c.kind=='TRANSFER'
    if target then
        local entry=Ledger.data().entries[c.settlementId]
        if not entry then return reject('TARGET_LOST') end
        if entry.factionId~=row.factionId then return reject('ACCESS_DENIED') end
    elseif c.kind=='RETURN' and not S.entry(id) then return reject('TARGET_LOST') end
    local leader=c.kind=='FOLLOW' and S.character(actor) or nil
    if c.kind=='FOLLOW' and not leader then return reject('LEADER_ID_UNAVAILABLE') end
    if row.pendingCommand then
        local old=row.pendingCommand
        receipt(data,id..':'..old.requestId,{state='CANCELLED',requestId=old.requestId,kind=old.kind,settlementId=old.settlementId,revision=row.revision+1})
    end
    row.revision=row.revision+1 row.reason='COMMAND_PENDING' row.obligations=nil
    row.pendingCommand={state='PENDING',requestId=c.requestId,kind=c.kind,settlementId=c.settlementId,
        expectedRevision=c.expectedRevision,acceptedRevision=row.revision,leaderId=leader}
    receipt(data,key,{state='PENDING',requestId=c.requestId,kind=c.kind,settlementId=c.settlementId,revision=row.revision})
    notify(id) return copy(data.receipts[key])
end
function S.advance(id,actor,obligations,bodyOwned)
    local data=store() local r=data and data.byNpc[id] local c=r and r.pendingCommand
    if not c then return false end
    if bodyOwned then r.reason='BODY_STOPPING' return false end
    if c.kind=='FOLLOW' and (not actor or actor:isDead() or S.character(actor)~=c.leaderId) then
        r.reason='LEADER_LOST' return false
    end
    local hasToolCustody=false
    for _,o in ipairs(obligations or {}) do
        if o.kind=='TOOL_CUSTODY' then hasToolCustody=true break end
    end
    local changing=c.kind=='UNASSIGN' or ((c.kind=='TRANSFER' or c.kind=='SETTLE') and c.settlementId~=r.settlementId)
        or (c.kind=='FOLLOW' and hasToolCustody)
    if changing and #obligations>0 then r.reason='OBLIGATION_PENDING' r.obligations=copy(obligations) return false end
    if c.kind=='SETTLE' or c.kind=='TRANSFER' then
        local e=Ledger.data().entries[c.settlementId]
        if not e or e.factionId~=r.factionId then r.reason='TARGET_LOST' return false end
        r.settlementId=c.settlementId r.context='SETTLEMENT'
    elseif c.kind=='UNASSIGN' then r.settlementId=nil r.context='WAIT'
    else r.context=c.kind end
    r.leaderId=r.context=='FOLLOW' and c.leaderId or nil
    r.revision=r.revision+1 r.pendingCommand=nil r.reason=nil r.obligations=nil
    receipt(data,id..':'..c.requestId,{state='COMMITTED',requestId=c.requestId,kind=c.kind,settlementId=c.settlementId,revision=r.revision})
    notify(id) return true
end
function S.cancel(actor,id,requestId,expected)
    local data=store() local r=data and data.byNpc[id] local c=r and r.pendingCommand
    if not Ledger.authorized(actor) then return reject('ACCESS_DENIED') end
    if not r or r.revision~=expected then return reject('STALE_MEMBERSHIP') end
    if not c or c.requestId~=requestId then return reject('STALE_REQUEST') end
    r.revision=r.revision+1 r.pendingCommand=nil r.reason=nil r.obligations=nil
    local result={state='CANCELLED',requestId=requestId,kind=c.kind,settlementId=c.settlementId,revision=r.revision}
    receipt(data,id..':'..requestId,result) notify(id) return copy(result)
end
function S.transition(id,expected,context,reason)
    local data=store() local r=data and data.byNpc[id]
    if not r or r.pendingCommand or r.revision~=expected or not contexts[context] then return false end
    r.context=context r.reason=reason r.revision=r.revision+1
    if context~='FOLLOW' then r.leaderId=nil end
    notify(id) return true
end
function S.note(id,reason)
    local data=store() local r=data and data.byNpc[id]
    if r and r.reason~=reason then r.reason=reason require('EmberRoutesProbe/LaborSignals').changed(id) end
end
function S.retire(id,settled)
    local data=store() local r=data and data.byNpc[id] if not r then return true end
    if r.pendingCommand then
        local c=r.pendingCommand
        receipt(data,id..':'..c.requestId,{state='CANCELLED',requestId=c.requestId,kind=c.kind,settlementId=c.settlementId,revision=r.revision+1})
    end
    r.retired=true r.pendingCommand=nil r.revision=r.revision+1
    if settled then data.byNpc[id]=nil end notify(id) return settled
end
function S.setReturnPoint(actor,scope,point,expected)
    return Ledger.setReturnPoint(actor,scope,point,expected)
end
return S
