-- P1 pilot 6/15: schema version gate (Minecraft datapack pack_format
-- localized): JobContracts, NeedsPolicy and LeisureConfig each carry
-- schemaVersion=1; a table with a wrong version is refused with an
-- explicit code at its load entry, never silently used. Correct-version
-- behaviour is pinned unchanged.
-- Run from the repo root: lua tests/lua/p1-pilot-schema-version-test.lua
package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local n=0 local function check(v,s) n=n+1 assert(v,s) end

-- (1) JobContracts: register() is the single load entry.
local Contracts=require 'EmberRoutesProbe/Kernel/JobContracts'
check(Contracts.SCHEMA_VERSION==1,'JobContracts SCHEMA_VERSION is 1')
local ok,code=Contracts.register('SCHEMA_MISSING',{validate=function() return true end,errorCodes={}})
check(not ok and code=='JOB_CONTRACT_SCHEMA_VERSION','missing schemaVersion refused with code')
ok,code=Contracts.register('SCHEMA_FUTURE',{schemaVersion=2,validate=function() return true end,errorCodes={}})
check(not ok and code=='JOB_CONTRACT_SCHEMA_VERSION' and Contracts.get('SCHEMA_FUTURE')==nil,
    'schemaVersion 2 refused with code and not stored')
ok,code=Contracts.register('SCHEMA_STRING',{schemaVersion='1',validate=function() return true end,errorCodes={}})
check(not ok and code=='JOB_CONTRACT_SCHEMA_VERSION','non-number schemaVersion refused with code')
check(Contracts.register('SCHEMA_OK',{schemaVersion=1,validate=function() return true end,errorCodes={}})
    and Contracts.get('SCHEMA_OK').schemaVersion==1,'schemaVersion 1 registers and is kept')
require('EmberRoutesProbe/Kernel/BuiltinJobContracts').install()
for _,kind in ipairs({'COOKING','FIELD_WORK','ACTIVITY','SELF_CARE','CRAFT','HAUL'}) do
    check(Contracts.get(kind).schemaVersion==1,'builtin '..kind..' declares schemaVersion 1')
end

-- (2) NeedsPolicy: the module table is the table; checkSchema is its load
-- gate and the module self-checks with it at load (assert at file end).
local Policy=require 'EmberRoutesProbe/SelfCare/NeedsPolicy'
check(Policy.SCHEMA_VERSION==1 and Policy.schemaVersion==1,'NeedsPolicy declares schemaVersion 1')
check(Policy.checkSchema(Policy),'correct NeedsPolicy table passes its own gate')
local function tamperedPolicy(version)
    local t={} for k,v in pairs(Policy) do t[k]=v end t.schemaVersion=version return t
end
ok,code=Policy.checkSchema(tamperedPolicy(2))
check(ok==nil and code=='NEEDS_POLICY_SCHEMA_VERSION','NeedsPolicy schemaVersion 2 refused with code')
ok,code=Policy.checkSchema(tamperedPolicy(nil))
check(ok==nil and code=='NEEDS_POLICY_SCHEMA_VERSION','NeedsPolicy missing schemaVersion refused with code')
ok,code=Policy.checkSchema('not-a-table')
check(ok==nil and code=='NEEDS_POLICY_SCHEMA_VERSION','NeedsPolicy non-table refused with code')
ok,code=pcall(function() assert(Policy.checkSchema(tamperedPolicy(2)),'NEEDS_POLICY_SCHEMA_VERSION') end)
check(not ok and type(code)=='string' and code:find('NEEDS_POLICY_SCHEMA_VERSION',1,true)~=nil,
    'load-time self-check raises the code for a wrong version')
check(Policy.EMERGENCY.HUNGER==0.90 and Policy.STEEPENING.TIER2_MULT==3,
    'NeedsPolicy tuning unchanged at correct version')
check(Policy.choose({hunger=0.9,thirst=0.1,fatigue=0.1,endurance=0.9},nil,{safe=true},
    {EAT=true,DRINK=true,REST=true,SLEEP=true})=='EAT','NeedsPolicy choose unchanged at correct version')

-- (3) LeisureConfig: same shape; the literal stays pure data, the gate
-- lives between the literal and return.
local Config=require 'EmberRoutesProbe/Leisure/LeisureConfig'
check(Config.SCHEMA_VERSION==1 and Config.schemaVersion==1,'LeisureConfig declares schemaVersion 1')
check(Config.checkSchema(Config),'correct LeisureConfig table passes its own gate')
local c2={} for k,v in pairs(Config) do c2[k]=v end c2.schemaVersion=99
ok,code=Config.checkSchema(c2)
check(ok==nil and code=='LEISURE_CONFIG_SCHEMA_VERSION','LeisureConfig schemaVersion 99 refused with code')
ok,code=Config.checkSchema({})
check(ok==nil and code=='LEISURE_CONFIG_SCHEMA_VERSION','LeisureConfig missing schemaVersion refused with code')
ok,code=pcall(function() assert(Config.checkSchema(c2),'LEISURE_CONFIG_SCHEMA_VERSION') end)
check(not ok and type(code)=='string' and code:find('LEISURE_CONFIG_SCHEMA_VERSION',1,true)~=nil,
    'load-time self-check raises the code for a wrong version')
check(Config.gates.health==75 and Config.repeatWeightFactor==0.15 and Config.fitnessMinutes==60,
    'LeisureConfig values unchanged at correct version')

print('PASS '..n..' schema version gate checks')
