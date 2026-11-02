-- Host cost comparison only; reflective JavaFunction bridge is not game Exposer.
EmberRoutesProbeJava=ERDispatchTestBridge
local root={}
package.loaded['EmberRoutesProbe/ContainerRegistry']={data=function() return root end,listeners={},inventoryListeners={}}
package.loaded['EmberRoutesProbe/SettlementLedger']={listeners={}}
local ids={} for i=1,128 do ids[i]='container-'..i end
package.loaded['EmberRoutesProbe/SettlementMembership']={query=function() return ids end}
local Selector=require 'EmberRoutesProbe/WorkSelector'
local Directory=require 'EmberRoutesProbe/TaskDirectory'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local candidates={} for i=1,16 do candidates[i]={key='job-'..i,category=i%2==0 and 'a' or 'b',score=i,allowed=true} end
local priorities={a=2,b=3}
local proof={effects='KNOWN',obligationsCleared=true}
local d=Directory.new()
local function directory()
    d:upsert('offer',1,'a','scope') assert(d:claim('offer',1,'npc','job')) assert(d:release('offer','job',proof))
end
local token=Wake.capture({id='scope'})
for i=1,1000 do Selector.choose(candidates,priorities) directory() Wake.changed(token) end
local function measure(label,run,n)
    local start=_ERTestNanos() for i=1,n do run() end
    print('HOST '..label..' '..n..' calls: '..tostring((_ERTestNanos()-start)/1000000)..' ms; game NOT RUN')
end
for _,width in ipairs({1,4,16}) do
    candidates={}
    for i=1,width do candidates[i]={key='job-'..i,category=i%2==0 and 'a' or 'b',score=i,allowed=true} end
    for i=1,1000 do Selector.choose(candidates,priorities) end
    measure('choose'..width,function() Selector.choose(candidates,priorities) end,20000)
end
measure('directory-cycle',directory,20000)
measure('wake128',function() Wake.changed(token) end,10000)
