-- Reuse the existing furniture/native host fixture; exercise the real membership
-- writer and bed roster together, including a fresh module after save/load.
local f=dofile('tests/lua/repose-sites-test.lua')
local checks=0 local function check(v,why) checks=checks+1 assert(v,why) end
local entry=f.entry entry.factionId='f' entry.revision=1 entry.name='Home'
local foreign={id='foreign',factionId='f',revision=1,areas={{x=40,y=40,w=4,h=4}}}
local ledger=package.loaded['EmberRoutesProbe/SettlementLedger']
ledger.data=function() return {factionId='f',entries={s=entry,foreign=foreign}} end
local md={}
f.actor.isDead=function() return false end f.actor.getModData=function() return md end
package.loaded['EmberRoutesProbe/Driver'].bindId=function(_,id) return {id=id,handle=f.npc} end
f.furniture.bed=true f.other.bed=true
package.loaded['EmberRoutesProbe/MembershipService']=nil
local S=require 'EmberRoutesProbe/MembershipService'
local Sites=f.sites local Index=require 'EmberRoutesProbe/SettlementFacilities'
Index.invalidate(0,0)
assert(S.newWorld())
local function send(id,kind,scope)
    local row=S.view(id)
    return S.request(f.actor,id,{kind=kind,settlementId=scope,expectedRevision=row.revision,requestId='cmd-'..id..'-'..row.revision})
end
local function commit(id)
    for _=1,1000 do
        if S.advance(id,f.actor,{},false) then return end
        f.advance(200)
    end
    error('membership commit did not converge')
end
S.register('a') S.register('b')
send('a','SETTLE','s') commit('a')
local a=S.view('a') local bedId=a.bedId
check(bedId and f.furniture.mod.EmberRoutesRepose.id==bedId and f.other.mod.EmberRoutesRepose.id==bedId,
    'SETTLE commits one stable roster bed for the entire double furniture')
send('b','SETTLE','s') commit('b')
check(not S.view('b').bedId and S.view('b').context=='SETTLEMENT' and S.view('b').bedReason=='BED_NONE',
    'no free bed never blocks settlement or invents an assignment')
send('a','FOLLOW') commit('a')
S.reconcileBed('a')
check(S.view('a').bedId==bedId and Sites.view(f.actor,f.furniture).npcId=='a','working/away owner retains exclusive bed')
local function discover(id)
    local scan=Sites.new(f.actor,f.npc,id,'SLEEP')
    for _=1,1000 do local candidate,done=scan:step(16) if done then return candidate end end
    error('bed search did not converge')
end
check(not discover('b'),'another resident cannot borrow the unoccupied assigned double bed')
check(Sites.configure(f.actor,f.furniture,Sites.view(f.actor,f.furniture).revision,'ASSIGNED','b')=='BED_ALREADY_ASSIGNED',
    'manual configuration cannot silently overwrite another resident')
local sq=f.square(2,1,0)
local public={mod={},getSquare=function() return sq end,getModData=function(self) return self.mod end,
    getSprite=function() return {getName=function() return 'furniture_bedding_01_0' end} end,
    getProperties=function() return {get=function(_,key) if key=='BedType' then return 'goodBed' end end} end,
    hasSpriteGrid=function() return false end,isFurnitureOccupied=function() return false end}
sq.rows={public} Index.invalidate(2,1)
send('a','SETTLE','s') commit('a')
f.npc.getX=function() return 2.5 end f.npc.getY=function() return 1.5 end
check(discover('a').object~=public and discover('b').object==public,'assigned owner bed strictly outranks nearer public bed')
local rev=Sites.view(f.actor,f.furniture).revision
check(Sites.configure(f.actor,f.furniture,rev,'DISABLED')=='SITE_POLICY_SAVED' and not S.view('a').bedId,
    'explicit disable clears roster and sleep falls back to public discovery')
