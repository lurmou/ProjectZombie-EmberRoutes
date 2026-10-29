-- A boundary is a review opportunity, not an instruction to leave a posture.
-- Only explicitly continuous activities renew; unknown definitions are finite.
local Config=require 'EmberRoutesProbe/LeisureConfig'
-- Installed vanilla Lua uses this global; probe it explicitly for hosts whose
-- global declarations do not include it (including the small test host).
local gamePaused=_G.isGamePaused
local C={}
function C.new(c)
    local kind=c.payload.leisure.activity
    local registry=require 'EmberRoutesProbe/LeisureRegistry'
    local def=registry.get and registry.get(kind)
    local policy=def and def.lifecycle or Config.lifecycle and Config.lifecycle[kind] or {mode='finite'}
    local elapsed,last,nextReview=0,nil,0
    local api={}
    function api.start() elapsed,last,nextReview=0,getTimestampMs(),0 end
    function api.tick()
        local now=getTimestampMs()
        if last then
            local dt=now-last
            -- Pauses/suspended simulation cannot satisfy a dwell on resume.
            if dt>=0 and dt<=1000 and not (gamePaused and gamePaused()) then elapsed=elapsed+dt end
        end
        last=now
    end
    function api.boundary()
        if policy.mode~='continuous' or c.payload.leisure.brief then return true end
        if elapsed<(policy.minimumMs or 20000) or elapsed<nextReview then return false end
        nextReview=elapsed+(policy.reviewMs or 10000)
        local service=require 'EmberRoutesProbe/LeisureService'
        return service.review and service.review(c,elapsed)==true or false
    end
    return api
end
return C
