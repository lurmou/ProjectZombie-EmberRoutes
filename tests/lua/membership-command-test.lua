-- This host fixture has no world furniture; model the no-bed commit explicitly.
package.loaded['EmberRoutesProbe/Settlement/MembershipBeds']={observe=function() return true end,settle=function(row) row.bedReason='BED_NONE' return true end,release=function() return true end,reconcile=function() end}
local root={} local tick=0 local owns=false local character={}
local actor={isDead=function() return false end,getModData=function() return character end}
local npc={getX=function() return 2 end,getY=function() return 2 end,getZ=function() return 0 end}
local entries={home={id='home',name='Home',factionId='f',revision=1,areas={{x=0,y=0,w=10,h=10}}},
    other={id='other',name='Other',factionId='f',revision=1,areas={{x=20,y=20,w=10,h=10}}}}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() tick=tick+1 return 'id'..tick end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={data=function() return {entries=entries,factionId='f'} end,authorized=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/Driver']={bindId=function(_,id) return {id=id,handle=npc} end,valid=function() return true end}
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {owns=function() return owns end,accepting=function() return true end,
    stop=function() return true end,status=function() return nil end} end}
package.loaded['EmberRoutesProbe/Work/LaborSignals']={changed=function() end}
local S=require 'EmberRoutesProbe/Settlement/MembershipService'
assert(not S.load() and not root.npcMembership,'old roots not silently upgraded')
assert(S.newWorld()) assert(S.register('a'))
local a=S.view('a') assert(a.context=='WAIT' and not a.settlementId)
local function command(kind,scope,slot)
    a=S.view('a') tick=tick+1
    return S.request(actor,'a',{requestId='r'..tick,expectedRevision=a.revision,kind=kind,settlementId=scope,followSlot=slot})
