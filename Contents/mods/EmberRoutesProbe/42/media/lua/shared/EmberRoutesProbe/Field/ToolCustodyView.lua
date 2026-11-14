-- Detached domain view of one ledger record; never an authority.
local V={}
function V.fromRecord(record)
    if not record or record.type~='TOOL_CUSTODY' or record.state=='SETTLED' then return nil end
    local d=record.data
    local intent=d.returnIntent
    return {format=1,id=record.id,npcId=record.npcId,itemId=d.itemId,role=d.role,
        state=d.custodyState,reason=d.reason,sequence=d.sequence,revision=record.revision,activeJobId=d.activeJobId,
        sourceContainerId=d.sourceId,returnJobId=d.returnJobId,claimId=d.claimId,
        returnIntent=intent and {format=1,jobId=intent.jobId,destinationId=intent.destinationId,scopeId=intent.scopeId} or nil,
        claims={'item:'..tostring(d.itemId)}}
end
return V
