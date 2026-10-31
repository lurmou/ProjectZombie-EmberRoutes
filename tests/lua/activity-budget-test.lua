-- Real cursor pump; native proof/stop/advance operations are counted substitutes.
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local events,ids,saved,version,now,bad,visited,calls,proofed={}, {},{},0,0,{}, {},{},{}
local function remove(id)
    for i,key in ipairs(ids) do if key==id then table.remove(ids,i) version=version+1 return end end
end
local store={get=function(id) return events[id] end,active=function() return ids,version end}
function store.touch(e) e.revision=e.revision+1 if e.state=='CLOSED' then remove(e.id) end return true end
function store.withdraw(id,npc)
    local e=events[id] local m=e.roster[npc]
    if not m.withdrawn then m.withdrawn=true store.touch(e) end
end
function store.close(id,revision,reason)
    local e=events[id] assert(e.revision==revision)
    e.state='WINDING_DOWN' e.controlEpoch=e.controlEpoch+1 e.outcome=reason store.touch(e) return true
end
package.loaded['EmberRoutesProbe/ActivityStore']=store
local participant={}
function participant.proof(e,id) calls.proofs=calls.proofs+1 proofed[id]=true return not bad[id],now end
function participant.receipt(e,id) return not bad[id] end
function participant.present(e,id) calls.present=calls.present+1 return not bad[id] end
function participant.stop(id,e) calls.stops=calls.stops+1 end
function participant.collectOne(e,id)
    calls.collect=calls.collect+1 local m=e.roster[id]
    if m.unknown then return false end
    if not m.settled then m.settled=true store.touch(e) end
    return true
end
function participant.finishCollection(e,all)
    if all then e.state='CLOSED' store.touch(e)
    elseif e.state=='WINDING_DOWN' then e.state='SETTLING' store.touch(e) end
    return all
end
function participant.advance(actor,e,id) calls.advance=calls.advance+1 visited[id]=true end
package.loaded['EmberRoutesProbe/ActivityParticipant']=participant
local Pump=require 'EmberRoutesProbe/ActivityPump'
local pump=Pump.new({site=function() return true end,
    memberValid=function(id,e) return e.roster[id] and not e.roster[id].withdrawn end,
    calendar=function(actor,hours,budget) assert(budget==2) calls.calendar=calls.calendar+1 end})
local function reset()
    events,ids,saved,bad,visited,proofed={},{},{},{},{},{} version=version+1
end
local function scene(id,n)
    local e={id=id,worldId='budget-world',definition='FREE_GATHERING',definitionVersion=1,state='GATHERING',revision=1,controlEpoch=1,
        stageEpoch=1,roster={},organizerId=id..':npc1',quorum=2,createdAt=0,gatherDeadline=1,endsAt=3,durationHours=2}
    for i=1,n do e.roster[id..':npc'..i]={jobId='job:'..id..':'..i,readyAt=0,participationHours=.1} end
    events[id]=e ids[#ids+1]=id version=version+1 return e
end
local function tick(at)
    now=at calls={proofs=0,present=0,stops=0,collect=0,advance=0,calendar=0}
    pump.tick({},saved,now,0)
    assert(calls.proofs+calls.present+calls.collect<=32,'phase work escaped its shared member budget')
    assert(calls.advance<=16 and calls.calendar<=1,'body or calendar work escaped its budget')
    local stats=pump.stats() assert(stats.headers<=4 and stats.phaseMembers<=32 and stats.bodyMembers<=16)
end
reset() local e=scene('large',64)
tick(0)
check(e.state=='GATHERING' and calls.proofs==32,'a partial readiness scan cannot open the scene')
bad['large:npc10']=true e.revision=e.revision+1
e.roster['large:npc64'].withdrawn=true e.roster['large:npc64'].settled=true
tick(100) tick(200) tick(300)
check(e.state=='GATHERING','roster or stop changes invalidate prior sliced readiness facts')
bad['large:npc10']=nil e.revision=e.revision+1
for i=4,10 do tick(i*100) end
check(e.state=='RUNNING' and not e.roster['large:npc64'].joined,'fresh complete proof opens without reintroducing a withdrawn actor')
e.roster['large:npc2'].unknown=true store.close(e.id,e.revision,'CANCELLED')
for i=11,30 do tick(i*100) end
check(e.state=='SETTLING' and not e.roster['large:npc2'].settled,'UNKNOWN remains unsettled without fabricated body release')
check(e.roster['large:npc1'].settled and e.roster['large:npc63'].settled,'one unknown actor does not freeze known-safe participants')
e.roster['large:npc2'].unknown=false
for i=31,50 do tick(i*100) end
check(e.state=='CLOSED' and #ids==0,'completed cleanup removes the derived active index')
reset() local a,b=scene('a',70),scene('b',70)
for i=0,20 do tick(i*100) end
local count=0 for _ in pairs(visited) do count=count+1 end
check(count==140,'round-robin work eventually advances every actor across simultaneous scenes')
reset() e=scene('stale',64)
tick(0) tick(5000) tick(5100)
check(e.state=='GATHERING','a long frame gap cannot commit stale readiness')
tick(6100) tick(6200) tick(6300)
check(e.state=='RUNNING','a fresh bounded rescan recovers after the stale barrier')
tick(6400) tick(50)
check(calls.advance>0,'clock rollback resets disposable cursor deadlines')
reset() e=scene('stop-between-slices',64)
tick(0)
local stopped for id in pairs(proofed) do stopped=id break end
bad[stopped]=true -- Stop changes Runtime state before any logical event callback.
tick(100) tick(200)
check(e.state=='GATHERING','atomic receipt metadata recheck rejects a stop between native scan slices')
print('activity-budget: '..checks..' PASS (real cursor pump; native participants mocked)')
