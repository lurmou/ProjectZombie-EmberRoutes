-- The fixture exercises the real Runtime/Controller/Driver/Companion pipeline.
local ctx=dofile('tests/lua/task-companion-runtime-test.lua')
local assertions=0
local function check(v,m) assertions=assertions+1 assert(v,m) end
ctx.select('a')
check(ctx.companion.debugExecute(ctx.actor,'follow'),'start a follower in the final fixture world')
ctx.tick(3)
local runtime=ctx.runtime()
check(ctx.companion.exportState('a').mode=='FOLLOW','predecessor is following')
local saved,careBody,done
local careId='care-1'
local h=runtime:submit({npcId='a',jobId=careId,kind='SELF_CARE',binding={id='a',handle=ctx.bodies.a},
    validate=function() return true end,
    start=function(body) careBody=body return true end,
    tick=function() end,finished=function() return done==true end,
    stopAdapter=function(controller,ticket)
        return require('EmberRoutesProbe/Runtime/TaskBusinessStop').new({controller=controller,ticket=ticket,
            npc=ctx.bodies.a,npcId='a',jobId=careId,same=function() return true end,
            pause=function() return true end,effects=function() return 'KNOWN' end,persist=function() return true end})
    end,persistFailure=function() return true end,replaceReason='SELF_CARE'})
check(h~=nil,'self care submits through the same runtime')
ctx.tick(8)
saved=ctx.root().companionIntents.byNpc.a
check(careBody and careBody.current() and saved.mode=='FOLLOW','care receives body only after follow stop persists intent')
check(ctx.companion.exportState('a').mode=='HOLD','predecessor is paused while care owns the body')
check(ctx.keys().a~=nil,'care retains unique authority')
done=true ctx.tick(5)
check(ctx.keys().a==nil,'care release completes before follow can resume')
saved.id='a'
check(ctx.companion.restoreState(ctx.actor,saved),'scalar intent queues controlled restoration')
ctx.tick(4)
check(ctx.companion.exportState('a').mode=='FOLLOW' and ctx.keys().a~=nil,'follow resumes with fresh grant')
local accepted=careBody.follow(ctx.actor,0)
check(not accepted,'expired care body cannot start a follower in successor session')
check(ctx.companion.startFor(ctx.actor,'a',1),'macro follow starts against the current member revision')
ctx.tick(8)
ctx.bodies.a.motion='FOLLOW_STALLED' ctx.tick(5)
local retry,why=ctx.companion.startFor(ctx.actor,'a',1)
check(not retry and why=='FOLLOW_RETRY_WAIT','same failed route is not restarted by periodic macro retries')
ctx.actor.x=ctx.actor.x+2
check(ctx.companion.startFor(ctx.actor,'a',1),'leader position change permits a fresh bounded attempt')
ctx.tick(4)
check(ctx.companion.exportState('a').mode=='FOLLOW','movement wakeup retains normal control admission')
print('PASS '..assertions..' controlled follow/self-care handoff checks; native host mocked')
