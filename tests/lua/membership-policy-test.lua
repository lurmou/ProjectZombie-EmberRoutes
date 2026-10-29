local P=require 'EmberRoutesProbe/MembershipPolicy'
local e={id='home',factionId='f',revision=4,areas={{x=0,y=0,w=10,h=10}}}
local r={npcId='a',factionId='f',settlementId='home',context='SETTLEMENT',revision=2}
local at={x=2,y=2,z=0,scopeId='home'}
for _,purpose in ipairs({'WORK','LEISURE','STUDY'}) do assert(P.evaluate(r,e,purpose,at,2).allowed) end
assert(P.evaluate(r,e,'LEISURE',at,1).reason=='STALE_MEMBERSHIP')
r.context='WAIT' assert(P.evaluate(r,e,'WORK',at).reason=='CONTEXT_WAIT')
assert(P.evaluate(r,e,'SELF_CARE',at).allowed and P.evaluate(r,e,'RECOVERY',at).allowed)
assert(P.evaluate(r,e,'SELF_CARE',at).sharedResources,'WAIT permits necessary care with own settlement supplies')
r.context='FOLLOW' assert(not P.evaluate(r,e,'STUDY',at).allowed)
assert(not P.evaluate(r,e,'SELF_CARE',at).sharedResources,'FOLLOW retains personal-supplies-only policy')
r.context='SETTLEMENT' r.pendingCommand={requestId='q'}
assert(P.evaluate(r,e,'LEISURE',at).reason=='COMMAND_PENDING') r.pendingCommand=nil
assert(P.evaluate(r,e,'WORK',{x=20,y=20}).reason=='OUTSIDE_SETTLEMENT')
assert(P.evaluate(r,e,'WORK',{x=1,y=1,scopeId='other'}).reason=='SCOPE_MISMATCH')
assert(P.evaluate(r,nil,'WORK',at).reason=='TARGET_LOST')
local other={id='home',factionId='enemy',revision=4,areas=e.areas}
assert(P.evaluate(r,other,'WORK',at).reason=='ACCESS_DENIED')
assert(P.evaluate(nil,nil,'SELF_CARE',at).allowed)
assert(P.evaluate(nil,nil,'WORK',at).reason=='NO_MEMBERSHIP')
assert(r.settlementId=='home','geometry never changes identity')
print('Membership policy: contexts, purposes, revisions, scope and geometry')
