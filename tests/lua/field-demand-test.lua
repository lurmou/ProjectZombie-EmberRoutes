local n=0 local function check(v,m) n=n+1 assert(v,m) end
local root={} local count=0 local enabled=false local available=false local supplied=false
local loaded=true local stain=true local incomplete=false local now=0 local notifications=0
local entry={id='s',revision=1,areas={{x=0,y=0,w=10,h=10}}}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end}
local entries={entry}
package.loaded['EmberRoutesProbe/SettlementLedger']={list=function() return entries end,view=function(_,id)
    for _,e in ipairs(entries) do if e.id==id then return e end end
end}
package.loaded['EmberRoutesProbe/SettlementGeometry']={inside=function(_,x,y) return x>=0 and x<10 and y>=0 and y<10 end}
package.loaded['EmberRoutesProbe/FieldSpatial']={chunk=function() return loaded and {} or nil end,
    square=function() return loaded and {} or nil end}
package.loaded['EmberRoutesProbe/FieldDiscovery']={allowed=function() return true end}
package.loaded['EmberRoutesProbe/LaborSignals']={changed=function() notifications=notifications+1 end}
package.loaded['EmberRoutesProbe/ToolDiscovery']={findSupplies=function()
    if supplied then return {ready=true,requirements={}} end
    return nil,incomplete and 'FIELD_OBSERVING' or 'FIELD_TOOLS_UNAVAILABLE',
        {complete=not incomplete,missingRoles={'CLEAN_TOOL','CLEAN_FLUID'}}
end}
EmberRoutesProbeJava={workerCount=function() return count end,workerIdAt=function() return 'a' end,
    cleaningScanStains=function() return stain and {{x=1,y=1,z=0}} or {} end,
    cleaningSquareHasStains=function() return stain end}
getText=function(k,...) return k end
local D=require 'EmberRoutesProbe/FieldDemand'
local function tick()
    now=now+2000
    D.advance({},now,function() if available then return {handle={}},entry end end,
        function() return {cleaning=enabled and 2 or 0} end)
end
tick()
local row=D.rows('s')[1]
check(row and row.observedCount==1 and row.reason=='FIELD_NO_WORKER','confirmed demand is visible without any NPC')
check(not root.taskJobs and not root.toolCustody,'observation creates no Job or custody')
check(row.coverage=='PARTIAL' and row.readOnly,'limited observation is explicitly partial and cannot submit commands')
count=1 tick()
check(D.rows('s')[1].reason=='FIELD_POLICY_DISABLED','priority zero changes explanation, not source existence')
enabled=true tick()
check(D.rows('s')[1].reason=='FIELD_WORKER_BUSY','busy worker does not hide demand')
available=true tick()
row=D.rows('s')[1]
check(row.reason=='FIELD_TOOLS_UNAVAILABLE' and #row.missingRoles==2,'known tool roles are explained')
incomplete=true tick()
check(D.rows('s')[1].state=='OBSERVING','incomplete inventory cannot be called definite shortage')
supplied=true tick()
check(D.rows('s')[1].state=='READY','supply recovery becomes visible without opening page')
root.taskJobs={byId={j={providerType='FIELD_WORK',scopeId='s',state='RUNNING',payload={target={kind='STAIN',x=1,y=1,z=0}}}}}
tick()
check(#D.rows('s')==0,'claimed target is not counted twice as pending demand')
root.taskJobs=nil loaded=false tick()
check(D.rows('s')[1].state=='OBSERVING' and D.rows('s')[1].staleCount==1,'unloaded confirmed source stays visible as stale')
loaded=true stain=false tick()
check(#D.rows('s')==0,'loaded source confirmed resolved leaves pending list')
stain=true tick()
row=D.rows('s')[1] row.observedCount=999
check(D.rows('s')[1].observedCount==1,'monitor snapshots cannot mutate demand facts')
entries={{id='other',revision=1,areas=entry.areas}} tick()
check(#D.rows('s')==0,'removed settlement cannot retain stale demand while other settlements exist')
root={} loaded=false
check(#D.rows('s')==0,'world change discards only derived observations')
check(not root.taskJobs and notifications>0,'changes notify without creating execution facts')
print('PASS '..n..' independent cleaning demand checks; world/native workers mocked')
