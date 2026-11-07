-- Bounded diagnostic samples; no per-frame printing or persistent history.
local Metrics={}
function Metrics.new()
    local ring,cursor,count={},0,0
    local api={operations=0,slices=0,claims=0}
    function api:record(ms,ops,slices)
        cursor=cursor%128+1 count=math.min(count+1,128)
        ring[cursor]=ms self.operations=self.operations+ops self.slices=self.slices+slices
    end
    function api:snapshot()
        local values={} for i=1,count do values[i]=ring[i] end table.sort(values)
        return {samples=count,p95=values[math.ceil(count*0.95)] or 0,p99=values[math.ceil(count*0.99)] or 0,
            maximum=values[count] or 0,operations=self.operations,slices=self.slices,claims=self.claims}
    end
    return api
end
return Metrics
