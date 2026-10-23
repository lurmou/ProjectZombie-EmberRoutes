function getText(key) return key end
local checks=0
local function check(value,label) checks=checks+1 assert(value,label) end
local craft={id='craft-one',npcId='a',generation=4,settlementId='s',state='PAUSED',phase='CRAFTING',reason='REPLACED',
    materials={{id=11,fullType='Base.Log'}},tools={{id=12}},outputs={},format=3,
    chain={index=1,nodes={{recipeName='Saw logs',requested=3,product='Base.Plank'}}}}
local haul={id='haul-one',npcId='b',generation=2,state='PAUSED',phase='DELIVER',reason='USER',source='in',destination='out',items={21},delivered=0}
local root={craftProbes={byNpc={a=craft}},labor={tasks={[haul.id]=haul}}}
local allowed=true local mode='FOLLOW' local control local calls={} local callback local released=false
package.loaded['EmberRoutesProbe/Boot']={ready=true,hasJava=function() return true end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,
    describe=function(id) if id=='in' or id=='out' then return {x=1,y=2,z=0} end end}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function(_,id) if allowed then return {id=id} end return nil,'ACCESS_DENIED' end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function(_,x) return x==1 end}
package.loaded['EmberRoutesProbe/CraftProbe']={status=function() return {recipeName='Saw logs',product='Base.Plank',requested=3,target=3,produced=0,delivered=0,resumable=true} end}
package.loaded['EmberRoutesProbe/CraftingService']={command=function(_,_,npc,action) calls[#calls+1]={npc=npc,action=action} return 'QUEUED' end,
    watch=function(_,_,fn) callback=fn return function() released=true end end}
package.loaded['EmberRoutesProbe/Work']={taskCommand=function(_,npc,id,generation,action)
    calls[#calls+1]={npc=npc,id=id,generation=generation,action=action} return 'QUEUED' end}
package.loaded['EmberRoutesProbe/Driver']={bindId=function(_,id) if id=='a' then return {handle={getFullName=function() return 'Alice' end}} end end}
package.loaded['EmberRoutesProbe/TaskRuntime']={current=function() return {status=function(_,id,job) if id=='a' and job==craft.id then return control end end} end}
package.loaded['EmberRoutesProbe/Companion']={exportState=function() return {mode=mode} end}
package.loaded['EmberRoutesProbe/BusinessJobs']={records=function(kind)
    return kind=='CRAFT' and {[craft.id]=craft} or {[haul.id]=haul}
end}
package.loaded['EmberRoutesProbe/Production']={status=package.loaded['EmberRoutesProbe/CraftProbe'].status}
local Service=require 'EmberRoutesProbe/OrderMonitorService'
local s=Service.status({},'s')
check(#s.rows==2,'saved crafting and unpooled hauling tasks are both visible')
local a,b=s.rows[1],s.rows[2]
check(a.id=='CRAFT:craft-one' and a.name=='Alice' and a.bodyMode=='FOLLOW' and a.canResume,'paused production and active follow remain separate')
check(b.id=='HAUL:haul-one' and not b.carrierAvailable and not b.canResume,'offline worker keeps its original task visible without an unsafe resume')
haul.controlUncertain=true
check(Service.status({},'s').rows[2].bucket=='attention','unknown hauling effects are retained as needs-review, not an ordinary pause')
haul.controlUncertain=nil
package.loaded['EmberRoutesProbe/Boot'].ready=false
check(not Service.status({},'s').rows[1].carrierAvailable,'unavailable Java still permits a retained-record view without binding')
package.loaded['EmberRoutesProbe/Boot'].ready=true
check(#a.assets==2 and a.assets[1].id==11 and a.nodes[1].name=='Saw logs','original IDs and recipe plan are detached')
a.assets[1].id=999 a.nodes[1].name='changed'
check(craft.materials[1].id==11 and craft.chain.nodes[1].recipeName=='Saw logs','view cannot mutate originals or recipe nodes')
check(Service.command({},'s','CRAFT:craft-one',4,'resume')=='QUEUED' and calls[1].npc=='a','resume targets the job owner, never selected NPC')
craft.generation=5
check(Service.command({},'s','CRAFT:craft-one',4,'return')=='TASK_CHANGED' and #calls==1,'old revision cannot cancel a resumed task')
local originalId=craft.id craft.id='replacement'
check(Service.command({},'s','CRAFT:craft-one',5,'stop')=='TASK_CHANGED' and #calls==1,'same NPC replacement is not a substitute for selected job')
craft.id=originalId control={state='STOPPING'}
a=Service.status({},'s').rows[1]
check(a.state=='STOPPING' and not a.canResume and not a.canCancel,'unconfirmed body stop stays visible and blocks recovery')
control=nil craft.uncertain=true
a=Service.status({},'s').rows[1]
check(a.bucket=='attention' and not a.canResume and a.canCancel,'unknown commit cannot replay but existing cleanup remains reachable')
craft.uncertain=nil craft.released=true craft.state='DONE'
a=Service.status({},'s').rows[2]
check(a.closed and a.bucket=='closed' and not a.canResume,'closed current record is distinguishable from active job')
craft.settlementId='other'
check(#Service.status({},'s').rows==1,'other settlement production is excluded')
haul.destination='unknown'
check(#Service.status({},'s').rows==0,'manual haul without two in-settlement endpoints is excluded')
haul.destination='out' haul.settlementId='other'
check(#Service.status({},'s').rows==0,'explicit foreign hauling ownership overrides local endpoints')
local pending={id='public-one',settlementId='s',name='Saw',state='WAITING',reason='WAITING_CLAIM',quantity=3,target=3,revision=2}
package.loaded['EmberRoutesProbe/Boot'].publicDispatch=true
local publicRevision
package.loaded['EmberRoutesProbe/PublicWork']={orders=function() return {pending} end,
 command=function(_,scope,id,revision) publicRevision=revision return 'ORDER_UPDATED' end}
local publicRows=Service.status({},'s').rows
check(#publicRows==1 and publicRows[1].kind=='ORDER' and publicRows[1].generation=='ORDER:2','unclaimed demand is visible with a distinct command revision domain')
check(Service.command({},'s','ORDER:public-one','ORDER:2','stop')=='ORDER_UPDATED' and publicRevision==2,'unclaimed pause reaches Order authority without choosing an NPC')
pending.jobId=craft.id craft.orderId=pending.id craft.settlementId='s' craft.state='PAUSED' craft.released=false craft.generation=2
check(Service.command({},'s','ORDER:public-one','ORDER:2','return')=='TASK_CHANGED','old unclaimed button cannot control newly assigned Job at same numeric generation')
craft.orderId=nil craft.settlementId='other' package.loaded['EmberRoutesProbe/Boot'].publicDispatch=false
allowed=false
check(Service.command({},'s','HAUL:haul-one',2,'resume')=='ACCESS_DENIED' and #calls==1,'permission is rechecked on commands')
allowed=true
local received local release=Service.watch({},'s',function(value) received=value end)
root={} callback({})
check(received.reason=='WORLD_RESET' and #received.rows==0,'watch cannot carry task projections across worlds')
release() check(released,'unsubscribe propagates to the existing view service')
print('PASS '..checks..' order monitor projection/command checks; no engine/inventory run')
