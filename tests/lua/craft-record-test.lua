-- CraftRecord pure contract test: verify decoupled schema and resource extraction without BusinessJobs
package.path = "Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;" .. package.path
package.loaded['EmberRoutesProbe/BusinessJobs']=nil

local Record=require 'EmberRoutesProbe/CraftRecord'

-- Assert that loading CraftRecord does NOT load BusinessJobs
if package.loaded['EmberRoutesProbe/BusinessJobs']~=nil then
    error('CraftRecord must not load BusinessJobs')
end

-- 1. Format 1 valid check
local validF1={
    format=1,
    id='craft-1',
    npcId='npc-1',
    requester='player',
    benchId='bench-1',
    generation=0,
    materialId=101,
    toolId=102,
    state='RUNNING',
    phase='CRAFTING',
    released=false,
    outputIds={201}
}
if not Record.valid('npc-1',validF1) then error('validF1 should pass') end
if Record.valid('npc-other',validF1) then error('mismatched npcId should fail') end

local resF1=Record.resources(validF1)
local expectedKeys={'item:101','item:102','craft-surface:bench-1','item:201'}
if #resF1~=#expectedKeys then error('resF1 count mismatch') end
for i,k in ipairs(expectedKeys) do
    if resF1[i]~=k then error('resF1 key mismatch: '..tostring(resF1[i])) end
end

-- 2. Format 2 valid check
local validF2={
    format=2,
    id='craft-2',
    npcId='npc-2',
    requester='player',
    benchId='bench-2',
    generation=1,
    materialId=301,
    toolId=302,
    state='DONE',
    phase='DONE',
    released=true,
    outputIds={401},
    source='source-box',
    settlementId='settlement-1',
    toolFromNpc=true
}
if not Record.valid('npc-2',validF2) then error('validF2 should pass') end

-- 3. Invalidation checks
local invalidId={format=1,id=123,npcId='npc-1',requester='player',benchId='bench-1',generation=0,materialId=101,toolId=102,state='RUNNING',phase='CRAFTING',released=false,outputIds={201}}
if Record.valid('npc-1',invalidId) then error('non-string id should fail') end

local sameToolMaterial={format=1,id='c3',npcId='npc-1',requester='player',benchId='bench-1',generation=0,materialId=101,toolId=101,state='RUNNING',phase='CRAFTING',released=false,outputIds={201}}
if Record.valid('npc-1',sameToolMaterial) then error('materialId == toolId should fail') end

-- 4. validateAll checks
local allRecords={
    ['npc-1']=validF1,
    ['npc-2']=validF2
}
if not Record.validateAll(allRecords) then error('validateAll should return true for valid records') end

allRecords['bad']=invalidId
if Record.validateAll(allRecords) then error('validateAll should return false for invalid record') end

print('PASS CraftRecord pure contract decoupled test')
