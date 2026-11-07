-- This host fixture has no world furniture; model the no-bed commit explicitly.
package.loaded['EmberRoutesProbe/Settlement/MembershipBeds']={observe=function() return true end,settle=function(row) row.bedReason='BED_NONE' return true end,release=function() return true end,reconcile=function() end}
local root={} local uuid=0 local calls=0 local checkpoints={}
local entry={id='home',factionId='f',revision=1,areas={{x=0,y=0,w=10,h=10}}}
local ledger={entries={},factionId='f'} local md={}
local actor={isDead=function() return false end,getModData=function() return md end}
ModData={getOrCreate=function(key) checkpoints[key]=checkpoints[key] or {} return checkpoints[key] end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() uuid=uuid+1 return 'id'..uuid end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={data=function() return ledger end,authorized=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function() return {} end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() calls=calls+1 end}
local S=require 'EmberRoutesProbe/Settlement/MembershipService'
local L=require 'EmberRoutesProbe/Settlement/MembershipLifecycle'
checkpoints['EmberRoutes/NpcCheckpoints/v2']={snapshot={format=2,records={old={}}}}
assert(not L.newWorld() and not root.npcMembership,'replacement character cannot upgrade old NPC saves')
checkpoints['EmberRoutes/NpcCheckpoints/v2'].snapshot.records={}
assert(L.newWorld(),'empty native checkpoint header alone is not an old NPC save')
assert(S.register('a')) ledger.entries.home=entry
S.request(actor,'a',{requestId='settle',kind='SETTLE',settlementId='home',expectedRevision=1})
assert(S.load() and S.view('a').pending.requestId=='settle','pending intent survives reload validation')
assert(S.advance('a',actor,{},false))
local before=S.view('a') assert(S.load())
assert(S.view('a').revision==before.revision and S.view('a').settlementId=='home')
S.request(actor,'a',{requestId='follow',kind='FOLLOW',expectedRevision=before.revision,followSlot=2})
S.advance('a',actor,{},false)
local leader=S.view('a').leaderId
assert(S.load() and S.followSlot('a',actor,S.view('a').revision)==2,'normal reload reads the explicit slot from membership')
assert(leader==S.character(actor),'same character retains scalar identity')
local followRevision=S.view('a').revision
S.request(actor,'a',{requestId='wait-roster',kind='WAIT',expectedRevision=followRevision})
assert(S.advance('a',actor,{},false))
local waiting=S.view('a')
assert(S.load() and S.view('a').revision==waiting.revision and S.view('a').squadSlot==2
    and S.squad(actor)[1]=='a' and S.view('a').followSlot==nil,'WAIT reload retains only the persistent squad slot without rewriting the record')
md={} assert(S.character(actor)~=leader,'new character does not inherit old follow target')
root.npcMembership.format=77 local saved=root.npcMembership
assert(not S.load() and not S.newWorld() and root.npcMembership==saved,'unknown format retained, never reset')
root.npcMembership.format=1
S.retire('a',false) assert(S.view('a').retired,'unsettled dead member retained')
S.retire('a',true) assert(not S.view('a'),'settled member may be retired')
-- Use the actual engine new-world event contract, not the respawn event.
local callbacks={}
Events={OnInitGlobalModData={Add=function(fn) callbacks.init=fn end},OnNewGame={Add=function(fn) callbacks.character=fn end},
    OnCharacterDeath={Add=function(fn) callbacks.death=fn end}}
local probe={} package.loaded['EmberRoutesProbe/Kernel/Boot']=probe
package.loaded['EmberRoutesProbe/Settlement/MembershipRuntime']={install=function() end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
root={} checkpoints['EmberRoutes/Work/v1']=root
L.install() callbacks.init(false) callbacks.character(actor)
assert(not root.npcMembership,'loading an old world and creating a new character do not initialize membership')
callbacks.init(true) assert(root.npcMembership and S.load(),'engine new-world event initializes the current engine root')
S.register('dead')
instanceof=function(value,kind) return value=='managed' and kind=='IsoPlayer' end
EmberRoutesProbeJava={ownedCarrierId=function(value) return value=='managed' and 'dead' or '' end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {stop=function() return true end} end}
callbacks.death('zombie') assert(not S.view('dead').retired,'unmanaged deaths cannot retire a member')
callbacks.death('managed') assert(S.view('dead').retired,'dead native lifecycle identity retains unresolved member')
print('Membership lifecycle: old worlds rejected, pending retained, stable/new character identity, bounded retirement')
