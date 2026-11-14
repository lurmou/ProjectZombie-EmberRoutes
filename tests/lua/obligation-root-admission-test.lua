local root={}
ModData={getOrCreate=function() return root end}
EmberRoutesProbeJava={}
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local function refused(value,reason)
    root=value local beforeFormat=value.format local originalJobs=value.taskJobs local originalObligations=value.obligations
    local ok,why=pcall(Registry.data)
    assert(not ok and string.find(tostring(why),reason,1,true),tostring(why))
    assert(value.format==beforeFormat and value.taskJobs==originalJobs and value.obligations==originalObligations
        and value.containers==nil,'rejected root is not filled or replaced')
end
refused({format=1,taskJobs={format=1,byId={}}},'WORK_FORMAT_UNSUPPORTED')
refused({format=2,taskJobs={format=1,byId={}}},'OBLIGATION_FORMAT_UNSUPPORTED')
refused({format=2,obligations={format=1,byId={}},toolCustody={format=1,byId={}}},'TOOL_CUSTODY_FORMAT_UNSUPPORTED')
refused({format=2,obligations={format=99,byId={}}},'OBLIGATION_FORMAT_UNSUPPORTED')
refused({format=2,obligations={format=1,byId={}},taskJobs={format=99,byId={}}},'JOB_FORMAT_UNSUPPORTED')
local owed={id='owed',type='CARRIED_ITEM',npcId='npc',jobId='job',revision=1,state='ACTIVE',data={itemId=12}}
refused({format=2,obligations={format=1,byId={owed=owed}},taskJobs={format=1,byId={}}},'OBLIGATION_JOB_MISSING')
local job={id='job',npcId='npc',providerType='TEST',scopeId='world',revision=1,state='PREPARING',effects='KNOWN',obligations={},payload={claims={}}}
refused({format=2,obligations={format=1,byId={owed=owed}},taskJobs={format=1,byId={job=job}}},'OBLIGATION_CLAIM_RETAINED')
root={}
assert(Registry.data()==root and root.format==2 and root.obligations.format==1 and root.obligations.byId)
local prior=root.obligations
root.obligations={format=99,byId={}}
assert(not pcall(Registry.data),'replaced ledger must be revalidated')
root.obligations=prior
assert(Registry.data()==root)
print('PASS obligation root admission and rejection without mutation; disk NOT RUN')
