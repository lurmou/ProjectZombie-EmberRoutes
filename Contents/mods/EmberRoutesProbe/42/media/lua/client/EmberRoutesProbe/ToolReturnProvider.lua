-- Tool return provider: dispatches independent tool return jobs via PublicWork.
-- When a tool is held idle with no active job for 30 seconds, it offers a tool return order.
local Store=require 'EmberRoutesProbe/LaborStore'
local ToolReturnService=require 'EmberRoutesProbe/ToolReturnService'

local Provider={category='toolReturn',defaultPriority=4,idleThreshold=30000}
local idleSince={}

function Provider.discover(env)
    local custodies=Store.custodyForNpc(env.npcId)
    local now=env.now or 0
    for _,c in ipairs(custodies) do
        if c.state=='HELD' and not c.activeJobId and not c.returnJobId then
            if not idleSince[c.id] then
                idleSince[c.id]=now
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
            idleSince[c.id]=nil
        end
    end
end

function Provider.claim(selected,npcId,jobId,env)
    local actor=env and env.actor
    local scopeId=env and env.entry and env.entry.id
    local ok,err=ToolReturnService.startFor(actor,npcId,selected.custodyId,jobId,scopeId)
    if ok then
        idleSince[selected.custodyId]=nil
        return 'STARTED'
    end
    return err or 'TOOL_RETURN_FAILED'
end

function Provider.reconcile()
    local deadKeys={}
    for cid,_ in pairs(idleSince) do
        local c=Store.custodyByItem and Store.custodyByItem(cid)
        if not c or c.state~='HELD' or c.activeJobId or c.returnJobId then
            deadKeys[#deadKeys+1]=cid
        end
    end
    for _,cid in ipairs(deadKeys) do idleSince[cid]=nil end
end

function Provider.hasWork()
    return false
end

function Provider.reset()
    idleSince={}
end

return Provider