check(discover('a').object==public,'disabled bed does not prevent public fallback')
check(Sites.configure(f.actor,public,0,'ASSIGNED','a')=='SITE_POLICY_SAVED','single assignment entry point updates both authorities')
bedId=S.view('a').bedId
-- Temporarily unloading the exact anchor cannot prove destruction.
local grid=f.cell.getGridSquare
f.cell.getGridSquare=function(self,x,y,z) if x==2 and y==1 and z==0 then return nil end return grid(self,x,y,z) end
S.reconcileBed('a')
check(S.view('a').bedId==bedId and S.view('a').bedReason=='SITE_UNLOADED','unloaded bed retains identity and diagnostic')
f.cell.getGridSquare=grid S.reconcileBed('a')
-- Posting is membership data, not a new target or a priority override.
local zones={home={id='home',settlementId='s',enabled=true,areas={{x=0,y=0,w=4,h=4,z=0}}},
    away={id='away',settlementId='foreign',enabled=true,areas={{x=40,y=40,w=4,h=4,z=0}}}}
package.loaded['EmberRoutesProbe/SettlementZones']={get=function(id) return zones[id],'ZONE_MISSING' end,
    coveredZone=function(e,z) return e.id==z.settlementId end,
    contains=function(z,x,y,zlevel) return z and x>=0 and x<4 and y>=0 and y<4 and zlevel==0 end,
    list=function() return {zones.home} end}
package.loaded['EmberRoutesProbe/PublicWork']={provider=function(cat) return cat=='crafting' and {} or nil end,categories=function() return {'crafting'} end}
local macroStops=0 S.changed=function() macroStops=macroStops+1 end
local memberRevision=S.view('a').revision
local function posting(value) return S.setPosting(f.actor,'a',value,S.view('a').revision,S.view('a').postingRevision or 0) end
check(posting({zoneId='away',category='crafting'})=='POSTING_ZONE_INVALID','posting rejects another settlement')
check(posting({zoneId='home',category='invented'})=='POSTING_CATEGORY_INVALID','posting rejects nonexistent categories')
check(posting({zoneId='home',category='crafting'})=='POSTING_SAVED','settled resident may hold one validated posting')
check(macroStops==0 and S.view('a').revision==memberRevision,'posting is configuration and never stops bodies or changes macro generation')
check(S.setPosting(f.actor,'a',nil,memberRevision,0)=='POSTING_CHANGED','separate posting revision rejects stale configuration')
S.changed=nil
local Filter=require 'EmberRoutesProbe/MembershipPosting'
local chosen={key='existing',category='crafting',point={x=1,y=1,z=0},allowed=true}
check(Filter.allows(S.view('a').posting,zones.home,chosen),'existing in-zone candidate survives posting filter')
check(not Filter.allows(S.view('a').posting,zones.home,{category='hauling',point=chosen.point}), 'posting filters category')
check(not Filter.allows(S.view('a').posting,zones.home,{category='crafting',point={x=20,y=1,z=0}}),'posting filters worksite')
check(not Filter.allows(S.view('a').posting,zones.home,{category='crafting'}),'missing worksite is refused, not invented')
check(not require('EmberRoutesProbe/WorkSelector').choose({chosen},{crafting=0}),'posting cannot override Priority 0')
-- Pending command + live responsibility survive a detached save round-trip.
local pending=send('a','WAIT')
assert(not S.advance('a',f.actor,{{kind='TOOL_CUSTODY',itemId='tool-1'}},false))
local function copy(value) if type(value)~='table' then return value end local result={}
    for k,v in pairs(value) do result[k]=copy(v) end return result end
f.root.npcMembership=copy(f.root.npcMembership)
package.loaded['EmberRoutesProbe/MembershipService']=nil S=require 'EmberRoutesProbe/MembershipService'
check(S.load() and S.view('a').bedId==bedId and S.view('a').posting.zoneId=='home'
    and S.view('a').pending.requestId==pending.requestId and S.view('a').obligations[1].itemId=='tool-1',
    'reload retains bed, posting, pending request and unresolved tool responsibility without reroll')
