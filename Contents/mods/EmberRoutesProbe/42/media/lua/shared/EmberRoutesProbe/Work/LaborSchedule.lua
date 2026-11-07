local Schedule={}
local methods={} methods.__index=methods
function Schedule.new() return setmetatable({order={},present={},cursor=0},methods) end
function methods:add(id)
    if self.present[id] then return end
    self.present[id]=true self.order[#self.order+1]=id
end
function methods:remove(id)
    if not self.present[id] then return end self.present[id]=nil
    for i,value in ipairs(self.order) do if value==id then
        table.remove(self.order,i) if i<=self.cursor then self.cursor=self.cursor-1 end break
    end end
end
function methods:step(budget,callback)
    local limit=math.min(math.max(0,budget),#self.order)
    for _=1,limit do
        if #self.order==0 then break end
        self.cursor=self.cursor%#self.order+1 callback(self.order[self.cursor])
    end
    return limit
end
return Schedule