end
local q=command('SETTLE','home') assert(q.state=='PENDING')
assert(not S.check('a','WORK',{x=2,y=2}).allowed)
assert(S.advance('a',actor,{},false))
a=S.view('a') assert(a.context=='SETTLEMENT' and a.settlementId=='home')
local members=S.members('home') assert(#members==1 and members[1]=='a') members[1]='foreign'
assert(S.members('home')[1]=='a','settlement roster index returns detached identities')
local copy=S.view('a') copy.context='FOLLOW' assert(S.view('a').context=='SETTLEMENT')
q=command('FOLLOW',nil,0)
assert(not S.advance('a',actor,{},true),'body must stop before commit')
assert(S.advance('a',actor,{},false)) assert(S.view('a').context=='FOLLOW' and S.view('a').settlementId=='home')
q=command('TRANSFER','other')
assert(not S.advance('a',actor,{{kind='RETURN_ORIGINALS',count=1}},false))
assert(S.view('a').settlementId=='home' and S.view('a').reason=='OBLIGATION_PENDING')
assert(S.advance('a',actor,{},false)) assert(S.view('a').settlementId=='other')
assert(#S.members('home')==0 and S.members('other')[1]=='a','transfer invalidates the shared roster index')
local revision=S.view('a').revision
assert(S.request(actor,'a',{requestId=q.requestId,expectedRevision=revision-2,kind='TRANSFER',settlementId='other'}).state=='COMMITTED')
assert(S.request(actor,'a',{requestId='stale',expectedRevision=revision-1,kind='WAIT'}).reason=='STALE_MEMBERSHIP')
command('UNASSIGN') S.advance('a',actor,{},false)
assert(not S.view('a').settlementId and S.view('a').factionId=='f')
assert(not S.check('a','LEISURE',{x=2,y=2}).allowed)
assert(S.check('a','RECOVERY').allowed)
command('SETTLE','home') S.advance('a',actor,{},false)
local pending=command('TRANSFER','other') local waiting=S.view('a')
local cancelled=S.cancel(actor,'a',pending.requestId,waiting.revision)
assert(cancelled.state=='CANCELLED' and S.view('a').settlementId=='home' and not S.view('a').pending)
assert(not S.advance('a',actor,{},false),'cancelled request cannot later commit')
local old=S.view('a').revision
for i=1,140 do command('WAIT') S.advance('a',actor,{},false) end
assert(#root.npcMembership.receiptOrder<=128,'technical history stays bounded')
assert(S.request(actor,'a',{requestId='expired',expectedRevision=old,kind='WAIT'}).reason=='STALE_MEMBERSHIP')
print('Membership commands: pending, custody, idempotency, stale revisions, detached views')
-- Contract change: squad slots survive WAIT/RETURN; only DISMISS/retire releases them.
assert(S.view('a').squadSlot==0 and #S.squad(actor)==1)
command('DISMISS') assert(S.advance('a',actor,{},false))
assert(#S.squad(actor)==0 and S.view('a').settlementId=='home')
-- Explicit slots: live and pending ownership, retries, release, and read-only load admission.
for _,id in ipairs({'b','c','d'}) do assert(S.register(id)) end
local function slotCommand(id,slot,who,kind,requestId)
    tick=tick+1 local row=S.view(id)
    return S.request(who or actor,id,{kind=kind or 'FOLLOW',followSlot=slot,
        expectedRevision=row.revision,requestId=requestId or ('slot-'..tick)})
end
local revision=S.view('a').revision
for _,slot in ipairs({-1,3,0.5,math.huge,0/0}) do
    assert(slotCommand('a',slot).reason=='INVALID_FOLLOW_SLOT')
end
assert(slotCommand('a',nil).reason=='INVALID_FOLLOW_SLOT')
assert(S.view('a').revision==revision,'invalid slot cannot mutate the row')
local accepted=slotCommand('a',1,nil,nil,'slot-a')
assert(accepted.state=='PENDING' and S.view('a').pending.followSlot==1)
assert(slotCommand('b',1).reason=='SLOT_TAKEN','pending command reserves slot')
assert(slotCommand('b',0).state=='PENDING' and slotCommand('c',2).state=='PENDING')
for slot=0,2 do assert(slotCommand('d',slot).reason=='SLOT_TAKEN','three occupied slots bound the first delivery') end
assert(slotCommand('a',1,nil,nil,'slot-a').state=='PENDING','same request is idempotent')
assert(slotCommand('a',0,nil,nil,'slot-a').reason=='REQUEST_CONFLICT','request ID cannot change slots')
assert(S.load(),'valid pending commands survive load')
for _,id in ipairs({'c','b','a'}) do assert(S.advance(id,actor,{},false)) end
assert(S.followSlot('a',actor,S.view('a').revision)==1)
assert(S.followSlot('a',actor,S.view('a').revision-1)==nil,'old member revision cannot read a new grant slot')
assert(slotCommand('a',1,nil,nil,'slot-a').state=='COMMITTED','committed retry keeps the same slot')
assert(slotCommand('a',2,nil,nil,'slot-a').reason=='REQUEST_CONFLICT')
local foreignMd={}
local foreignActor={isDead=function() return false end,getModData=function() return foreignMd end}
assert(slotCommand('d',1,foreignActor).state=='PENDING','different leaders have independent slots')
assert(S.advance('d',foreignActor,{},false) and S.load())
assert(S.followSlot('d',actor,S.view('d').revision)==nil,'leader identity gates restored slot')
assert(slotCommand('a',nil,nil,'WAIT').state=='PENDING')
assert(slotCommand('d',1).reason=='SLOT_TAKEN','old active slot stays held until WAIT commits')
assert(S.advance('a',actor,{},false) and S.view('a').followSlot==nil)
assert(S.view('a').squadSlot==1 and #S.squad(actor)==3,'WAIT preserves roster and slot')
assert(slotCommand('b',1).reason=='SLOT_TAKEN','WAIT does not release the persistent slot')
assert(slotCommand('a',nil,nil,'DISMISS').state=='PENDING')
assert(not S.advance('a',actor,{{kind='RETURN_ORIGINALS'}},false),'dismiss cannot bypass unresolved originals')
assert(S.advance('a',actor,{},false) and #S.squad(actor)==2)
assert(slotCommand('b',1).state=='PENDING','slot switch reserves new slot')
assert(slotCommand('d',0).reason=='SLOT_TAKEN','switch keeps the old active slot until commit')
assert(S.advance('b',actor,{},false))
local switched=slotCommand('d',0)
assert(switched.state=='PENDING')
assert(S.cancel(actor,'d',switched.requestId,S.view('d').revision).state=='CANCELLED')
assert(S.view('d').leaderId==S.character(foreignActor) and S.view('d').followSlot==1,'cancel preserves prior leader and slot')
local b=root.npcMembership.byNpc.b
b.followSlot=nil local original=root.npcMembership
assert(not S.load() and root.npcMembership==original and b.followSlot==nil,'missing FOLLOW slot is rejected without repair')
local blockedRevision=b.revision
assert(slotCommand('b',0).reason=='MEMBERSHIP_FORMAT_INVALID' and b.followSlot==nil
    and b.revision==blockedRevision,'a new command cannot silently repair an unsupported row')
assert(not S.transition('b',b.revision,'WAIT') and b.context=='FOLLOW','runtime transition cannot repair an unsupported row')
b.followSlot=1
local savedSquad=b.squadSlot b.squadSlot=nil
assert(not S.load() and b.squadSlot==nil,'missing squad contract is rejected without repair')
b.squadSlot=savedSquad
local c=root.npcMembership.byNpc.c c.followSlot=1 c.squadSlot=1
assert(not S.load() and c.followSlot==1,'duplicate slots are rejected without reassignment')
c.followSlot=2 c.squadSlot=2
assert(S.load())
local pendingSlot=slotCommand('a',0)
local p=root.npcMembership.byNpc.a.pendingCommand
p.followSlot=nil assert(not S.load() and p.followSlot==nil,'missing pending slot is not defaulted')
p.followSlot=1 assert(not S.load(),'pending collision with active member rejects load')
p.followSlot=0 assert(S.cancel(actor,'a',pendingSlot.requestId,S.view('a').revision).state=='CANCELLED')
assert(S.transition('b',S.view('b').revision,'RETURN') and S.view('b').followSlot==nil,'runtime return clears active slot')
assert(S.view('b').squadSlot==1 and #S.squad(actor)==2,'RETURN keeps the persistent roster')
S.retire('d',false)
assert(S.view('d').followSlot==nil and S.load(),'retirement releases slot while retaining unresolved member')
print('PASS explicit slot ownership, retry identity, release, leader scope, and strict load checks')
return {service=S,root=root,actor=actor}
