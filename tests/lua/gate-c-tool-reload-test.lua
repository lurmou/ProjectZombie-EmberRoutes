-- Domain custody and return recovery; physical transfer and body are host fakes.
local n=0 local function check(v,m) n=n+1 assert(v,m) end
local root={} local serial=0
local function container()
    local c={items={}}
    function c:getItems() return {size=function() return #c.items end,get=function(_,i) return c.items[i+1] end,
        contains=function(_,item) for _,v in ipairs(c.items) do if v==item then return true end end return false end} end
    function c:getFirstEvalRecurse(fn) for _,v in ipairs(c.items) do if fn(v) then return v end end end
    function c:hasRoomFor() return true end
    return c
end
local inv,box=container(),container()
local endpoint={id='S',container=box,object={}}
local Registry={data=function() return root end,id=function() serial=serial+1 return 'r-'..serial end,
    resolve=function(id) if id=='S' then return endpoint end end,revalidate=function() return true end,
    logistics=function() return 'STORAGE' end,accepts=function() return true end,inventoryChanged=function() end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end,watch=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
package.loaded['EmberRoutesProbe/Boot']={controlledExecution=true}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {handle=npc} end,valid=function() return true end}
package.loaded['EmberRoutesProbe/WorkTransfer']={reachable=function() return true end}
package.loaded['EmberRoutesProbe/CraftSupply']={}
package.loaded['TimedActions/ISInventoryTransferAction']=true
package.loaded['EmberRoutesProbe/FieldActions']={}
ISTimedActionQueue={queues={}}
local actions={} local spec local physical=0
local body={stop=function() return true end,clear=function() return true end,add=function(a) actions[#actions+1]=a return true end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {accepting=function() return true end,
    submit=function(_,s) spec=s s.start(body) return {} end,inspect=function() return {state='ACTIVE'} end} end}
npc={id='n',isDead=function() return false end,getInventory=function() return inv end}
ISInventoryTransferAction={new=function(_,worker,item,from,to) return {isValid=function() return true end,
    transferItem=function(_,i)
        physical=physical+1
        for k,v in ipairs(from.items) do if v==i then table.remove(from.items,k) break end end
        to.items[#to.items+1]=i i.container=to return true
    end} end}
local tool={id=31,container=inv,getID=function(self) return self.id end,getContainer=function(self) return self.container end}
inv.items={tool}
local actor={isDead=function() return false end}
local Store=require 'EmberRoutesProbe/LaborStore'
local Service=require 'EmberRoutesProbe/ToolReturnService'
local function copy(v) if type(v)~='table' then return v end local t={} for k,x in pairs(v) do t[k]=copy(x) end return t end
local function reload()
    root=copy(root) -- serialization may duplicate byId/byNpc/byItem table aliases
    Store.data() Service.reconcile()
end
local function stop(reason)
    local s=spec
    local controller={inspect=function() return {state='STOPPING',npcId=s.npcId,jobId=s.jobId} end,
        bodySnapshot=function() return {available=true,nativeStopped=true} end,stopBody=function() return true end}
    local adapter=s.stopAdapter(controller,function() return {} end)
    check(adapter.requestStop(reason),'stop request accepted')
    check(adapter.persistEffects(adapter.observeStop()),'known physical stop persisted')
end
local custody=assert(Store.claimCustody('n',31,'DIG','S','field-1')) custody.state='HELD'
reload()
check(Store.validToolUse('n','field-1',31) and not Store.canClaimTool('other',31),'held-tool reload restores sole holder/job and claim')
custody=Store.custodyByItem(31) custody.activeJobId=nil -- field settlement boundary
check(Service.startFor(actor,'n',custody.id,'return-1','home'),'return obligation starts')
check(not Store.canClaimTool('n',31),'return obligation blocks new tool claim')
spec.tick() -- reached destination, no transfer yet
stop('SAVE')
check(Store.custodyByItem(31).state=='PENDING_RETURN' and Store.custodyByItem(31).returnJobId=='return-1','save preserves unfinished return intent')
reload()
check(Service.recoverFor(actor,'n'),'unfinished return recovered under same ID')
check(Service.liveTask('n').returnJobId=='return-1','reload does not invent a second return job')
spec.tick() spec.tick()
check(#actions==1,'one native return action queued for held original')
local a=actions[#actions] check(a:isValid() and a:transferItem(tool),'native action transfers original')
check(not a:transferItem(tool) and physical==1,'post-transfer guard prevents second native submission')
-- Reload after physical transfer but before settlement: observation only.
reload()
check(Service.recoverFor(actor,'n'),'arrived original recovered before settlement')
spec.tick()
check(#actions==1,'arrived recovery does not repeat PUT')
stop('COMPLETED')
check(not Store.custodyByItem(31) and #box.items==1 and #inv.items==0,'settlement frees claim only for verified physical arrival')
local nextCustody=assert(Store.claimCustody('n',31,'DIG','S','field-2'))
check(nextCustody.itemId==31 and Store.validToolUse('n','field-2',31),'next job can re-borrow the same original')
-- Mixed PREPARE cancellation: never erase the already held original.
local held={id=32,container=inv,getID=tool.getID,getContainer=tool.getContainer}
inv.items={held} local c32=assert(Store.claimCustody('n',32,'DIG','S','field-3'))
local untouched={id=33,container=box,getID=tool.getID,getContainer=tool.getContainer}
box.items[#box.items+1]=untouched local c33=assert(Store.claimCustody('n',33,'DIG','S','field-3'))
local Supplies=require 'EmberRoutesProbe/FieldSupplies'
check(Supplies.releaseUncollected({npc=npc},{requirements={{itemId=32,custodyId=c32.id,containerId='S'},
    {itemId=33,custodyId=c33.id,containerId='S'}}}),'mixed pickup stop reconciles each original')
check(Store.custodyByItem(32).state=='HELD' and not Store.canClaimTool('other',32),'held tool retains obligation after interrupted pickup')
check(not Store.custodyByItem(33),'verified uncollected warehouse reservation releases')
print('PASS '..n..' Gate C tool held/unfinished-return reload checks; disk/native game UNVERIFIED')
