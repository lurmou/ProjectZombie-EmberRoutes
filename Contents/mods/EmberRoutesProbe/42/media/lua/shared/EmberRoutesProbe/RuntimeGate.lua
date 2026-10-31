local RuntimeGate = {}

-- Safely inspect engine runtime environment. Returns nil if engine context is missing.
function RuntimeGate.isClient()
    if type(isClient) == 'function' then
        return isClient() == true
    end
    return nil
end

function RuntimeGate.isServer()
    if type(isServer) == 'function' then
        return isServer() == true
    end
    return nil
end

-- Single-player indicates verified local world where neither dedicated server nor client networking is active.
-- If engine functions are absent, it is an unknown/uninitialized environment and MUST return false.
function RuntimeGate.isSinglePlayer()
    if type(isClient) ~= 'function' or type(isServer) ~= 'function' then
        return false
    end
    return isClient() == false and isServer() == false
end

-- Authoritative environment: in single player, the local game is authoritative; in MP, only the dedicated server is.
function RuntimeGate.isAuthoritative()
    if RuntimeGate.isSinglePlayer() then return true end
    if RuntimeGate.isServer() == true then return true end
    return false
end

-- Strictly check if an actor is a valid, living PZ IsoGameCharacter/IsoPlayer/NPC instance.
-- Any mock or object lacking the character contract is rejected in production.
function RuntimeGate.isLiveActor(actor)
    if not actor then return false end
    if type(actor) ~= 'userdata' and type(actor) ~= 'table' then return false end
    if type(actor.isDead) ~= 'function' then return false end
    if actor:isDead() == true then return false end
    return true
end

-- Actor-required execution guard for single-player local world.
function RuntimeGate.canExecute(actor)
    if not RuntimeGate.isSinglePlayer() then return false end
    return RuntimeGate.isLiveActor(actor)
end

local hasFieldOpsCache

function RuntimeGate.resetCache()
    hasFieldOpsCache = nil
end

-- Field operations require PZ native timed action classes (e.g. ISCleanBlood).
-- Headless test environments lacking these engine scripts must safely reject field operations.
function RuntimeGate.hasFieldOperations()
    if hasFieldOpsCache then return true end
    -- Native PZ engine environment: client has loaded ISCleanBlood as a global table
    if type(ISCleanBlood) == 'table' then
        hasFieldOpsCache = true
        return true
    end
    -- Safe headless / test environment probe: check _G.package existence before indexing
    local pkg = _G.package
    if type(pkg) == 'table' then
        if type(pkg.loaded) == 'table' and pkg.loaded['EmberRoutesProbe/FieldOperations'] then
            return true
        end
        if type(pkg.searchpath) == 'function' and type(pkg.path) == 'string'
            and pkg.searchpath('TimedActions/ISCleanBlood', pkg.path) then
            return true
        end
    end
    return false
end

return RuntimeGate
