local Log=require "EmberRoutesProbe/Log"
local Metrics={enabled=false,LIMIT=2048,WINDOW=128}
local samples={}
local clock
local keys={["ui.open"]=true,["ui.query"]=true,["ui.update"]=true,["ui.panel"]=true,
    ["ui.items"]=true,["ui.sources"]=true,["index.slice"]=true}
function Metrics.start()
    local bridge=EmberRoutesProbeJava -- Registered by this package's Main/Exposer.
    if not bridge or type(bridge.diagnosticTimeNanos)~="function" then return false end
    clock=bridge.diagnosticTimeNanos samples={} Metrics.enabled=true
    return true
end
function Metrics.begin(key)
    if not Metrics.enabled or not keys[key] or (samples[key] and samples[key].count>=Metrics.LIMIT) then return nil end
    return clock()
end
function Metrics.finish(key,started)
    if not started or not Metrics.enabled or not keys[key] then return end
    local elapsed=(clock()-started)/1000000
    if elapsed<0 then return end
    local s=samples[key]
    if not s then s={count=0,total=0,max=0,recent={}} samples[key]=s end
    if s.count>=Metrics.LIMIT then return end
    s.count=s.count+1 s.total=s.total+elapsed s.max=math.max(s.max,elapsed)
    s.recent[(s.count-1)%Metrics.WINDOW+1]=elapsed
end
function Metrics.report()
    local result={}
    for key,s in pairs(samples) do
        local recent={} for i,v in ipairs(s.recent) do recent[i]=v end table.sort(recent)
        result[key]={count=s.count,averageMs=s.total/s.count,maxMs=s.max,
            recentP95Ms=recent[math.ceil(#recent*0.95)],capped=s.count>=Metrics.LIMIT}
    end
    return result
end
function Metrics.stop()
    Metrics.enabled=false
    local result=Metrics.report()
    for key,s in pairs(result) do
        Log.write("WAREHOUSE_PERF",string.format("CPU %s samples=%d avgMs=%.4f maxMs=%.4f recentP95Ms=%.4f capped=%s",
            key,s.count,s.averageMs,s.maxMs,s.recentP95Ms,tostring(s.capped)))
    end
    return result
end
return Metrics
