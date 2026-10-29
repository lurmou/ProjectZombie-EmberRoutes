local root={} local seq=0 local md={}
local actor={isDead=function() return false end,getModData=function() return md end}
local entry={id='home',factionId='f',revision=1,areas={{x=0,y=0,w=30,h=30}}}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() seq=seq+1 return 'id'..seq end}
package.loaded['EmberRoutesProbe/SettlementLedger']={data=function() return {factionId='f',entries={home=entry}} end,
    authorized=function() return true end,view=function() error('NPC eligibility must not use player geometry') end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function() return {} end}
local M=require 'EmberRoutesProbe/MembershipService'
M.newWorld()
local function settle(id)
    M.register(id) M.request(actor,id,{requestId='settle'..id,kind='SETTLE',settlementId='home',expectedRevision=1})
    M.advance(id,actor,{},false)
end
settle('a') settle('b')
local Social=require 'EmberRoutesProbe/SocialCoordinator'
local point={x=2,y=2,z=0}
Social.advertise('a',entry,point,0) Social.advertise('b',entry,{x=4,y=2,z=0},0)
local pair=Social.invite('a',entry,0,function(a,b) return a,b end)
assert(pair and Social.accept(pair,'a','attemptA',1))
local old=M.view('b').revision
M.request(actor,'b',{requestId='waitB',kind='WAIT',expectedRevision=old})
assert(not Social.accept(pair,'b','attemptB',2),'accepted command immediately invalidates prior invitation')
assert(not Social.view(pair,'a','attemptA',2),'both sides reject stale pair before effects')
assert(M.check('b','LEISURE',point,old).reason=='STALE_MEMBERSHIP')
assert(M.check('b','RECOVERY',point).allowed,'returning borrowed books remains eligible during command handoff')
M.advance('b',actor,{},false)
assert(M.check('b','WORK',point).reason=='CONTEXT_WAIT')
Social.withdraw('b') assert(Social.release(pair,'a','attemptA',true))
assert(M.check('a','STUDY',point).allowed and M.check('a','LEISURE',point).allowed)
assert(not M.check('a','WORK',{x=3,y=3,scopeId='other'}).allowed)
for _,name in ipairs({'CachedList','Theme','Text','StatusVisual'}) do package.loaded['EmberRoutesProbe/UI/'..name]={} end
local Cards=require 'EmberRoutesProbe/UI/OrderMonitorCards'
local row={id='job',membership=M.view('a')} local signature=Cards.signature(row)
row.membership.context='WAIT' row.membership.revision=row.membership.revision+1
assert(Cards.signature(row)~=signature,'monitor caches refresh when macro intent changes without a body-mode change')
print('Membership consumers: stable scopes, stale social invites, independent custody recovery')
