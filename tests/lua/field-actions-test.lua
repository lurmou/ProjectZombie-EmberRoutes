local n=0 local function check(v,m) n=n+1 assert(v,m) end
local Actions=require 'EmberRoutesProbe/FieldActions'
local queued
ISTimedActionQueue={hasAction=function(a) return queued==a end}
local commits=0
local function context()
 local live=true
 local c={job={id='field',effects='KNOWN',payload={sequence=0}}}
 c.same=function() return true end c.valid=function() return true end
 c.change=function(edit) edit(c.job) return true end
 c.unknown=function() c.job.effects='UNKNOWN' c.job.payload.attempt.state='UNKNOWN' return true end
 c.body={current=function() return live end,retained=function() return true end,
  add=function(a) queued=a return true end}
 function c.revoke() live=false c.stopping=true end
 return c
end
local function native()
 return {isValid=function() return true end,start=function() end,update=function() end,
  perform=function() queued=nil end,stop=function() queued=nil end,
  complete=function() commits=commits+1 return true end}
end
local c=context() local output=false
local a=assert(Actions.new(c,{kind='HARVEST',create=native,observe=function(ok,finished) return true,output,not finished end}))
check(a.run()=='Running','owned action is queued')
queued:start()
local old=queued
output=true old:complete()
check(c.job.effects=='KNOWN' and c.job.payload.attempt.state=='APPLIED','effect is recorded before callback returns')
old:complete()
check(commits==1,'repeated native completion cannot duplicate effect')
old:perform()
check(a.run()=='Success','completion requires observed output')
c=context() output=false
a=assert(Actions.new(c,{kind='HARVEST',create=native,observe=function(ok,finished) return true,output,not finished end}))
a.run() old=queued c.revoke() old:complete()
check(commits==1,'revoked body cannot call native complete')
old:stop() a.settle()
check(c.job.payload.attempt.state=='ABORTED','known no-effect interruption is recorded')
c=context()
a=assert(Actions.new(c,{kind='HARVEST',create=native,observe=function() return false,false end}))
a.run() old=queued old:complete() old:perform()
check(c.job.effects=='UNKNOWN' and a.run()=='Failure','unprovable effect is isolated')
check(Actions.new(c,{kind='HARVEST'})==nil,'unknown attempt cannot restart')
c=context() local hits=0
local function treeAction()
 local v=native()
 v.animEvent=function() commits=commits+1 hits=hits+1 end
 return v
end
a=assert(Actions.new(c,{kind='TREE',progressive=true,create=treeAction,
 observe=function(ok,finished) return ok,hits==2,not finished end}))
a.run() old=queued old:start() old:animEvent('ChopTree')
check(c.job.payload.attempt.state=='PREPARED' and c.job.effects=='KNOWN','partial hit recorded without completing the tree')
old:animEvent('ChopTree') old:animEvent('ChopTree') old:perform()
check(hits==2 and a.run()=='Success','completed tree cannot receive a duplicate hit')
-- Deposit is one confirmed effect; ecological retirement is another native callback.
c=context() output=false local finalized=false
local finalizeAction=native
local node=assert(Actions.new(c,{kind='FORAGE',create=finalizeAction,
 observe=function(ok,finished) return ok,output,not finished end,
 afterPerform=function() return finalized end}))
node.run() old=queued output=true old:complete()
c.revoke() old:stop() queued=nil
check(node.settle() and c.job.effects=='UNKNOWN', 'interruption after deposit retains unconfirmed finalization')
check(node.settle() and c.job.effects=='UNKNOWN', 'repeated stop settlement cannot erase finalization uncertainty')
check(node.run()=='Failure', 'incomplete native transaction cannot report success')
print('PASS '..n..' field native-adapter boundary checks; native effects mocked')
