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
local C={}
local definitions={}
local function validErrorCodes(contract)
    local codes=contract.errorCodes
    if type(codes)~='table' then return false end
    for code,meaning in pairs(codes) do
        if type(code)~='string' or code=='' or type(meaning)~='string' or meaning=='' then return false end
    end
    if contract.transferReason~=nil and codes[contract.transferReason]==nil then return false end
    if contract.transition~=nil and next(codes)==nil then return false end
    return true
end
function C.register(kind,contract)
    if type(kind)~='string' or kind=='' or type(contract)~='table' then return false,'JOB_CONTRACT_INVALID' end
    if definitions[kind] then return false,'JOB_CONTRACT_EXISTS' end
    if not validErrorCodes(contract) then return false,'JOB_CONTRACT_ERROR_CODES_REQUIRED' end
    definitions[kind]=contract
    return true
end
function C.get(kind) return definitions[kind] end
return C
