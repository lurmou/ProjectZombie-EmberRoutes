local Ledger=require 'EmberRoutesProbe/Kernel/ObligationLedger'
local doc=Ledger.fresh()
local function proposal(base,ops) local value,why=Ledger.propose(base,ops) assert(value,why) return value end
local function rejected(base,ops) local value=Ledger.propose(base,ops) assert(value==nil) end
local item={id='item-obligation',type='CARRIED_ITEM',npcId='npc',jobId='job',revision=1,state='ACTIVE',data={itemId=17,sourceId='box'}}
local active=proposal(doc,{{action='CREATE',id=item.id,record=item}})
assert(not doc.byId[item.id] and Ledger.outstanding(active,'job')==1)
rejected(active,{[2]={action='SETTLE',id=item.id,expectedRevision=1}})
local uncertain=proposal(active,{{action='RECONCILE',id=item.id,expectedRevision=1}})
rejected(uncertain,{{action='CONFIRM',id=item.id,expectedRevision=2,evidence={effects='KNOWN',itemId=17}}})
local confirmed=proposal(uncertain,{{action='CONFIRM',id=item.id,expectedRevision=2,evidence={effects='KNOWN',itemId=17,originalPresent=true}}})
assert(confirmed.byId[item.id].state=='ACTIVE' and confirmed.byId[item.id].revision==3)
rejected(active,{{action='SETTLE',id='missing',expectedRevision=1,evidence={effects='KNOWN'}}})
rejected(active,{{action='SETTLE',id=item.id,expectedRevision=2,evidence={effects='KNOWN'}}})
rejected(active,{{action='SETTLE',id=item.id,expectedRevision=1,evidence={effects='UNKNOWN',itemId=17,destinationId='box',originalPresent=true,attemptId='a'}}})
rejected(active,{{action='SETTLE',id=item.id,expectedRevision=1,evidence={effects='KNOWN',itemId=17,destinationId='box',attemptId='a'}}})
local settled=proposal(active,{{action='SETTLE',id=item.id,expectedRevision=1,evidence={effects='KNOWN',itemId=17,destinationId='box',originalPresent=true,attemptId='a'}}})
assert(Ledger.outstanding(settled,'job')==0 and settled.byId[item.id].settlement.attemptId=='a')
assert(active.byId[item.id].state=='ACTIVE','candidate cannot mutate live document')
local furnace={id='furnace',type='FURNACE_DUTY',npcId='npc',jobId='cook',revision=1,state='ACTIVE',data={siteKey='stove',openedByJob=true}}
local heating=proposal(settled,{{action='CREATE',id=furnace.id,record=furnace}})
rejected(heating,{{action='SETTLE',id='furnace',expectedRevision=1,evidence={effects='KNOWN',siteKey='stove',inactive=true,foodClear=true,shutdownRequired=true}}})
rejected(heating,{{action='TRANSFER',id='furnace',expectedRevision=1,npcId='other',evidence={siteKey='stove',bodyReleased=true,siteVerified=true}}})
local moved=proposal(heating,{{action='TRANSFER',id='furnace',expectedRevision=1,npcId='other',evidence={siteKey='stove',bodyReleased=true,siteVerified=true,originalsVerified=true}}})
assert(moved.byId.furnace.npcId=='other' and moved.byId.furnace.transfers[1].from=='npc')
local done=proposal(moved,{{action='SETTLE',id='furnace',expectedRevision=2,evidence={effects='KNOWN',siteKey='stove',inactive=true,foodClear=true,shutdownRequired=true,shutdownObserved=true}}})
assert(Ledger.outstanding(done)==0)
rejected(done,{{action='RETIRE',id='furnace',expectedRevision=3}})
local noProof=Ledger.propose(done,{{action='RETIRE',id='furnace',expectedRevision=3}},function() return false end)
assert(noProof==nil,'retirement requires a successful authority check')
local retired=assert(Ledger.propose(done,{{action='RETIRE',id='furnace',expectedRevision=3}},function(record)
    return record.state=='SETTLED' and record.settlement.shutdownObserved==true
end))
assert(not retired.byId.furnace and done.byId.furnace,'retirement only changes the candidate')
local rolling=heating
for i=1,20 do
    local current=rolling.byId.furnace
    local nextOwner=current.npcId=='npc' and 'other' or 'npc'
    rolling=proposal(rolling,{{action='TRANSFER',id='furnace',expectedRevision=current.revision,npcId=nextOwner,
        evidence={siteKey='stove',bodyReleased=true,siteVerified=true,originalsVerified=true}}})
end
assert(rolling.byId.furnace.transferCount==20 and #rolling.byId.furnace.transfers==16,'bounded history does not stop custody transfer')
assert(not Ledger.check({byId={}}),'unversioned ledger refused')
print('PASS obligation candidate boundaries; no persistence or engine evidence')
