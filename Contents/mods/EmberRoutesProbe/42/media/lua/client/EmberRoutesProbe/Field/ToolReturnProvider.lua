-- Tool return provider: dispatches independent tool return jobs via PublicWork.
-- When a tool is held idle with no active job for 30 seconds, it offers a tool return order.
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local ToolReturnService=require 'EmberRoutesProbe/Field/ToolReturnService'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'

local Provider={category='toolReturn',defaultPriority=4,idleThreshold=30000}
local idleSince={}
local idleItems={}
local world,owned,nextRecovery=nil,{},0
local scanList,scanIndex
local function resetWorld()
    local root=Registry.data()
    if root~=world then world,owned,idleSince,idleItems,nextRecovery,scanList,scanIndex=root,{},{},{},0,nil,nil end
    return root
end

function Provider.discover(env)
    resetWorld()
    local custodies=Store.custodyForNpc(env.npcId)
    local now=env.now or 0
    for _,c in ipairs(custodies) do
        if c.state=='HELD' and not c.activeJobId and not c.returnJobId then
            if not idleSince[c.id] then
                idleSince[c.id]=now idleItems[c.id]=c.itemId
            elseif (now-idleSince[c.id])>=Provider.idleThreshold then
                local offerKey='toolReturn:'..c.id
                if not env.candidateReady or env.candidateReady(offerKey) then
                    local rev=1
                    if env.upsertOffer then
                        local offer,r=env.upsertOffer(offerKey,1,'toolReturn',env.entry and env.entry.id)
                        rev=r or 1
                    end
                    if env.candidates then
                        env.candidates[#env.candidates+1]={
                            key=offerKey,
                            revision=rev,
                            category='toolReturn',
                            priority=env.priority or 4,
                            custodyId=c.id,
                            itemId=c.itemId,
                            role=c.role
                        }
                    end
                end
            end
        else
            idleSince[c.id]=nil idleItems[c.id]=nil
        end
    end
end

function Provider.claim(selected,npcId,jobId,env)
    resetWorld()
    local actor=env and env.actor
    local scopeId=env and env.entry and env.entry.id
    local ok,err=ToolReturnService.startFor(actor,npcId,selected.custodyId,jobId,scopeId,{trackResult=true})
    if ok then
        idleSince[selected.custodyId]=nil idleItems[selected.custodyId]=nil
        owned[jobId]={key=selected.key,directory=env.directory}
        return 'STARTED'
    end
    -- startFor aborts its own return intent before refusing after assignment.
    return err or 'TOOL_RETURN_FAILED','ROLLED_BACK'
end

function Provider.reconcile()
    resetWorld()
    ToolReturnService.reconcile()
    local deadKeys={}
    for cid,_ in pairs(idleSince) do
        local c=Store.custodyByItem and Store.custodyByItem(idleItems[cid])
        if not c or c.id~=cid or c.state~='HELD' or c.activeJobId or c.returnJobId then
            deadKeys[#deadKeys+1]=cid
        end
    end
    for _,cid in ipairs(deadKeys) do idleSince[cid]=nil idleItems[cid]=nil end
end

function Provider.advance(env)
    resetWorld()
    Provider.reconcile()
    for jobId,row in pairs(owned) do
        local result=ToolReturnService.returnResult(jobId)
        if result and result.knownStopped then
            local directory=row.directory or env.directory
            if directory and directory:release(row.key,jobId,{effects='KNOWN',obligationsCleared=true}) then
                owned[jobId]=nil ToolReturnService.forgetResult(jobId)
            end
        end
    end
    if env.now<nextRecovery then return end
    nextRecovery=env.now+5000
    -- Incremental scan over a snapshot list (sorted by custody id), resuming
    -- by index; the list is refreshed once exhausted or when the world changes.
    if not scanList then scanList=Store.custodyEntries() scanIndex=1 end
    for _=1,4 do
        local c=scanList[scanIndex] scanIndex=scanIndex+1
        if not c then scanList=nil break end
        if c.state=='PENDING_RETURN' and not ToolReturnService.liveTask(c.npcId) then
            ToolReturnService.startFor(env.actor,tostring(c.npcId),c.id,c.returnJobId,nil)
        end
    end
end

function Provider.hasWork()
    resetWorld()
    for _ in pairs(owned) do return true end
    return Store.hasCustody()
end

-- P4 (provider-lifecycle): an NPC mid-return still holds an unfinished
-- tool-return job. The live task is the truth: startFor records it until the
-- task stops or finishes, including recovery restarts driven by advance().
-- A HELD tool with no live task holds no job, so it does not retain.
function Provider.retained(npcId)
    return ToolReturnService.liveTask(npcId) ~= nil
end

function Provider.beforeClaim(selected,npcId)
    if selected.category~=Provider.category and ToolReturnService.canInterrupt(npcId) then
	ToolReturnService.interrupt(npcId,'PREEMPTED_BY_'..string.upper(selected.category))
    end
end
return Provider
