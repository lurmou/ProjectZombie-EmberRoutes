local P=require 'EmberRoutesProbe/Work/WorkOverviewPresenter'
local n=0
local function check(v,m) assert(v,m) n=n+1 end
local rows={
 {id='ORDER:a',kind='ORDER',title='Planks',state='WAITING'},
 {id='ORDER:a',kind='CRAFT',title='Planks',state='WAITING'},
 {id='FIELD_WORK:b',kind='FIELD_WORK',npcId='n1',workCategory='lumberjack',title='Logging',state='SUSPENDED',reason='FIELD_TOOL_MISSING',bucket='waiting'},
 {id='CRAFT:c',kind='CRAFT',npcId='n2',title='Fork',state='RUNNING',bucket='active'},
 {id='ORDER:d',kind='ORDER',title='Paused',state='PAUSED'},
 {id='ORDER:e',kind='ORDER',state='DONE',closed=true},
 {id='HAUL:f',kind='HAUL',npcId='n3',state='PAUSED',bucket='paused'},
 {id='ORDER:g',kind='ORDER',state='CANCELLED'}}
local problems={{id='water:home',affected={'n1','n2','n3'}},{id='water:home'}}
local s=P.project(rows,{{id='n1',name='One',isBleeding=true}},problems)
check(#s.works==5,'one domain key per work; closed and cancelled excluded')
check(s.counts.waiting==1 and s.counts.blocked==1 and s.counts.paused==2,'counts distinguish assigned/unassigned and pause')
check(#s.problems==1,'three affected people remain one problem')
check(s.byNpc.n1.title=='Logging' and s.byNpc.n1.state=='blocked','shared personnel title/state')
check(s.alerts[1].kind=='health' and s.alerts[2].kind=='blocked' and s.alerts[3].kind=='waiting','alert priority')
check(P.visible(nil,'idle') and not P.visible(s.byNpc.n1,'idle'),'idle is absence of work')
check(not P.visible({state='waiting'},'idle') and not P.visible({state='paused'},'working'),'waiting and paused only in all filter')
check(P.state({id='x',npcId='n',state='SUSPENDED',bucket='waiting'})=='waiting','waiting duration is not blocking evidence')
check(P.state({id='FIELD_WORK:user',kind='FIELD_WORK',npcId='n',state='SUSPENDED',bucket='waiting',reason='USER'})=='waiting','user body stop is not a fabricated blocker')
local commandCalls={}
package.loaded['EmberRoutesProbe/Warehouse/OrderMonitorService']={command=function(_,_,id,generation,action)
 commandCalls[#commandCalls+1]={id,generation,action} return 'QUEUED' end}
local job={providerType='FIELD_WORK',id='j',npcId='n',scopeId='s',revision=7}
package.loaded['EmberRoutesProbe/Runtime/TaskJobs']={current=function() return {get=function() return job end} end}
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger']={view=function() return {} end}
local stopped
package.loaded['EmberRoutesProbe/Runtime/TaskRuntime']={current=function() return {stopJob=function(_,npc,id,reason) stopped={npc,id,reason} return true end} end}
local A=require 'EmberRoutesProbe/Work/WorkCommandAdapter'
local field={id='FIELD_WORK:j',jobId='j',npcId='n',generation=7,kind='FIELD_WORK',bucket='active',carrierAvailable=true,readOnly=true}
check(A.capabilities(field).stopBody and not A.capabilities(field).resume,'field has body stop, no durable pause/resume')
check(A.command({},'s',field,'stopBody')=='STOP_REQUESTED' and stopped[2]=='j','field routes through stopJob')
job.revision=8 stopped=nil
check(A.command({},'s',field,'stopBody')=='TASK_CHANGED' and not stopped,'stale field revision rejected')
check(A.command({},'s',{id='ORDER:p',generation='ORDER:4',kind='ORDER',canCancel=true},'return')=='QUEUED','public cancel uses existing service')
check(commandCalls[1][1]=='ORDER:p' and commandCalls[1][2]=='ORDER:4','exact monitor ID and generation forwarded')
print('ui-distributed-work: '..n..' PASS; detached facts and command seams')
