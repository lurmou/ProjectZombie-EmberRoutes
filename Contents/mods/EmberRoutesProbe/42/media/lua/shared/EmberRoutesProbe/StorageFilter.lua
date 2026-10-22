-- Storage allocation policy only. No inventory mutation, profession checks or UI.
local Filter = { nodes={}, order={}, classifiers={} }
function Filter.registerCategory(id, parent, color)
    assert(type(id)=="string" and #id<=80 and id:match("^[%w_.]+$") and not Filter.nodes[id], "FILTER_CATEGORY_ID")
    assert(not parent or Filter.nodes[parent], "FILTER_PARENT_REQUIRED")
    local depth=parent and Filter.nodes[parent].depth+1 or 0
    assert(depth<=16 and #Filter.order<128,"FILTER_TREE_LIMIT")
    Filter.nodes[id]={id=id,parent=parent,depth=depth,color=color or {0.7,0.7,0.7}}
    if parent then Filter.nodes[parent].hasChildren=true end
    Filter.order[#Filter.order+1]=id
    Filter.treeCache=nil
end
function Filter.registerClassifier(id, fn)
    assert(type(id)=="string" and type(fn)=="function", "FILTER_CLASSIFIER_INVALID")
    for _, entry in ipairs(Filter.classifiers) do assert(entry.id~=id,"FILTER_CLASSIFIER_DUPLICATED") end
    Filter.classifiers[#Filter.classifiers+1]={id=id,match=fn}
end
for _, definition in ipairs({
    {"food",nil,{0.4,0.8,0.3}}, {"food.stable","food"}, {"food.perishable","food"},
    {"weapons",nil,{0.85,0.35,0.25}}, {"weapons.guns","weapons"}, {"weapons.ammo","weapons"}, {"weapons.other","weapons"},
    {"materials",nil,{0.8,0.65,0.3}}, {"medical",nil,{0.8,0.85,0.9}},
    {"tools",nil,{0.4,0.65,0.9}}, {"scrap",nil,{0.6,0.5,0.4}}, {"other",nil,{0.6,0.6,0.7}}
}) do Filter.registerCategory(definition[1],definition[2],definition[3]) end

function Filter.new()
    return {format=1,enabled=true,private=false,groups={},types={}}
end
function Filter.copy(config)
    if type(config)~="table" or config.format~=1 or type(config.enabled)~="boolean" or type(config.private)~="boolean"
            or type(config.groups)~="table" or type(config.types)~="table" then return nil,"FILTER_FORMAT_INVALID" end
    local result=Filter.new()
    result.enabled,result.private=config.enabled,config.private
    for _, field in ipairs({"groups","types"}) do
        local count=0
        for id,value in pairs(config[field]) do
            count=count+1
            if count>256 or type(id)~="string" or #id>256 or type(value)~="boolean" then return nil,"FILTER_LIMIT_OR_VALUE" end
            result[field][id]=value
        end
    end
    return result
end
function Filter.access(config)
    return type(config)=="table" and config.format==1 and config.enabled==true and config.private==false
        and type(config.groups)=="table" and type(config.types)=="table"
end
function Filter.describe(item)
    local food=item.isFood and item:isFood() or item:getCategory()=="Food"
    return {fullType=item:getFullType(), display=string.lower(item:getDisplayCategory() or ""),
        category=string.lower(item:getCategory() or ""), food=food,
        perishable=food and item:getOffAgeMax()<1000000000,
        ranged=item.isRanged and item:isRanged() or false}
end
function Filter.classify(description, item)
    for _, rule in ipairs(Filter.classifiers) do
        local id=rule.match(description,item)
        if id and Filter.nodes[id] then return id end
    end
    local d=description
    if d.food then return d.perishable and "food.perishable" or "food.stable" end
    if d.display=="ammo" or d.display=="ammunition" then return "weapons.ammo" end
    if d.category=="weapon" then return d.ranged and "weapons.guns" or "weapons.other" end
    if d.display:find("medical",1,true) or d.display=="firstaid" then return "medical" end
    if d.display:find("tool",1,true) then return "tools" end
    if d.display:find("material",1,true) or d.display=="crafting" then return "materials" end
    if d.display=="junk" or d.display=="trash" or d.display=="scrap" then return "scrap" end
    if d.display:find("weapon",1,true) then return "weapons.other" end
    if d.display=="food" then return "food.stable" end
    return "other"
end
function Filter.matchesDescription(config, description, item)
    if not Filter.access(config) then return false end
    if config.types[description.fullType]~=nil then return config.types[description.fullType]==true end
    local node=Filter.classify(description,item)
    while node do
        if config.groups[node]~=nil then return config.groups[node]==true end
        node=Filter.nodes[node] and Filter.nodes[node].parent
    end
    return false
end
function Filter.matches(config,item)
    if not Filter.access(config) then return false end
    local exact=config.types[item:getFullType()]
    if exact~=nil then return exact==true end
    return Filter.matchesDescription(config,Filter.describe(item),item)
end
function Filter.setGroup(config,id,value)
    assert(Filter.nodes[id] and type(value)=="boolean","FILTER_GROUP_INVALID")
    config.groups[id]=value
    for _, child in ipairs(Filter.order) do
        local parent=Filter.nodes[child].parent
        while parent do
            if parent==id then config.groups[child]=nil break end
            parent=Filter.nodes[parent].parent
        end
    end
    -- Exact-type exceptions deliberately survive broad category edits.
end
function Filter.legacy(tag)
    local config=Filter.new()
    if tag=="private" or not tag then config.private=true return config end
    if tag=="inbox" or tag=="outbox" then
        for _,id in ipairs(Filter.order) do if not Filter.nodes[id].parent then config.groups[id]=true end end
    elseif tag=="tools" then config.groups.tools,config.groups.materials=true,true
    elseif Filter.nodes[tag] then config.groups[tag]=true
    else config.private=true end
    return config
end
function Filter.badges(config)
    if not Filter.access(config) then return {} end
    local result,roots={},{}
    for _,id in ipairs(Filter.order) do
        if not Filter.nodes[id].hasChildren then
            local current,value=id,false
            while current do
                if config.groups[current]~=nil then value=config.groups[current]==true break end
                current=Filter.nodes[current].parent
            end
            if value then
                current=id
                while Filter.nodes[current].parent do current=Filter.nodes[current].parent end
                roots[current]=true
            end
        end
    end
    for _,id in ipairs(Filter.order) do if roots[id] then result[#result+1]=Filter.nodes[id] end end
    return result
end
function Filter.treeOrder()
    if Filter.treeCache then return Filter.treeCache end
    local result={}
    local function visit(id)
        result[#result+1]=id
        for _,child in ipairs(Filter.order) do if Filter.nodes[child].parent==id then visit(child) end end
    end
    for _,id in ipairs(Filter.order) do if not Filter.nodes[id].parent then visit(id) end end
    Filter.treeCache=result
    return result
end
return Filter
