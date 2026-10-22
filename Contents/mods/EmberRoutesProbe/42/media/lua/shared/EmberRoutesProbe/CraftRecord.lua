-- Pure persisted-record contract, shared by craft execution and the one claims authority.
local Record={}
local states={RUNNING=true,PAUSED=true,RECONCILE_REQUIRED=true,DONE=true,CANCELLED=true}
local phases={COLLECTING=true,CRAFTING=true,COMMITTING=true,CONFIRMED=true,RETURNING=true,
    RECONCILE_REQUIRED=true,DONE=true,CANCELLED=true}
local function integer(value) return type(value)=="number" and value==value and math.abs(value)~=math.huge and value==math.floor(value) end
local function production(id,r)
    if r.npcId~=id or type(id)~="string" or type(r.id)~="string" or type(r.requester)~="string"
        or type(r.recipeId)~="string" or type(r.signature)~="string" or type(r.settlementId)~="string"
        or type(r.product)~="string" or type(r.recipeName)~="string"
        or not states[r.state] or (not phases[r.phase] and r.phase~="PLANNING")
        or not integer(r.generation) or r.generation<0 or type(r.released)~="boolean"
        or not integer(r.requested) or r.requested<1 or r.requested>9999
        or not integer(r.target) or r.target<r.requested or r.target>10030
        or not integer(r.unitYield) or r.unitYield<1 or r.unitYield>32
        or not integer(r.produced) or not integer(r.delivered) or r.delivered<0 or r.delivered>r.produced or r.produced>r.target
        or (r.released and (r.uncertain or (r.state~="DONE" and r.state~="CANCELLED"))) then return false end
    if r.benchId~=nil and type(r.benchId)~="string" then return false end
    if r.surface~=nil then
        if type(r.surface)~="table" or not r.benchId then return false end
        for _,key in ipairs({"x","y","z"}) do if not integer(r.surface[key]) then return false end end
    end
    local seen={}
    for _,name in ipairs({"materials","tools","outputs"}) do
        local list=r[name] if type(list)~="table" or #list>(name=="outputs" and 128 or 64) then return false end
        local count=0
        for key,entry in pairs(list) do
            if not integer(key) or key<1 or key>#list or type(entry)~="table" or not integer(entry.id) or seen[entry.id] then return false end
            seen[entry.id]=true count=count+1
            if name~="outputs" and (not integer(entry.slot) or entry.slot<0 or (entry.source~=nil and type(entry.source)~="string")) then return false end
            if name=="outputs" and (type(entry.fullType)~="string" or type(entry.delivered)~="boolean") then return false end
        end
        if count~=#list then return false end
    end
    return true
end
function Record.valid(id,r)
    if type(r)=="table" and r.format==3 then return production(id,r) end
    if type(r)~="table" or r.npcId~=id or type(id)~="string" or (r.format~=1 and r.format~=2)
        or type(r.id)~="string" or type(r.requester)~="string" or type(r.benchId)~="string"
        or not integer(r.generation) or r.generation<0 or not integer(r.materialId) or not integer(r.toolId)
        or r.materialId==r.toolId or not states[r.state] or not phases[r.phase]
        or type(r.released)~="boolean" or type(r.outputIds)~="table" or #r.outputIds>8
        or (r.released and (r.uncertain or (r.state~="DONE" and r.state~="CANCELLED"))) then return false end
    if r.format==2 and (type(r.source)~="string" or type(r.settlementId)~="string" or type(r.toolFromNpc)~="boolean"
        or (not r.toolFromNpc and type(r.toolSource)~="string")
        or (r.destination~=nil and type(r.destination)~="string")
        or (r.toolDestination~=nil and type(r.toolDestination)~="string")) then return false end
    if r.surface~=nil then
        if type(r.surface)~="table" then return false end
        for _,key in ipairs({"x","y","z"}) do
            if not integer(r.surface[key]) or math.abs(r.surface[key])>10000000 then return false end
        end
    end
    local seen,count={[r.materialId]=true,[r.toolId]=true},0
    for key,value in pairs(r.outputIds) do
        if not integer(key) or key<1 or key>#r.outputIds or not integer(value) or seen[value] then return false end
        seen[value]=true count=count+1
    end
    return count==#r.outputIds and (not r.made or count==1)
end
function Record.resources(r)
    if r.format==3 then
        local result={}
        if r.benchId then result[#result+1]="craft-surface:"..r.benchId end
        for _,name in ipairs({"materials","tools","outputs"}) do
            for _,entry in ipairs(r[name]) do result[#result+1]="item:"..entry.id end
        end
        return result
    end
    local result={"item:"..r.materialId,"item:"..r.toolId,"craft-surface:"..r.benchId}
    for _,id in ipairs(r.outputIds) do result[#result+1]="item:"..id end
    return result
end
function Record.records(root)
    local saved=root.craftProbes
    if not saved then return {} end
    if saved.format~=1 or type(saved.byNpc)~="table" then error("CRAFT_RECORD_INVALID") end
    for id,r in pairs(saved.byNpc) do if not Record.valid(id,r) then error("CRAFT_RECORD_INVALID") end end
    return saved.byNpc
end
return Record
