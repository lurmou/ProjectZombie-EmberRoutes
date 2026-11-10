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
local control
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {status=function() return control end} end}
package.loaded['EmberRoutesProbe/Settlement/MembershipService']={view=function() end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={view=function() if allowed then return {id='s',name='Home'} end return nil,'ACCESS_DENIED' end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/Warehouse/DisplayNames']={name=function(id) return id end}
package.loaded['EmberRoutesProbe/Field/FieldDemand']={rows=function() return field end}
local boot={publicDispatch=true}
boot.isPublicDispatch=function() return boot.publicDispatch==true end
package.loaded['EmberRoutesProbe/Kernel/Boot']=boot
package.loaded['EmberRoutesProbe/Work/PublicWork']={orders=function() return {order} end,rules=function() return {rule,rule} end}
local projector
package.loaded['EmberRoutesProbe/SelfCare/MedicalCare']={demands=function() return {} end}
package.loaded['EmberRoutesProbe/Warehouse/OrderMonitorService']={watch=function(_,_,callback,p) projector=p return function() end end}
local D=require 'EmberRoutesProbe/Warehouse/DemandMonitorService'
local s=D.status({},'s')
check(#s.rows==2,'same stock problem deduplicates even with repeated source facts')
local cleaning=s.rows[1] local stock=s.rows[2]
check(not cleaning.handling and cleaning.demandReason and cleaning.bucket=='waiting','waiting for an idle cleaner is ordinary waiting with an explanation')
check(stock.handling and stock.children[1].id=='order','stock shortage remains visible while an order handles it')
check(stock.urgency=='normal' and stock.affected=='Home' and stock.readOnly,'demand has urgency and affected object without mutation commands')
root.taskJobs.byId.clean={id='clean',scopeId='s',providerType='FIELD_WORK',npcId='Alice',state='RUNNING',effects='UNKNOWN',
    revision=1,payload={category='cleaning',phase='WORK',target={kind='STAIN',x=1,y=2,z=0},assets={}}}
cleaning=D.status({},'s').rows[1]
check(cleaning.handling and cleaning.uncertain and cleaning.bucket=='attention','unknown effects remain attention even with an assigned worker')
cleaning.children[1].name='mutated'
check(root.taskJobs.byId.clean.npcId=='Alice','detached display cannot mutate job authority')
control={state='ACTIVE'} root.taskJobs.byId.clean.effects='KNOWN'
cleaning=D.status({},'s').rows[1]
check(cleaning.bucket=='active' and not cleaning.demandReason,'active cleaning never claims it is waiting for an idle worker')
check(cleaning.children[1].stages[1].labelKey=='IGUI_EmberRoutesProbe_Monitor_work_STAIN',
    'demand reuses real work presentation instead of exposing WORK')
control=nil root.taskJobs.byId.clean.state='SUSPENDED'
cleaning=D.status({},'s').rows[1]
check(cleaning.bucket=='waiting' and cleaning.handling,'assigned suspended work is waiting, not active')
root.taskJobs.byId.clean.state='CANCELLED' root.taskJobs.byId.clean.effects='UNKNOWN'
cleaning=D.status({},'s').rows[1]
check(cleaning.uncertain and cleaning.children[1].jobId=='clean','terminal label cannot hide unknown cleaning responsibility')
root.taskJobs.byId.clean.state='RUNNING' root.taskJobs.byId.clean.effects='KNOWN'
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
