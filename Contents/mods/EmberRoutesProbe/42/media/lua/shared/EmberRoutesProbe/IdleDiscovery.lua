-- Transient per-NPC ordinary discovery pacing. Never owns bodies or effects.
local I={}
function I.new()
    local rows={} local count=0
    local api={}
    function api:clear(id) if rows[id] then rows[id]=nil count=count-1 end end
    function api:due(id,now,stamp,revision,changed)
        local r=rows[id]
        if not r then return true end
        if now<r.since then self:clear(id) return true end
        if r.stamp~=stamp or r.revision~=revision and changed(r.watch) then
            self:clear(id) return true
        end
        r.revision=revision
        if not r.sleeping then return true end
        if now>=r.due then r.sleeping=false return true end
        return false
    end
    function api:empty(id,now,stamp,revision,watch,complete,retryAt)
        if not complete then self:clear(id) return end
        local r=rows[id]
        if not r then
            if count>=256 then
                local oldest,at
                for key,value in pairs(rows) do if not at or value.since<at then oldest,at=key,value.since end end
                self:clear(oldest)
            end
            r={since=now,stamp=stamp} rows[id]=r count=count+1
        elseif r.stamp~=stamp then r.since,r.stamp=now,stamp end
        r.revision,r.watch=revision,watch
        if now-r.since>=10000 then
            local offset=0 for i=1,#id do offset=(offset+string.byte(id,i))%5000 end
            r.sleeping=true r.due=now+15000+offset
            if retryAt and retryAt>now then r.due=math.min(r.due,retryAt) end
        end
    end
    return api
end
return I
