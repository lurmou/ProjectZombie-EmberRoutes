-- Process-local contracts, never world state or another task authority.
-- Every contract declares the codes its callbacks can emit, in errorCodes
-- (code -> what it means). A contract whose callbacks return only booleans
-- declares an empty table: the declaration itself is mandatory, the content
-- mirrors reality, no code is invented. Registration rejects a missing or
-- malformed errorCodes table with JOB_CONTRACT_ERROR_CODES_REQUIRED; a
-- transferReason must be one of the declared codes, and a contract with a
-- transition callback must declare at least one code (JobStore propagates
-- the transition's second return value verbatim, so an undeclared code
-- would surface with no documented meaning).
-- Datapack pack_format analogy: every contract table carries schemaVersion
-- and registration refuses a table whose version is not C.SCHEMA_VERSION
-- (JOB_CONTRACT_SCHEMA_VERSION), never silently running an old table.
local C={SCHEMA_VERSION=1}
local definitions={}
local function validErrorCodes(contract)
    local codes=contract.errorCodes
    if type(codes)~='table' then return false end
    for code,meaning in pairs(codes) do
        if type(code)~='string' or code=='' or type(meaning)~='string' or meaning=='' then return false end
    end
    if contract.transferReason~=nil and codes[contract.transferReason]==nil then return false end
    -- Empty-check through pairs. The Kahlua BaseLib this game ships registers
    -- 18 globals and `next` is not one of them: `next(codes)` evaluated to a
    -- nil callee, aborted this module's load and took JobStore with it (every
    -- later Registry.data() then failed on a nil Jobs module). Same idiom and
    -- same semantics as JobStore.empty / ModDataTemplates.empty.
    if contract.transition~=nil then
        local declared=false
        for _ in pairs(codes) do declared=true break end
        if not declared then return false end
    end
    return true
end
function C.register(kind,contract)
    if type(kind)~='string' or kind=='' or type(contract)~='table' then return false,'JOB_CONTRACT_INVALID' end
    if contract.schemaVersion~=C.SCHEMA_VERSION then return false,'JOB_CONTRACT_SCHEMA_VERSION' end
    if definitions[kind] then return false,'JOB_CONTRACT_EXISTS' end
    if not validErrorCodes(contract) then return false,'JOB_CONTRACT_ERROR_CODES_REQUIRED' end
    definitions[kind]=contract
    return true
end
function C.get(kind) return definitions[kind] end
return C
