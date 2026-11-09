local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
local Editor={}

function Editor.new(config,descriptions)
    local copy=Filter.copy(config)
    return {draft=copy or Filter.new(),descriptions=descriptions or {},collapsed={},status=""}
end

function Editor.isCollapsed(model,id)
    return model and model.collapsed and model.collapsed[id]==true
end

function Editor.toggleCollapse(model,id)
    if not model then return end
    model.collapsed=model.collapsed or {}
    model.collapsed[id]=not model.collapsed[id]
    return model.collapsed[id]
end

function Editor.collapseAll(model)
    if not model then return end
    model.collapsed = {}
    for _, id in ipairs(Filter.order) do
        if Filter.nodes[id] and Filter.nodes[id].hasChildren then
            model.collapsed[id] = true
        end
    end
end

function Editor.expandAll(model)
    if not model then return end
    model.collapsed = {}
end

function Editor.value(config,id)
    local current=id
    while current do
        if config.groups[current]~=nil then return config.groups[current] end
        current=Filter.nodes[current] and Filter.nodes[current].parent
    end
    return false
end

local function isAncestorCollapsed(model,id)
    local current=Filter.nodes[id] and Filter.nodes[id].parent
    while current do
        if Editor.isCollapsed(model,current) then return true end
        current=Filter.nodes[current] and Filter.nodes[current].parent
    end
    return false
end

function Editor.rows(model, options)
    options = options or {}
    local rows,seen={},{}
    if not options.itemsOnly then
        rows[#rows+1]={kind="enabled",label="enabled"}
        rows[#rows+1]={kind="private",label="private"}
    end

    local query = options.query and string.lower(options.query:gsub("^%s*(.-)%s*$", "%1")) or ""
    local hasQuery = query ~= ""

    for _,id in ipairs(Filter.treeOrder()) do
        local node=Filter.nodes[id]
        local isCollapsed = Editor.isCollapsed(model,id)
        if hasQuery then isCollapsed = false end

        if hasQuery or not isAncestorCollapsed(model,id) then
            local nodeMatches = false
            if hasQuery then
                local label = getTextOrNull and getTextOrNull("IGUI_EmberRoutesProbe_Filter_"..id) or id
                if string.find(string.lower(label), query, 1, true) or string.find(string.lower(id), query, 1, true) then
                    nodeMatches = true
                end
            end

            local matchingChildren = {}
            for _,description in ipairs(model.descriptions) do
                if description.node==id then
                    local itemMatches = true
                    if hasQuery and not nodeMatches then
                        local resolveName=_G.getItemNameFromFullType
                        local iName = type(resolveName)=="function" and resolveName(description.fullType) or description.fullType
                        itemMatches = string.find(string.lower(iName or ""), query, 1, true) or string.find(string.lower(description.fullType), query, 1, true)
                    end
                    if itemMatches then
                        matchingChildren[#matchingChildren+1] = description.fullType
                    end
                end
            end

            if not hasQuery or nodeMatches or #matchingChildren > 0 then
                rows[#rows+1]={
                    kind="group",
                    id=id,
                    depth=node.depth,
                    hasChildren=node.hasChildren==true,
                    collapsed=isCollapsed
                }
                if not isCollapsed or hasQuery then
                    for _,ft in ipairs(matchingChildren) do
                        rows[#rows+1]={kind="type",id=ft,depth=node.depth+1}
                        seen[ft]=true
                    end
                end
            end
        end
    end

    local extra={}
    for id in pairs(model.draft.types) do if not seen[id] then extra[#extra+1]=id end end
    table.sort(extra)
    for _,id in ipairs(extra) do
        local matches = true
        if hasQuery then
            local resolveName=_G.getItemNameFromFullType
            local iName = type(resolveName)=="function" and resolveName(id) or id
            matches = string.find(string.lower(iName or ""), query, 1, true) or string.find(string.lower(id), query, 1, true)
        end
        if matches then
            rows[#rows+1]={kind="type",id=id,depth=1}
        end
    end
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