check(public.mod.EmberRoutesRepose.mode=='ASSIGNED' and public.mod.EmberRoutesRepose.npcId=='a','furniture policy survives independent roster reload')
local saved=S.view('a').posting f.root.npcMembership.byNpc.a.posting.format=99
check(not S.load() and f.root.npcMembership.byNpc.a.posting.format==99,'unknown posting format rejected and preserved')
f.root.npcMembership.byNpc.a.posting=saved
local location=f.root.npcMembership.byNpc.a.bedLocation
f.root.npcMembership.byNpc.a.bedLocation={x=0/0,y=0,z=0}
check(not S.load(),'corrupt bed locator rejected before writes')
f.root.npcMembership.byNpc.a.bedLocation=location
-- Macro calls are per resident and per revision, never atomic.
getText=function(key) return key end getTextOrNull=getText
package.loaded['EmberRoutesProbe/DisplayNames']={name=function(id) return id end}
local spoken={} f.actor.Say=function(_,line) spoken[#spoken+1]=line end
package.loaded['EmberRoutesProbe/MembershipMenu']=nil
local Menu=require 'EmberRoutesProbe/MembershipMenu'
check(Menu.commandStatus('a','WAIT',pending).state=='BLOCKED','blocked accepted command has separate status and reason')
commit('a')
check(Menu.commandStatus('a','WAIT',pending).state=='COMPLETED','WAIT reports completion only after commit')
S.register('outside') send('outside','SETTLE','foreign') commit('outside')
local batch=Menu.batchRequest(f.actor,'s','RETURN',{{id='a',revision=S.view('a').revision},
    {id='b',revision=S.view('b').revision-1},{id='outside',revision=S.view('outside').revision}})
check(batch[1].status=='ACCEPTED_PENDING' and batch[2].status=='FAILED' and batch[2].reason=='STALE_MEMBERSHIP'
    and batch[3].reason=='SCOPE_MISMATCH','batch exposes partial success, stale revisions and current-members-only rejection')
commit('a')
check(Menu.commandStatus('a','RETURN',batch[1].receipt).state=='ACCEPTED_PENDING','committed RETURN intention is not an arrival')
S.transition('a',S.view('a').revision,'SETTLEMENT')
check(Menu.commandStatus('a','RETURN',batch[1].receipt).state=='COMPLETED','RETURN needs actual runtime arrival transition')
for _=1,130 do send('b','WAIT') commit('b') end
check(not S.result('a',batch[1].receipt.requestId) and Menu.commandStatus('a','RETURN',batch[1].receipt).state=='COMPLETED',
    'large partial batches retain completion evidence after bounded receipt eviction')
-- Unknown furniture formats retain both original policy and roster for diagnosis.
public.mod.EmberRoutesRepose.format=99 S.reconcileBed('a')
check(S.view('a').bedId==bedId and S.view('a').bedReason=='SITE_CONFLICT'
    and public.mod.EmberRoutesRepose.format==99,'unknown furniture policy is retained, never reset')
public.mod.EmberRoutesRepose.format=1
public.mod.EmberRoutesRepose.npcId='b'
S.reconcileBed('a')
check(not S.view('a').bedId and S.view('a').bedReason=='BED_INVALID'
    and public.mod.EmberRoutesRepose.npcId=='b','inconsistent roster clears visibly without stealing or rerolling')
assert(Sites.configure(f.actor,public,Sites.view(f.actor,public).revision,'PUBLIC')=='SITE_POLICY_SAVED')
assert(Sites.configure(f.actor,public,Sites.view(f.actor,public).revision,'ASSIGNED','a')=='SITE_POLICY_SAVED')
send('a','UNASSIGN') commit('a')
check(not S.view('a').bedId and not S.view('a').posting and public.mod.EmberRoutesRepose.mode=='PUBLIC',
    'normal unassignment releases the exact owned furniture and posting')
send('a','SETTLE','s') commit('a')
check(S.view('a').bedId==bedId,'explicit resettlement reuses actual furniture identity')
-- Destroyed or conflicting ownership never silently rerolls or overwrites.
sq.rows={} S.reconcileBed('a')
check(not S.view('a').bedId and S.view('a').bedReason=='BED_INVALID','destroyed bed clears roster visibly without reroll')
check(posting(nil)=='POSTING_SAVED' and not S.view('a').posting,'posting clear uses the same validated command')
print('PASS '..checks..' Health Gate A membership/bed/posting/macro/save checks; native world and arrival mocked')
