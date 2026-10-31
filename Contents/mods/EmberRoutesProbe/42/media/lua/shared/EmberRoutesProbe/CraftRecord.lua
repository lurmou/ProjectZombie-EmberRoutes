-- Pure persisted-record contract, shared by craft execution and the one claims authority.
local Validate=require 'EmberRoutesProbe/Validate'
local Record={}
local states={RUNNING=true,PAUSED=true,RECONCILE_REQUIRED=true,DONE=true,CANCELLED=true}
local phases={COLLECTING=true,CRAFTING=true,COMMITTING=true,CONFIRMED=true,RETURNING=true,
    RECONCILE_REQUIRED=true,DONE=true,CANCELLED=true}
local integer=Validate.integer
local function production(id,r)
    if not require('EmberRoutesProbe/ProductionYield').valid(r) then return false end
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
    if r.origin~=nil then
        if type(r.origin)~="table" or r.origin.kind~="MAINTAIN_STOCK" or type(r.origin.ruleId)~="string"
            or not integer(r.origin.cycleSequence) or r.origin.cycleSequence<1 then return false end
    end
    if r.surface~=nil then
        if type(r.surface)~="table" or not r.benchId then return false end
        for _,key in ipairs({"x","y","z"}) do if not integer(r.surface[key]) then return false end end
    end
    if r.chain~=nil then
        local chain=r.chain
        if type(chain)~="table" or chain.format~=1 or not integer(chain.index) or type(chain.nodes)~="table"
            or #chain.nodes>64 or chain.index<0 or chain.index>#chain.nodes or type(chain.goal)~="table" then return false end
        local goal=chain.goal
        for _,key in ipairs({"recipeId","recipeName","product","signature"}) do if type(goal[key])~="string" then return false end end
        for _,key in ipairs({"requested","target","produced","delivered","unitYield"}) do if not integer(goal[key]) then return false end end
        if goal.requested<1 or goal.requested>9999 or goal.target<goal.requested or goal.target>10030
            or goal.produced<0 or goal.delivered<0 or goal.delivered>goal.produced or goal.produced>goal.target
            or goal.unitYield<1 or goal.unitYield>32 then return false end
        local nodeCount=0
        for key,node in pairs(chain.nodes) do
            if not integer(key) or key<1 or key>#chain.nodes then return false end nodeCount=nodeCount+1
            if type(node)~="table" or type(node.recipeId)~="string" or type(node.signature)~="string"
                or not integer(node.requested) or node.requested<1 or node.requested>10030 then return false end
            if type(node.product)~="string" or type(node.recipeName)~="string" or type(node.surface)~="boolean"
                or not integer(node.unitYield) or node.unitYield<1 or node.unitYield>32 then return false end
            if node.surface then
                if type(node.benchId)~="string" or type(node.location)~="table" then return false end
                for _,axis in ipairs({"x","y","z"}) do if not integer(node.location[axis]) then return false end end
            elseif node.location~=nil or node.benchId~=nil then return false end
        end
        if nodeCount~=#chain.nodes or (#chain.nodes>0 and chain.nodes[#chain.nodes].recipeId~=goal.recipeId) then return false end
        if chain.blocker and (type(chain.blocker)~="table" or type(chain.blocker.recipeId)~="string" or type(chain.blocker.recipeName)~="string") then return false end
        if type(r.held)~="table" or #r.held>256 then return false end
    elseif r.held~=nil then return false end
    local seen={}
    for _,name in ipairs({"materials","tools","outputs","held"}) do
        if name=="held" and not r.chain then break end
        local list=r[name] if type(list)~="table" or #list>(name=="held" and 256 or name=="outputs" and 128 or 64) then return false end
        local count=0
        for key,entry in pairs(list) do
            if not integer(key) or key<1 or key>#list or type(entry)~="table" or not integer(entry.id) or seen[entry.id] then return false end
            seen[entry.id]=true count=count+1
            if name~="outputs" and name~="held" and (not integer(entry.slot) or entry.slot<0 or (entry.source~=nil and type(entry.source)~="string")) then return false end
            if name=="held" and type(entry.fullType)~="string" then return false end
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
        if require('EmberRoutesProbe/ProductionYield').assetFree(r) then return {} end
        local result={}
        if r.benchId then result[#result+1]="craft-surface:"..r.benchId end
        for _,name in ipairs({"materials","tools","outputs","held"}) do
            for _,entry in ipairs(r[name] or {}) do result[#result+1]="item:"..entry.id end
        end
        return result
    end
    local result={"item:"..r.materialId,"item:"..r.toolId,"craft-surface:"..r.benchId}
    for _,id in ipairs(r.outputIds) do result[#result+1]="item:"..id end
    return result
end
function Record.validateAll(records)
    if type(records)~="table" then return false end
    for id,r in pairs(records) do if not Record.valid(id,r) then return false end end
    return true
end
return Record
