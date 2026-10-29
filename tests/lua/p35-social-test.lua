package.loaded['EmberRoutesProbe/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
local root={} local seq=0
local home={id='home'}
package.loaded['EmberRoutesProbe/MembershipService']={view=function(id)
    if id=='a' or id=='b' then return {npcId=id,context='SETTLEMENT',settlementId='home',revision=1} end
end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,id=function() seq=seq+1 return 'pair'..seq end}
local S=require 'EmberRoutesProbe/SocialCoordinator'
S.advertise('a',home,{x=0,y=0,z=0},0) S.advertise('b',home,{x=1,y=0,z=0},0)
local function geometry(a,b) return a,b end
local id=S.invite('a',home,1,geometry)
assert(id and S.invite('b',home,1,geometry)==id)
assert(S.accept(id,'a','attemptA',2) and S.accept(id,'b','attemptB',2))
assert(not S.accept(id,'b','foreign',2))
assert(S.view(id,'a','attemptA',3).ready)
assert(S.arrive(id,'a','attemptA',1)) assert(S.view(id,'a','attemptA',3).phase=='APPROACH')
assert(S.arrive(id,'b','attemptB',1)) assert(S.view(id,'a','attemptA',3).phase=='CONVERSE')
assert(not S.cancel(id,'a','foreign')) assert(S.cancel(id,'a','attemptA'))
assert(not S.view(id,'b','attemptB',4))
assert(S.release(id,'a','attemptA',true)) assert(not S.release(id,'b','attemptB',false))
assert(S.release(id,'b','attemptB',true))
root={} assert(not S.pending('a'))
print('P3.5 paired intent: unique acceptance, arrival barrier, stale fences, separate release')

S.advertise('a',home,{x=0,y=0,z=0},100) S.advertise('b',home,{x=1,y=0,z=0},100)
local pending=S.invite('a',home,101,geometry)
assert(S.cancel(pending,'a','not-yet-accepted'))
assert(not S.pending('a') and not S.pending('b'),'unaccepted cancelled invitations are reclaimed')
