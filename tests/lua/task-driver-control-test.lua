local Controller=require 'EmberRoutesProbe/TaskController'
local stopped=false
local handle={}
local key,issuedGeneration
local mask=0
local frozen=false
local releaseThrows=false
EmberRoutesProbeJava={
    carrierPresent=function(h) return h==handle end,
    carrierId=function() return 'a' end,
    acquireBodyControl=function(h,job,generation)
        assert(h==handle and job=='job' and generation>0)
        issuedGeneration=generation key='secret' return key
    end,
    moveSeatWithControl=function(h,k,object,limit) assert(k==key and object=='chair' and limit==12) mask=1 return 'MOVE_REQUESTED_SEAT' end,
    moveSleepSeatWithControl=function(h,k,object) assert(h==handle and k==key and object=='bed') mask=1 return 'MOVE_REQUESTED_SEAT' end,
    moveWithControl=function(h,k) assert(k==key and not frozen) mask=1 return 'MOVE_REQUESTED' end,
    furniturePoseWithControl=function(h,k,object,phase)
        assert(h==handle and k==key and object=='chair' and (phase=='PREPARE' or phase=='LIE')) return true
    end,
    stopWithControl=function(h,k) assert(k==key) mask=0 stopped=true return true end,
    bodyStopMask=function(h,k) assert(k==key) return mask end,
    releaseBodyControl=function(h,k)
        assert(k==key)
        if releaseThrows then error('native observation failed') end
        if mask~=0 then return false end key=nil return true
    end,
    freezeBodyControl=function() frozen=true return true end,
    thawBodyControl=function() assert(key==nil) frozen=false return true end,
    retireBodyControl=function() frozen=true return true end,
}
local c=Controller.new()
local t
local adapter={requestStop=function() return c:stopBody(t) end,
    observeStop=function() return {bodyStopped=c:bodySnapshot(t).nativeStopped,effects='KNOWN'} end,
    persistEffects=function() return true end}
t=assert(c:request('a','job','WORK',adapter))
assert(not c:attachDriver(t,{id='a',handle=handle}))
c:step()
assert(not c:attachDriver(t,{id='b',handle=handle}))
assert(c:attachDriver(t,{id='a',handle=handle}) and issuedGeneration>0)
assert(not c:attachDriver(t,{id='a',handle=handle}))
assert(c:bodySnapshot(t).nativeStopped)
local furnitureBody=c:body(t)
assert(furnitureBody.furniture('chair','PREPARE') and not furnitureBody.furniture('chair','INVALID'))
assert(furnitureBody.furniture('chair','LIE'),'sleep pose uses the existing authorized body capability')
assert(c:move(t,{}, {x=1,y=2,z=0}))
assert(not c:bodySnapshot(t).nativeStopped)
local seatOk,seatResult=c:move(t,{}, {furniture='chair',maxPathLength=12})
assert(seatOk and seatResult=='MOVE_REQUESTED_SEAT','same body capability dispatches exact seating approach')
assert(c:move(t,{}, {furniture='bed',sleep=true}),'sleep approach uses its guarded native seat route')
assert(c:beginSave() and frozen)
assert(not c:move(t,{}, {x=1,y=2,z=0}))
assert(not furnitureBody.furniture('chair','PREPARE'),'stopping owner cannot prepare or align a new pose')
assert(not c:finishSave(true))
releaseThrows=true
c:step()
assert(c:inspect(t).state=='STOPPING' and key~=nil)
releaseThrows=false
c:step()
assert(stopped and key==nil and c:inspect(t).state=='CLOSED')
assert(c:finishSave(true) and not frozen)
assert(not c:stopBody(t) and not c:bodySnapshot(t).available)
c:retire()
print('PASS controller/Driver capability bridge; native Java bodies NOT RUN')
