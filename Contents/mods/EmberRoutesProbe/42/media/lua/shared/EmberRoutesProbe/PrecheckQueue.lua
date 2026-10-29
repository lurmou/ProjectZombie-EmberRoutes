-- Cooperative private planning, independent of the roster's decision cursor.
-- Entries and results are transient; no resource claims or body authority.
local Queue={}
function Queue.new(limit)
    local entries,order,cursor={},{},0
    local api={}
    function api:get(id) return entries[id] end
    function api:size() return #order end
    function api:put(id,e)
        if entries[id] or #order>=limit then return false end
        entries[id]=e order[#order+1]=id return true
    end
    function api:remove(id)
        local e=entries[id] if not e then return end
        entries[id]=nil e.request:cancel()
        for i,key in ipairs(order) do if key==id then
            table.remove(order,i) if i<=cursor then cursor=cursor-1 end break
        end end
    end
    function api:clear()
        while #order>0 do self:remove(order[#order]) end
    end
    function api:step(budget,validate,complete,clock)
        if #order==0 then return 0,0,0 end
        local spent,slices=0,0 local started=clock()
        -- Finite attempts also cover ready entries and invalidated requests.
        local attempts=0 local checked={} local idle=0
        while #order>0 and spent<budget and attempts<budget do
            attempts=attempts+1 cursor=cursor%#order+1
            local id=order[cursor] local e=entries[id]
            if not checked[id] then checked[id]=validate(id,e) and 'VALID' or 'INVALID' end
            if checked[id]=='INVALID' then self:remove(id) idle=0
            elseif not e.ready then
                idle=0
                local slice=math.min(8,budget-spent)
                local plan,reason=e.request:step(slice)
                spent=spent+slice slices=slices+1
                if plan or reason then complete(id,e,plan,reason) end
            else idle=idle+1 if idle>=#order then break end end
            if clock()-started>=2 then break end
        end
        return spent,slices,clock()-started
    end
    return api
end
return Queue
