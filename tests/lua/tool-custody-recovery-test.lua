local fixture=dofile('tests/lua/tool-custody-ledger-test.lua')
local root=fixture.root
root.taskJobs={format=1,byId={}}
local original
for _,record in pairs(root.obligations.byId) do
    if record.type=='TOOL_CUSTODY' and record.state=='ACTIVE' then original=record break end
end
assert(original,'unfinished custody fixture required')
local copy={id=original.id..':collision',type='TOOL_CUSTODY',npcId='other',revision=1,state='ACTIVE',
    data={itemId=original.data.itemId,role=original.data.role,custodyState='RESERVED',sequence=1,
        sourceId='source',claimId=original.id..':collision:c1'}}
root.obligations.byId[copy.id]=copy
local jobs=assert(require('EmberRoutesProbe/Kernel/JobStore').open(root))
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return jobs end}
package.loaded['EmberRoutesProbe/Work/LaborStore']=nil
package.loaded['EmberRoutesProbe/Kernel/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end,watch=function() end}
local Store=require 'EmberRoutesProbe/Work/LaborStore'
assert(Store.data()==root)
assert(root.obligations.byId[original.id].state=='RECONCILE_REQUIRED'
    and root.obligations.byId[copy.id].state=='RECONCILE_REQUIRED','both conflicts remain diagnosable')
assert(root.quarantineResources['item:'..tostring(copy.data.itemId)],'conflicting claim is quarantined')
local Custody=require 'EmberRoutesProbe/Field/ToolCustody'
local selected,why=Custody.byItem(copy.data.itemId)
assert(not selected and why=='TOOL_CUSTODY_CONFLICT','ambiguous item cannot select a custody')
print('PASS custody cold collision retains both records and quarantine; disk NOT RUN')
