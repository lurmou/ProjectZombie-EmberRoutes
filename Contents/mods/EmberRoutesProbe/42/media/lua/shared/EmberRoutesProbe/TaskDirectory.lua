-- Rebuildable offers only; not a second physical-item claim ledger.
local Directory={}
function Directory.new()
    local offers={}
    local api={}
    function api:upsert(key,revision,category,scopeId)
        if type(key)~='string' or key=='' or type(revision)~='number' then return nil,'OFFER_INVALID' end
        local old=offers[key]
        if old and old.jobId then return old end
        if old and revision<old.revision then return nil,'OFFER_CHANGED' end
        local value={key=key,revision=revision,category=category,scopeId=scopeId}
        offers[key]=value return value
    end
    function api:claim(key,revision,npcId,jobId)
        local offer=offers[key]
        if not offer or offer.revision~=revision then return false,'OFFER_CHANGED' end
        if offer.jobId then
            return offer.jobId==jobId and offer.npcId==npcId,'OFFER_ALLOCATED'
        end
        offer.jobId,offer.npcId=jobId,npcId
        return true
    end
    function api:withdraw(key)
        local offer=offers[key]
        if offer and offer.jobId then offer.withdrawn=true else offers[key]=nil end
    end
    function api:release(key,jobId,proof)
        local offer=offers[key]
        if not offer or offer.jobId~=jobId then return false,'OFFER_CHANGED' end
        -- Callers provide confirmed business facts, not a timeout/lease guess.
        if not proof or proof.effects~='KNOWN' or proof.obligationsCleared~=true then return false,'OBLIGATIONS_RETAINED' end
        offers[key]=nil return true
    end
    return api
end
return Directory
