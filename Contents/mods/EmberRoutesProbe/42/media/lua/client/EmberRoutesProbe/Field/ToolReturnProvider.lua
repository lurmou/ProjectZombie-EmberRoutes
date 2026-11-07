-- Tool return provider: dispatches independent tool return jobs via PublicWork.
-- When a tool is held idle with no active job for 30 seconds, it offers a tool return order.
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local ToolReturnService=require 'EmberRoutesProbe/Field/ToolReturnService'
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'

local Provider={category='toolReturn',defaultPriority=4,idleThreshold=30000}
local idleSince={}
local idleItems={}
local world,owned,nextRecovery=nil,{},0
local iterator,scanState,scanKey
local function resetWorld()
    local root=Registry.data()
    if root~=world then world,owned,idleSince,idleItems,nextRecovery,iterator=root,{},{},{},0,nil end
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
    return err or 'TOOL_RETURN_FAILED'
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
    local root=resetWorld()
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
    local custodies=root.toolCustody and root.toolCustody.byId
    if not custodies then return end
    if not iterator or scanState~=custodies then iterator,scanState,scanKey=pairs(custodies) end
    for _=1,4 do
        local key,c=iterator(scanState,scanKey) scanKey=key
        if not key then iterator=nil break end
        if c.state=='PENDING_RETURN' and not ToolReturnService.liveTask(c.npcId) then
            ToolReturnService.startFor(env.actor,tostring(c.npcId),c.id,c.returnJobId,nil)
        elseif c.state=='DEAD_CARRIER' then
            -- Legacy entries written before death became a release settlement:
            -- the carrier is dead and no path can consume this state, so
            -- releasing the custody is the only exit it can ever take.
            Store.releaseCustody(c.id)
        end
    end
end

function Provider.hasWork()
    local root=resetWorld()
    for _ in pairs(owned) do return true end
    for _ in pairs(root.toolCustody and root.toolCustody.byId or {}) do return true end
    return false
end

function Provider.beforeClaim(selected,npcId)
    if selected.category~=Provider.category and ToolReturnService.canInterrupt(npcId) then
	ToolReturnService.interrupt(npcId,'PREEMPTED_BY_'..string.upper(selected.category))
    end
end
return Provider
