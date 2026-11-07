package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return {forNpc=function() return {} end} end}
local root={} local seq=0
local home={id='home'}
package.loaded['EmberRoutesProbe/Settlement/MembershipService']={view=function(id)
    if id=='a' or id=='b' then return {npcId=id,context='SETTLEMENT',settlementId='home',revision=1} end
end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end,id=function() seq=seq+1 return 'pair'..seq end}
local S=require 'EmberRoutesProbe/Activity/SocialCoordinator'
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

-- Advert expiry is exclusive, removes old eligibility, and never revives on a
-- later invitation unless that participant advertises again.
S.reset()
S.advertise('a',home,{x=0,y=0,z=0},0)
S.advertise('b',home,{x=1,y=0,z=0},0)
assert(S.invite('a',home,5999,geometry),'experimental six-second window')
S.reset()
S.advertise('a',home,{x=0,y=0,z=0},0)
S.advertise('b',home,{x=1,y=0,z=0},0)
assert(not S.invite('a',home,6000,geometry),'expiry boundary is not inviteable')
S.advertise('a',home,{x=0,y=0,z=0},6001)
assert(not S.invite('a',home,6001,geometry),'expired partner leaves no inviteable advert')
for _,phase in ipairs({'APPROACH','CONVERSE'}) do
    S.reset()
    S.advertise('a',home,{x=0,y=0,z=0},0)
    S.advertise('b',home,{x=1,y=0,z=0},0)
    local key=assert(S.invite('a',home,1,geometry))
    assert(S.accept(key,'a','a1',2) and S.accept(key,'b','b1',2))
    if phase=='CONVERSE' then
        assert(S.arrive(key,'a','a1',1) and S.arrive(key,'b','b1',1))
        assert(S.view(key,'a','a1',35001).ends==1+10/60)
    else
        assert(S.view(key,'a','a1',35000))
        assert(not S.view(key,'a','a1',35001),'35-second timeout cancels pair')
        assert(S.cancel(key,'a','a1') and S.cancel(key,'a','a1'))
        assert(S.release(key,'a','a1',true) and not S.release(key,'a','a1',true))
        assert(S.release(key,'b','b1',true))
    end
    root={} -- Reload changes the registry root; pair state is never restored.
    assert(not S.pending('a') and not S.pending('b') and not S.view(key,'a','a1',35002))
    S.withdraw('a') S.withdraw('a') S.withdraw('b')
    S.advertise('a',home,{x=0,y=0,z=0},40000)
    S.advertise('b',home,{x=1,y=0,z=0},40000)
    assert(S.invite('a',home,40001,geometry),'participants can pair again after cleanup/reload')
end
print('PASS cut 3 advert expiry, 35000ms timeout, idempotent cleanup and APPROACH/CONVERSE registry reload')
S.reset()
S.advertise('a',home,{x=0,y=0,z=0},0)
S.advertise('b',home,{x=1,y=0,z=0},0)
local half=assert(S.invite('a',home,1,geometry))
assert(S.accept(half,'a','a1',2))
S.withdraw('b') S.withdraw('b')
assert(not S.pending('b') and not S.view(half,'a','a1',3))
assert(S.release(half,'a','a1',true))
assert(not S.pending('a'))
print('PASS cut 3 half-accepted withdrawal leaves neither participant reserved')
