-- Real business stores + QA fixture; engine inventory and disk boundary substituted.
local world={} local serial=0 local itemId=91000 local actor={}
local items={}
local list={size=function() return #items end,get=function(_,i) return items[i+1] end}
local inventory={getItems=function() return list end,AddItem=function(_,kind)
    itemId=itemId+1 local id=itemId local data={}
    local item={getID=function() return id end,getFullType=function() return kind end,getModData=function() return data end}
    items[#items+1]=item return item
end}
actor.getInventory=function() return inventory end actor.isDead=function() return false end
function getSpecificPlayer() return actor end
function isDebugEnabled() return true end
function isClient() return false end function isServer() return false end
function getRandomUUID() serial=serial+1 return 'qa-'..serial end
ModData={getOrCreate=function() return world end}
local logs={} DebugLog={log=function(msg) logs[#logs+1]=msg end}
local function copy(t) if type(t)~='table' then return t end local out={} for k,v in pairs(t) do out[k]=copy(v) end return out end
local function boot()
    for _,name in ipairs({'ContainerRegistry','TaskJobs','BusinessJobs','LaborStore','LaborSignals'}) do
	package.loaded['EmberRoutesProbe/'..name]=nil
    end
    _G.EmberRoutesB5QaSessionId=nil
    return dofile('tests/pz/B5Acceptance.lua')
end
local Q=boot()
local ok,why=Q.execute(actor,'prepare') assert(ok,why)
assert(world.b5AcceptanceFixture.ready and #items==4)
assert(not Q.execute(actor,'prepare'),'cannot prepare twice or erase existing fixture')
assert(not Q.execute(actor,'verify'),'same runtime cannot count as a cold boot')
local function durable(value,parents)
    local t=type(value)
    assert(t=='table' or t=='string' or t=='boolean' or t=='number' or t=='nil','runtime value escaped into ModData')
    if t=='number' then assert(value==value and math.abs(value)<math.huge) end
    if t~='table' then return end
    parents=parents or {} assert(not parents[value],'cycle escaped into ModData') parents[value]=true
    for k,v in pairs(value) do durable(k,parents) durable(v,parents) end parents[value]=nil
end
durable(world)
local oldCid=world.b5AcceptanceFixture.originalClaimId
for i=1,2 do
    world=copy(world) Q=boot()
    ok,why=Q.execute(actor,'verify') assert(ok,why)
    assert(world.b5AcceptanceFixture.coldBoots==i) durable(world)
    assert(world.taskJobs.byId[world.b5AcceptanceFixture.jobId].claimId~=oldCid)
    assert(not Q.execute(actor,'verify'),'repeat check cannot increment reload counter')
end
-- Fixture must fail if the actual specimen is removed, even if the ledger survived.
world=copy(world) Q=boot() table.remove(items)
assert(not Q.execute(actor,'verify'),'missing physical specimen is not a pass')
assert(world.b5AcceptanceFixture.coldBoots==2)
print('PASS B5 QA fixture: guarded setup, two simulated runtime rebuilds, no same-session shortcut, physical ID check; game/disk NOT RUN')

package.loaded['DebugUIs/DebugContextMenu']=true
package.loaded['EmberRoutesProbe/B5Acceptance']=Q
local menuCalls=0
local parent={addOption=function() menuCalls=menuCalls+1 return {} end,addSubMenu=function() end}
local context={getOptionFromName=function() return {subOption=1} end,getSubMenu=function() return parent end}
DebugContextMenu={doDebugMenu=function() return 'vanilla-result' end}
ISContextMenu={getNew=function() return {addOption=function() menuCalls=menuCalls+1 end} end}
function getText(key) return key end
dofile('tests/pz/ZZB5AcceptanceMenu.lua')
assert(DebugContextMenu.doDebugMenu(0,context,{},true)=='vanilla-result' and menuCalls==0)
assert(DebugContextMenu.doDebugMenu(0,context,{},false)=='vanilla-result' and menuCalls==3)
print('PASS QA menu: native return preserved, test-mode inert, commands only under native Debug parent; native UI NOT RUN')
