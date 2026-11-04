-- Read-only demand projection and existing watcher dispatch; no native simulation.
local count=0 local function check(v,m) count=count+1 assert(v,m) end
function getText(key,...)
    local parts={key} for _,v in ipairs({...}) do parts[#parts+1]=tostring(v) end return table.concat(parts,'|')
end
function getTextOrNull() return nil end
function getItemNameFromFullType(v) return v end
local allowed=true local root={taskJobs={byId={}}}
local field={{id='DEMAND:cleaning:s',state='BLOCKED',reason='FIELD_WORKER_BUSY',generation=1,observedCount=3}}
local rule={id='r',product='Base.Bandage',minimum=5,knownCount=1,enabled=true,revision=1,activeOrder='order'}
local order={id='order',state='WAITING',name='Bandages'}
package.loaded['EmberRoutesProbe/SettlementLedger']={view=function() if allowed then return {id='s',name='Home'} end return nil,'ACCESS_DENIED' end}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/DisplayNames']={name=function(id) return id end}
package.loaded['EmberRoutesProbe/FieldDemand']={rows=function() return field end}
package.loaded['EmberRoutesProbe/Boot']={publicDispatch=true}
package.loaded['EmberRoutesProbe/PublicWork']={orders=function() return {order} end,rules=function() return {rule,rule} end}
local projector
package.loaded['EmberRoutesProbe/MedicalCare']={demands=function() return {} end}
package.loaded['EmberRoutesProbe/OrderMonitorService']={watch=function(_,_,callback,p) projector=p return function() end end}
local D=require 'EmberRoutesProbe/DemandMonitorService'
local s=D.status({},'s')
check(#s.rows==2,'same stock problem deduplicates even with repeated source facts')
local cleaning=s.rows[1] local stock=s.rows[2]
check(not cleaning.handling and cleaning.blocked and cleaning.bucket=='attention','unhandled cleaning explains its blocker')
check(stock.handling and stock.children[1].id=='order','stock shortage remains visible while an order handles it')
check(stock.urgency=='normal' and stock.affected=='Home' and stock.readOnly,'demand has urgency and affected object without mutation commands')
root.taskJobs.byId.clean={id='clean',scopeId='s',providerType='FIELD_WORK',npcId='Alice',state='RUNNING',effects='UNKNOWN',
    payload={category='cleaning',phase='WORK'}}
cleaning=D.status({},'s').rows[1]
check(cleaning.handling and cleaning.uncertain and cleaning.bucket=='attention','unknown effects remain attention even with an assigned worker')
cleaning.children[1].name='mutated'
check(root.taskJobs.byId.clean.npcId=='Alice','detached display cannot mutate job authority')
order.state='CANCELLED'
stock=D.status({},'s').rows[2]
check(not stock.handling,'cancelled order no longer counts as a handler')
check(#D.status({},'s').rows==2,'cancelling an order does not erase the observed shortage')
rule.activeOrder=nil rule.knownCount=5
check(#D.status({},'s').rows==1,'satisfied stock fact clears the demand')
field={} root.taskJobs.byId.clean.effects='KNOWN'
check(#D.status({},'s').rows==1,'existing unresolved cleaning execution remains discoverable without stain facts')
root.taskJobs.byId.clean.state='DONE'
check(#D.status({},'s').rows==0,'settled work alone does not invent a remaining demand')
allowed=false
check(D.status({},'s').reason=='ACCESS_DENIED','access gate precedes all demand observation')
D.watch({},'s',function() end)
check(projector==D.status,'watch uses the demand projection instead of building an order snapshot')
print('PASS '..count..' demand separation checks; host only')
