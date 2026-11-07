-- FIELD decisions use verified facts, never a universal post-WORK cargo stage.
local n=0
local function check(v,msg) n=n+1 assert(v,msg) end
local cargoCalls=0
package.loaded['EmberRoutesProbe/Field/FieldSupplies']={step=function(c)
    c.job.payload.phase='WORK' return 'Running'
end}
package.loaded['EmberRoutesProbe/Field/FieldCargo']={step=function(c)
    cargoCalls=cargoCalls+1
    if c.cargoResult=='Success' then
	for _,a in ipairs(c.job.payload.assets) do a.custody='DELIVERED' end
    end
    return c.cargoResult or 'Running'
end}
local W=require 'EmberRoutesProbe/Field/FieldWorkflow'
local function context(kind)
    local c={job={effects='KNOWN',payload={phase='WORK',target={kind=kind or 'STAIN'},assets={},workDone=true}}}
    c.change=function(fn) if c.reject then return false end fn(c.job) return true end
    return c
end
local continues=0
local def={step=function() return 'Success' end,continue=function() continues=continues+1 return false end}
local c=context()
check(W.step(c,def)=='Success','zero-output work can request settlement immediately')
check(cargoCalls==0,'zero-output work never invokes cargo')
check(c.job.payload.phase=='WORK','no artificial delivery stage')
check(continues==1,'domain considers continuation at actual work completion')
c=context('WATER')
local chain={step=def.step,continue=function(v) v.job.payload.workDone=nil return true end}
check(W.step(c,chain)=='Running','zero-output water can immediately continue')
check(cargoCalls==0,'continuation does not detour through cargo')
c=context() c.job.payload.phase='PREPARE'
check(W.step(c,def)=='Running' and c.job.payload.phase=='WORK','supply completion is not job completion')
c=context('TREE') c.job.payload.assets={{id=1,custody='GROUND'},{id=2,custody='HELD'}}
local before=continues
check(W.step(c,def)=='Running' and c.job.payload.phase=='COLLECT','ground originals enter domain collection')
check(continues==before,'does not switch targets before current cargo is resolved')
c.cargoResult='Running'
check(W.step(c,def)=='Running' and cargoCalls==1,'pending originals drive cargo')
c.cargoResult='Success'
check(W.step(c,def)=='Success' and continues==before+1,'proven delivery allows continuation/settlement')
c=context('FORAGE') c.job.payload.assets={{id=3,custody='HELD'}}
check(W.step(c,def)=='Running' and c.job.payload.phase=='DELIVER','held originals need delivery')
c=context() c.job.effects='UNKNOWN' before=continues
check(W.step(c,def)=='Failure' and continues==before,'unknown effect cannot advance')
c=context() c.job.payload.attempt={state='PREPARED',dispatched=true}
check(W.step(c,def)=='Failure','unresolved attempt cannot be hidden by Success')
c=context() c.job.payload.holding=true
check(W.step(c,def)=='Failure','corpse responsibility blocks settlement')
c=context() c.job.payload.capacity={key='warehouse'}
check(W.step(c,def)=='Failure','unreleased capacity blocks settlement')
c=context() c.reject=true c.job.payload.assets={{id=3,custody='HELD'}}
check(W.step(c,def)=='Failure' and c.job.payload.phase=='WORK','failed phase publication cannot advance')
c=context('TREE') c.job.payload.phase='DELIVER' c.job.payload.assets={{id=1,custody='GROUND'}} c.cargoResult='Success'
package.loaded['EmberRoutesProbe/Field/FieldCargo'].step=function() return 'Success' end
check(W.step(c,def)=='Failure','cargo Success cannot erase pending original responsibility')
c=context() c.recoveryOnly=true before=continues
check(W.step(c,def)=='Success' and continues==before,'recovery cannot start another target')
c=context()
local failedRollback={step=def.step,continue=function(v) v.job.effects='UNKNOWN' return false end}
check(W.step(c,failedRollback)=='Failure','failed continuation rollback cannot be disguised as settled work')
print('PASS '..n..' FIELD domain progression checks; native effects mocked')
