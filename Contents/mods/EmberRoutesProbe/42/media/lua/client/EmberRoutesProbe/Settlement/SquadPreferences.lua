-- Cosmetic, character-owned preferences; never changes membership or follow slots.
local P={} P.__index=P
local KEY='EmberRoutesSquadHUD'
local scales={[0.85]=true,[1]=true,[1.2]=true,[1.4]=true}
local function finite(n) return type(n)=='number' and n==n and math.abs(n)<1e8 end
local function valid(value)
    if type(value)~='table' or value.format~=1 or not scales[value.scale] or not scales[value.buttonScale]
        or type(value.order)~='table' or type(value.callsigns)~='table' then return false end
    if value.x~=nil and (not finite(value.x) or not finite(value.y) or value.x<0 or value.x>1 or value.y<0 or value.y>1) then return false end
    if value.x==nil and value.y~=nil then return false end
    local seen={} local count=0
    for i,id in pairs(value.order) do
        count=count+1
        if count>3 or type(i)~='number' or i<1 or i>3 or i~=math.floor(i)
            or type(id)~='string' or id=='' or seen[id] then return false end
        seen[id]=true
    end
    if count~=#value.order then return false end
    count=0
    for id,name in pairs(value.callsigns) do
        count=count+1
        if count>512 or type(id)~='string' or type(name)~='string' or #name>96 then return false end
    end
    return true
end
local function copy(v)
    if type(v)~='table' then return v end
    local out={} for k,x in pairs(v) do out[k]=copy(x) end return out
end
local function defaults() return {format=1,scale=1,buttonScale=1,order={},callsigns={}} end
function P.new(actor)
    local raw=actor:getModData()[KEY]
    return setmetatable({actor=actor,value=raw and valid(raw) and copy(raw) or defaults(),
        writable=raw==nil or valid(raw)},P)
end
function P:save()
    local raw=self.actor:getModData()[KEY]
    if not self.writable or raw~=nil and not valid(raw) then self.writable=false return false end
    self.actor:getModData()[KEY]=copy(self.value) return true
end
function P:setScale(field,value)
    if (field~='scale' and field~='buttonScale') or not scales[value] or not self.writable then return false end
    self.value[field]=value return self:save()
end
function P:position(width,height,screenW,screenH)
    local x=self.value.x and self.value.x*screenW or 70
    local y=self.value.y and self.value.y*screenH or 50
    return math.floor(math.max(0,math.min(x,screenW-width))),math.floor(math.max(0,math.min(y,screenH-height)))
end
function P:setPosition(x,y,screenW,screenH)
    if not self.writable or screenW<=0 or screenH<=0 or not finite(x) or not finite(y) then return false end
    self.value.x=math.max(0,math.min(1,x/screenW)) self.value.y=math.max(0,math.min(1,y/screenH))
    return self:save()
end
function P:ordered(rows)
    local result,seen,byId={},{},{}
    for _,row in ipairs(rows) do byId[row.id]=row end
    for _,id in ipairs(self.value.order) do if byId[id] then result[#result+1]=byId[id] seen[id]=true end end
    for _,row in ipairs(rows) do if not seen[row.id] then result[#result+1]=row end end
    return result
end
function P:reorder(rows,id,index)
    if not self.writable or type(index)~='number' then return false end
    local order={} local found=false
    for _,row in ipairs(self:ordered(rows)) do
        if row.id==id then found=true else order[#order+1]=row.id end
    end
    if not found then return false end
    table.insert(order,math.max(1,math.min(#order+1,math.floor(index))),id)
    self.value.order=order return self:save()
end
function P:setCallsign(id,text)
    if not self.writable or type(id)~='string' or type(text)~='string' then return false end
    text=text:gsub('[%c<>]',''):gsub('^%s+',''):gsub('%s+$','')
    if #text>96 then return false end -- native input separately limits to 24 characters
    if text~='' and not self.value.callsigns[id] then
        local count=0 for _ in pairs(self.value.callsigns) do count=count+1 end
        if count>=512 then return false end
    end
    self.value.callsigns[id]=text~='' and text or nil return self:save()
end
function P:resetLayout()
    if not self.writable then return false end
    self.value.x=nil self.value.y=nil self.value.scale=1 self.value.buttonScale=1 self.value.order={}
    return self:save()
end
return P
