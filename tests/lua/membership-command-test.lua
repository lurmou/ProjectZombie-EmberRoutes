local root={} local tick=0 local owns=false local character={}
local actor={isDead=function() return false end,getModData=function() return character end}
local npc={getX=function() return 2 end,getY=function() return 2 end,getZ=function() return 0 end}
local entries={home={id='home',name='Home',factionId='f',revision=1,areas={{x=0,y=0,w=10,h=10}}},
    other={id='other',name='Other',factionId='f',revision=1,areas={{x=20,y=20,w=10,h=10}}}}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() tick=tick+1 return 'id'..tick end}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return {entries=entries,factionId='f'} end,authorized=function() return true end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) return {id=id,handle=npc} end,valid=function() return true end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {owns=function() return owns end,accepting=function() return true end,
    stop=function() return true end,status=function() return nil end} end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
local S=require 'EmberRoutesProbe/MembershipService'
assert(not S.load() and not root.npcMembership,'old roots not silently upgraded')
assert(S.newWorld()) assert(S.register('a'))
local a=S.view('a') assert(a.context=='WAIT' and not a.settlementId)
local function command(kind,scope)
    a=S.view('a') tick=tick+1
    return S.request(actor,'a',{requestId='r'..tick,expectedRevision=a.revision,kind=kind,settlementId=scope})
end
local q=command('SETTLE','home') assert(q.state=='PENDING')
assert(not S.check('a','WORK',{x=2,y=2}).allowed)
assert(S.advance('a',actor,{},false))
a=S.view('a') assert(a.context=='SETTLEMENT' and a.settlementId=='home')
local members=S.members('home') assert(#members==1 and members[1]=='a') members[1]='foreign'
assert(S.members('home')[1]=='a','settlement roster index returns detached identities')
local copy=S.view('a') copy.context='FOLLOW' assert(S.view('a').context=='SETTLEMENT')
q=command('FOLLOW')
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
