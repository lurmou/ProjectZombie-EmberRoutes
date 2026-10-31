-- Tool custody and ownership/authorization unit tests for Phase 1A.
local n=0
local function check(v,msg) n=n+1 assert(v,msg) end

local root={}
local registry={data=function() return root end,id=function() return 'custody-1' end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=registry
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Boot']={controlledExecution=true,ready=true,enabled=true,runtimeReady=true}

local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/ToolCustodyRecord'

-- 1. Schema Validation Checks
local validEntry={
    format=1,
    id='custody:1:101',
    npcId=1,
    itemId=101,
    role='CLEAN_TOOL',
    state='HELD',
    sequence=1,
    activeJobId='job-1',
    sourceContainerId='crate-1',
    claims={'item:101'}
}
check(Record.valid(validEntry),'valid entry passes schema')

local badEntry={format=2,id='bad',npcId='nan',itemId=-1,role='',state='UNKNOWN',sequence=-1,claims={}}
check(not Record.valid(badEntry),'invalid entry rejected by schema')
check(not Record.valid({format=1,id='c:1:101',npcId=1,itemId=101,role='TOOL',state='HELD',sequence=1,claims={'wrong'}}),'mismatched claims rejected')

-- 2. canClaimTool vs validToolUse
-- Unclaimed item: can claim, but CANNOT use (no claim exists)
check(Store.canClaimTool(1,201),'unclaimed item can be claimed')
check(not Store.validToolUse(1,'job-1',201),'unclaimed item cannot be used directly without claim')

-- Claim custody for NPC 1 on item 201
local custody,err=Store.claimCustody(1,201,'CLEAN_TOOL','crate-1','job-1')
check(custody~=nil and not err,'custody claimed successfully')
check(custody.state=='RESERVED','initial state is RESERVED')

-- Now NPC 1 on job-1 has valid tool use
check(Store.validToolUse(1,'job-1',201),'authorized job on same NPC has valid tool use')
-- Another job on same NPC without assignment cannot use it yet
check(not Store.validToolUse(1,'job-2',201),'unassigned job on same NPC rejected')
-- Another NPC cannot use or claim it
check(not Store.validToolUse(2,'job-9',201),'other NPC rejected for tool use')
check(not Store.canClaimTool(2,201),'other NPC cannot claim reserved tool')
-- Same NPC can re-claim/assign
check(Store.canClaimTool(1,201),'same NPC can reuse custody tool')

-- Assign to job-2
check(Store.assignToolUse(custody.id,'job-2'),'assign tool use to job-2')
check(Store.validToolUse(1,'job-2',201),'job-2 now has valid tool use')
check(not Store.validToolUse(1,'job-1',201),'job-1 no longer active on custody')

-- 3. Multi-tool / Multi-resource custody
local fluidCustody=Store.claimCustody(1,202,'CLEAN_FLUID','shelf-1','job-2')
check(fluidCustody~=nil,'fluid custody claimed for cleaning consumable')
local npcTools=Store.custodyForNpc(1)
check(#npcTools==2,'NPC 1 has both mop and cleaner in custody')

-- 4. Reload Recovery: Claims rebuilt from root.toolCustody
local savedRoot=root
-- Simulate world reload with a fresh registry data table sharing root content
local freshRoot={
    taskJobs={format=1,byId={}},
    toolCustody=savedRoot.toolCustody
}
registry.data=function() return freshRoot end

-- Trigger Store.data() refresh
local data=Store.data()
check(Store.validToolUse(1,'job-2',201),'after reload, custody claim rebuilt and valid for job-2')
check(Store.validToolUse(1,'job-2',202),'after reload, fluid custody claim rebuilt and valid for job-2')
check(not Store.canClaimTool(2,201),'after reload, other NPC still cannot steal claimed tool')

-- 5. Release Custody
check(Store.releaseCustody(custody.id),'custody released')
check(Store.canClaimTool(2,201),'item 201 is now free and can be claimed by others')
check(not Store.validToolUse(1,'job-2',201),'item 201 can no longer be used by job-2')

print(string.format('PASS %d tool custody lifecycle & authorization checks',n))
