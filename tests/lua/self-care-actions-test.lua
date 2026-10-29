local checks=0 local function check(v,s) checks=checks+1 assert(v,s) end
local objects={} local inventory={getItems=function() return {size=function() return #objects end,get=function(_,i) return objects[i+1] end} end}
local remaining=0.4 local queued,live,retained=nil,true,true local saves=0
local item={getID=function() return 7 end,getFullType=function() return 'Base.Bread' end,
    getHungChange=function() return -remaining end,getContainer=function() return inventory end}
objects={item}
package.loaded['TimedActions/ISEatFoodAction']=true package.loaded['TimedActions/ISDrinkFluidAction']=true
local completions,stops=0,0
ISEatFoodAction={new=function(_,npc,food,fraction)
    return {character=npc,start=function() end,update=function() end,isValid=function() return true end,
        complete=function() completions=completions+1 remaining=remaining-0.1 return true end,
        perform=function() queued=nil end,
        stop=function() stops=stops+1 remaining=remaining-0.025 queued=nil end}
end}
ISTimedActionQueue={hasAction=function(action) return action==queued end}
local Actions=require 'EmberRoutesProbe/SelfCareActions'
local function context()
    return {npc={getInventory=function() return inventory end},payload={attemptId='care:1'},
        sameAttempt=function() return true end,valid=function() return true end,
        persist=function() saves=saves+1 return true end,
        body={current=function() return live end,retained=function() return retained end,
            add=function(action) queued=action return true end,
            clear=function() if queued then queued:stop() end return true end}}
end
local c=context() local leaf=Actions.consumption(c,'EAT',item,0.25)
check(leaf.run()=='Running' and queued and saves>0,'records intent before dispatching a native action')
local action=queued action:start()
check(c.payload.consumption.started,'native start fact saved')
action:complete() action:complete() action:perform()
check(completions==1 and math.abs(remaining-0.3)<0.00001,'duplicate completion cannot consume twice')
check(leaf.run()=='Success' and c.payload.consumption.effects=='KNOWN','success requires actual depletion')
retained=false action:stop() check(stops==0,'old callback cannot stop or consume after authority release')
local restored=context() restored.payload=c.payload
local replay=Actions.consumption(restored,'EAT',item,0.25)
check(replay.run()=='Success' and not queued,'known completed attempt is never enqueued again')
retained=true live=true local partial=context()
local interrupted=Actions.consumption(partial,'EAT',item,0.25)
assert(interrupted.run()=='Running') queued:start() live=false
check(interrupted.halt() and partial.payload.consumption.stopped,'retained stopping authority accounts partial consumption')
check(math.abs(partial.payload.consumption.consumed-0.025)<0.00001,'partial amount preserved without rollback')
live=true local uncertain=context()
uncertain.payload.consumption={started=true,attemptId='care:1'}
local unknown=Actions.consumption(uncertain,'EAT',item,0.25)
check(unknown.run()=='Failure' and uncertain.effects=='UNKNOWN' and not queued,'unconfirmed restored consumption cannot restart')
local stale=context()
stale.payload.consumption={attemptId='care:0',kind='EAT',before=0.4,effects='KNOWN',completed=true}
local foreign=Actions.consumption(stale,'EAT',item,0.25)
check(foreign.run()=='Failure' and stale.effects=='UNKNOWN','completed evidence from a different attempt cannot finish this one')
local rejected=context()
rejected.payload.consumption={attemptId='care:1',kind='EAT',before=0.3,effects='UNKNOWN',started=false}
check(Actions.consumption(rejected,'EAT',item,0.25).run()=='Failure' and not queued,
    'unknown effects cannot be reset by a false started marker')
local changed=context() local changedLeaf=Actions.consumption(changed,'EAT',item,0.25)
assert(changedLeaf.run()=='Running') local external=queued external:start()
remaining=remaining-0.01 local prior=completions
check(external:complete()==false and completions==prior and changed.effects=='UNKNOWN',
    'foreign depletion before native completion cannot be attributed or consumed again')
check(changedLeaf.run()=='Failure','foreign depletion enters reconciliation instead of another native effect')
print('PASS '..checks..' consumption leaf fencing/partial-effect checks; native actions mocked')
