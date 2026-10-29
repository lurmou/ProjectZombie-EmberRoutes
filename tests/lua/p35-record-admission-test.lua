-- Regression: selecting SIT was not enough: the real Job validator rejected
-- site on LEISURE before a Session could ever start.
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local job=Record.create('sit-job','npc-a')
job.payload=assert(Record.begin(job,'LEISURE'))
local p=job.payload
p.settlementId='home' p.membershipRevision=1 p.settlementRevision=1
p.leisure={format=1,activity='SIT',hours=1}
p.site={id='chair',partId='part',revision=1,key='chair-key',parts={{id='part',x=1,y=2,z=0}}}
p.claims={'repose:chair:part'}
assert(Record.valid(job),'LEISURE SIT must pass the full personal record validator with its furniture proof')
local Jobs=require 'EmberRoutesProbe/TaskJobs'
assert(Jobs.current():create(job),'real JobStore must admit the seat attempt')
local live=Jobs.current():get(job.id) live.payload.step='STOP_CONFIRMED'
assert(Jobs.current():update(live.id,live.revision,{payload=live.payload}))
live=Jobs.current():get(job.id) live.payload.step='ACTING' live.payload.leisure.started=true
assert(Jobs.current():update(live.id,live.revision,{payload=live.payload}))
assert(Record.valid(Jobs.current():get(job.id)),'saved active SIT remains loadable')
live.payload.leisure.activity='FITNESS'
assert(not Record.valid(live),'other leisure cannot smuggle a furniture proof')
live.payload.leisure.activity='SIT' live.payload.site.parts={}
assert(not Record.valid(live),'invalid furniture identity is still rejected')
print('P3.5 full record admission: reserved SIT survives request/start/save; invalid proofs rejected')
