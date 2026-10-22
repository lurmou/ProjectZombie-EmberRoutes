local Filter=require "EmberRoutesProbe/StorageFilter"
local Editor={}
function Editor.new(config,descriptions)
    local copy=Filter.copy(config)
    return {draft=copy or Filter.new(),descriptions=descriptions or {},status=""}
end
function Editor.value(config,id)
    local current=id
    while current do
        if config.groups[current]~=nil then return config.groups[current] end
        current=Filter.nodes[current] and Filter.nodes[current].parent
    end
    return false
end
function Editor.rows(model)
    local rows,seen={},{}
    rows[#rows+1]={kind="enabled",label="enabled"}
    rows[#rows+1]={kind="private",label="private"}
    for _,id in ipairs(Filter.treeOrder()) do
        local node=Filter.nodes[id]
        rows[#rows+1]={kind="group",id=id,depth=node.depth}
        for _,description in ipairs(model.descriptions) do
            if description.node==id then
                rows[#rows+1]={kind="type",id=description.fullType,depth=node.depth+1}
                seen[description.fullType]=true
            end
        end
    end
    local extra={}
    for id in pairs(model.draft.types) do if not seen[id] then extra[#extra+1]=id end end
    table.sort(extra)
    for _,id in ipairs(extra) do rows[#rows+1]={kind="type",id=id,depth=1} end
    return rows
end
function Editor.mark(model,row)
    local config=model.draft
    if row.kind=="enabled" then return config.enabled and "[x]" or "[ ]" end
    if row.kind=="private" then return config.private and "[x]" or "[ ]" end
    if row.kind=="type" then
        if config.types[row.id]==nil then return "[~]" end
        return config.types[row.id] and "[x]" or "[ ]"
    end
    local value=Editor.value(config,row.id)
    for _,id in ipairs(Filter.order) do
        local parent=Filter.nodes[id].parent
        while parent do
            if parent==row.id and Editor.value(config,id)~=value then return "[-]" end
            parent=Filter.nodes[parent].parent
        end
    end
    return value and "[x]" or "[ ]"
end
function Editor.toggle(model,row)
    local config=model.draft
    if row.kind=="enabled" then config.enabled=not config.enabled
    elseif row.kind=="private" then config.private=not config.private
    elseif row.kind=="group" then Filter.setGroup(config,row.id,Editor.mark(model,row)~="[x]")
    elseif row.kind=="type" then
        local value=config.types[row.id]
        if value==nil then config.types[row.id]=true
        elseif value then config.types[row.id]=false
        else config.types[row.id]=nil end
    end
end
function Editor.all(model,value)
    model.draft.groups,model.draft.types={},{}
    for _,id in ipairs(Filter.order) do if not Filter.nodes[id].parent then model.draft.groups[id]=value end end
end
return Editor
