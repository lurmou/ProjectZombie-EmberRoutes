-- Process-local contracts, never world state or another task authority.
local C={}
local definitions={}
function C.register(kind,contract)
    if type(kind)~='string' or kind=='' or type(contract)~='table' then return false,'JOB_CONTRACT_INVALID' end
    if definitions[kind] then return false,'JOB_CONTRACT_EXISTS' end
    definitions[kind]=contract
    return true
end
function C.get(kind) return definitions[kind] end
return C
