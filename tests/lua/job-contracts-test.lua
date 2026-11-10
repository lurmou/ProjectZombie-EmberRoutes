-- JobContracts errorCodes: every contract declares the codes its callbacks
-- can emit; registration without that declaration is refused loudly.
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
local n=0 local function check(ok,label) n=n+1 assert(ok,label) end
local function rejected(contract,why)
    local ok,code=Contracts.register('REJECT_'..n,contract)
    return not ok and code=='JOB_CONTRACT_ERROR_CODES_REQUIRED'
end
-- Version gate: a contract without schemaVersion, or with a wrong one, is
-- refused with JOB_CONTRACT_SCHEMA_VERSION before any other check.
local function versionRejected(contract)
    local ok,code=Contracts.register('VERSION_'..n,contract)
    return not ok and code=='JOB_CONTRACT_SCHEMA_VERSION'
end
check(versionRejected({validate=function() return true end,errorCodes={}}),'missing schemaVersion refused')
check(versionRejected({schemaVersion=2,validate=function() return true end,errorCodes={}}),'schemaVersion 2 refused')
check(versionRejected({schemaVersion='1',validate=function() return true end,errorCodes={}}),'non-number schemaVersion refused')
check(versionRejected({schemaVersion=0,validate=function() return true end,errorCodes={}}),'schemaVersion 0 refused')
check(rejected({schemaVersion=1,validate=function() return true end}),'missing errorCodes refused')
check(rejected({schemaVersion=1,validate=function() return true end,errorCodes='NONE'}),'non-table errorCodes refused')
check(rejected({schemaVersion=1,validate=function() return true end,errorCodes={BAD_CODE=''}}),'empty code meaning refused')
check(rejected({schemaVersion=1,validate=function() return true end,errorCodes={['']='x'}}),'empty code refused')
check(rejected({schemaVersion=1,validate=function() return true end,transferReason='UNDECLARED',errorCodes={}}),
    'transferReason outside errorCodes refused')
check(rejected({schemaVersion=1,transition=function() return false,'SOME_CODE' end,errorCodes={}}),
    'transition without a declared code refused')
check(Contracts.register('DECLARED',{schemaVersion=1,validate=function() return true end,
    transition=function() return false,'DECLARED_BAD' end,
    errorCodes={DECLARED_BAD='declared transition failure'}}),
    'normal registration with codes accepted')
check(Contracts.get('DECLARED').errorCodes.DECLARED_BAD=='declared transition failure',
    'declared code meaning retained')
check(Contracts.get('DECLARED').schemaVersion==1 and Contracts.SCHEMA_VERSION==1,
    'registered contract keeps schemaVersion 1')
check(Contracts.register('BOOLEAN_ONLY',{schemaVersion=1,validate=function() return true end,errorCodes={}}),
    'boolean-only contract declares an empty table')
local ok,code=Contracts.register('DECLARED',{schemaVersion=1,validate=function() return true end,errorCodes={}})
check(not ok and code=='JOB_CONTRACT_EXISTS','duplicate registration still rejected')
ok,code=Contracts.register('',{errorCodes={}})
check(not ok and code=='JOB_CONTRACT_INVALID','invalid kind still rejected')

-- Built-in contracts: all six declare errorCodes, and every code the
-- callbacks actually emit is among them.
require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
for _,kind in ipairs({'COOKING','FIELD_WORK','ACTIVITY','SELF_CARE','CRAFT','HAUL'}) do
    local c=Contracts.get(kind)
    check(type(c)=='table' and type(c.errorCodes)=='table',kind..' declares errorCodes')
    check(c.schemaVersion==1,kind..' declares schemaVersion 1')
end
check(Contracts.get('COOKING').errorCodes.COOKING_TRANSITION_INVALID~=nil
    and Contracts.get('COOKING').errorCodes[Contracts.get('COOKING').transferReason]~=nil,
    'COOKING declares its transition code and its transferReason')
check(Contracts.get('CRAFT').errorCodes.CRAFT_TRANSITION_INVALID~=nil
    and Contracts.get('CRAFT').errorCodes.CRAFT_SCOPE_RECONCILE_REQUIRED~=nil,
    'CRAFT declares its transition and scope codes')
check(Contracts.get('HAUL').errorCodes.HAUL_TRANSITION_INVALID~=nil,
    'HAUL declares its transition code')
check(next(Contracts.get('FIELD_WORK').errorCodes)==nil
    and next(Contracts.get('ACTIVITY').errorCodes)==nil
    and next(Contracts.get('SELF_CARE').errorCodes)==nil,
    'boolean-only builtins declare empty errorCodes')

-- LaborRecovery requires the contract to carry errorCodes as well.
local Recovery=require 'EmberRoutesProbe/Work/LaborRecovery'
check(Contracts.register('RECOVERY_OK',{schemaVersion=1,validate=function() return true end,errorCodes={}}),
    'recovery fixture contract registers')
local restored=false
Recovery.register('RECOVERY_OK',function() restored=true end)
Recovery.restore({current={taskJobs={byId={}}}})
check(restored,'recovery runs for a contract with errorCodes')
check(Contracts.register('RECOVERY_GATE',{schemaVersion=1,validate=function() return true end,errorCodes={}}),
    'recovery gate fixture contract registers')
Contracts.get('RECOVERY_GATE').errorCodes=nil
ok,code=pcall(Recovery.register,'RECOVERY_GATE',function() end)
check(not ok and type(code)=='string' and code:find('RECOVERY_CONTRACT_ERROR_CODES_REQUIRED',1,true)~=nil,
    'recovery refuses a contract stripped of errorCodes')
print('PASS '..n..' job contract errorCodes checks')
