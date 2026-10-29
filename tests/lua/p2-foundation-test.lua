local checks=0
local function check(value,label) checks=checks+1 assert(value,label) end
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
package.loaded['EmberRoutesProbe/LaborSignals']={watch=function() end}
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Record=require 'EmberRoutesProbe/SelfCareRecord'
local store=Jobs.current()
check(store==Jobs.current(),'world shares exact store instance')
check(store:create(Record.create('care','a')),'personal record accepted')
local Business=require 'EmberRoutesProbe/BusinessJobs'
check(Business.crafts().a==nil,'personal record is not a craft')
Business.flush()
check(store:get('care').state=='PREPARING','labor flush leaves personal state unchanged')
local p=assert(Record.begin(store:get('care'),'EAT',{jobId='original'}))
check(p.attemptId=='care:1' and p.resume.jobId=='original','attempt and recovery identity')
local retained=store:get('care') retained.payload=p
check(not Record.begin(retained,'DRINK'),'cannot replace pending attempt')
retained.payload.step='IDLE' retained.effects='UNKNOWN'
check(not Record.begin(retained,'DRINK'),'cannot replace unknown consumption')
check(not store:create(Record.create('care2','a')),'one recurring routine per NPC')
for i=1,512 do
    assert(store:create({id='work'..i,npcId='w',providerType='OTHER',scopeId='s',revision=1,
        state='PREPARING',effects='KNOWN',obligations={},payload={}}),'ordinary capacity')
end
check(#store:forNpc('w')==512,'ordinary capacity fixture filled')
check(store:create(Record.create('care-b','b')),'full work history does not block personal routine')
check(#Jobs.current():forNpc('b')==1,'shared secondary index sees new provider')
local reopened=assert(require('EmberRoutesProbe/JobStore').open(root))
check(reopened:get('care-b')~=nil,'capacity policy survives reopen')
local Tree=require 'EmberRoutesProbe/BehaviorTree'
local n=0
local t=assert(Tree.new({kind='Sequence',children={{kind='Action',run=function() n=n+1 return 'Success' end},
    {kind='Action',run=function(c) return c.done and 'Success' or 'Running' end}}}))
check(Tree.tick(t,{}, {nodes=1})=='Running','budget exhaustion yields')
check(Tree.tick(t,{}, {nodes=4})=='Running' and n==1,'sequence retains cursor')
check(Tree.tick(t,{done=true},{nodes=4})=='Success' and n==1,'completed leaf never replays')
local cycle={kind='Subtree',children={}} cycle.children[1]=cycle
check(not Tree.new(cycle),'cyclic structure rejected')
local fallback=assert(Tree.new({kind='Fallback',children={{kind='Action',run=function() return 'Failure' end},
    {kind='Action',run=function() error('must wait for cleanup') end}}}))
check(Tree.tick(fallback,{cleanupPending=true},{nodes=8})=='Running','fallback waits for cleanup')
local effectCount=0
local gated=assert(Tree.new({kind='Sequence',children={{kind='Action',run=function()
    effectCount=effectCount+1 return 'Success' end}}}))
local blocked={cleanupPending=true}
check(Tree.tick(gated,blocked,{nodes=8})=='Running','completed effect waits for cleanup')
blocked.cleanupPending=false
check(Tree.tick(gated,blocked,{nodes=8})=='Success' and effectCount==1,'cleanup wait cannot replay completed effect')
local reused={kind='Condition',run=function() return 'Success' end}
check(not Tree.new({kind='Sequence',children={reused,reused}}),'aliased nodes cannot share cursor positions')
local Policy=require 'EmberRoutesProbe/NeedsPolicy'
local sample={hunger=0.5,thirst=0.4,fatigue=0.1,endurance=1}
check(Policy.choose(sample,nil,{safe=false},{EAT=true})==nil,'unsafe filters personal candidates')
check(Policy.choose(sample,nil,{safe=true},{DRINK=true})=='DRINK','resource validity precedes interruption')
check(Policy.choose(sample,'DRINK',{safe=true},{EAT=true,DRINK=true})=='DRINK','hysteresis keeps viable action')
check(Policy.satisfied('REST',{endurance=0.85}),'rest measures endurance')
check(not Policy.satisfied('SLEEP',{fatigue=0.7}),'endurance does not stand in for fatigue')
local Claims=require 'EmberRoutesProbe/LaborStore'
local personal=root.taskJobs.byId.care
personal.payload=p personal.payload.claims={'item:19'}
check(Claims.data()~=nil and Claims.owner(19).taskId=='care','personal claims rebuild with labor authority')
local token=assert(Claims.claimPersonal(personal))
check(Claims.validPersonal(personal,token,'item:19'),'current attempt owns original')
local other=root.taskJobs.byId['care-b']
other.payload=assert(Record.begin(other,'DRINK')) other.payload.claims={'item:19'}
check(not Claims.claimPersonal(other),'second NPC cannot take claimed food')
personal.effects='UNKNOWN'
check(not Claims.finishPersonal(personal,token) and Claims.owner(19)~=nil,'unknown consumption retains custody')
personal.effects='KNOWN' personal.obligations={returnItem=true}
check(not Claims.finishPersonal(personal,token),'return obligation retains original')
personal.obligations={}
check(Claims.finishPersonal(personal,token) and Claims.owner(19)==nil,'known cleared custody releases exact token')
check(#Jobs.current():get('care').payload.claims==0,'released custody cannot reappear after load')
root={}
check(Jobs.current()~=store and #Jobs.current():forNpc('a')==0,'world identity retires old indexes')
check(not Claims.validPersonal(personal,token),'old world token cannot act in new world')
print('PASS '..checks..' P2 storage/tree/policy checks; native behavior NOT RUN')
