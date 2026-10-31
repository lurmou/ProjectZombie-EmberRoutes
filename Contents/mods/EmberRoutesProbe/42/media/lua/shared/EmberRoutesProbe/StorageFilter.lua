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
    {"food",nil,{0.4,0.8,0.3}}, {"food.meals","food"}, {"food.perishable","food"}, {"food.stable","food"},
    {"medical",nil,{0.8,0.85,0.9}}, {"medical.bandages","medical"}, {"medical.pills","medical"},
    {"weapons",nil,{0.85,0.35,0.25}}, {"weapons.guns","weapons"}, {"weapons.ammo","weapons"}, {"weapons.parts","weapons"}, {"weapons.other","weapons"},
    {"apparel",nil,{0.5,0.7,0.85}}, {"apparel.armor","apparel"}, {"apparel.clothing","apparel"}, {"apparel.bags","apparel"},
    {"literature",nil,{0.75,0.6,0.9}}, {"literature.skills","literature"}, {"literature.entertainment","literature"},
    {"tools",nil,{0.4,0.65,0.9}},
    {"materials",nil,{0.8,0.65,0.3}}, {"materials.electronics","materials"},
    {"trade",nil,{0.95,0.8,0.3}}, {"trade.currency","trade"}, {"trade.valuables","trade"},
    {"scrap",nil,{0.6,0.5,0.4}}, {"scrap.waste","scrap"}, {"scrap.compost","scrap"},
    {"kits",nil,{0.35,0.85,0.75}}, {"kit.fishing","kits"}, {"kit.farming","kits"}, {"kit.tailoring","kits"}, {"kit.mechanic","kits"},
    {"other",nil,{0.6,0.6,0.7}}
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
    local rotten=false
    if food and item.isRotten then
        rotten=item:isRotten()
    elseif food and item.getAge and item.getOffAgeMax then
        rotten=item:getAge()>item:getOffAgeMax()
    end
    local cooked=food and item.isCooked and item:isCooked() or false
    local clothing=(item.IsClothing and item:IsClothing()) or (item.isClothing and item:isClothing()) or false
    local container=(item.IsContainer and item:IsContainer()) or (item.isContainer and item:isContainer()) or false
    local display=string.lower(item.getDisplayCategory and item:getDisplayCategory() or "")
    local category=string.lower(item.getCategory and item:getCategory() or "")
    local fullType=item.getFullType and item:getFullType() or ""
    return {
        fullType=fullType,
        display=display,
        category=category,
        food=food,
        rotten=rotten,
        cooked=cooked,
        clothing=clothing,
        container=container,
        perishable=food and item.getOffAgeMax and item:getOffAgeMax()<1000000000 or false,
        ranged=item.isRanged and item:isRanged() or false
    }
end
function Filter.classify(description, item)
    for _, rule in ipairs(Filter.classifiers) do
        local id=rule.match(description,item)
        if id and Filter.nodes[id] then return id end
    end
    local d=description
    local f=d.fullType:lower()

    -- 1. Kits matching (Fishing / Farming / Tailoring / Mechanic)
    if d.display=="fishing" or f:find("fishing") or f:find("fishhook") or f:find("lure") or f:find("worm") then
        return "kit.fishing"
    end
    if d.display=="gardening" or d.display=="farming" or f:find("seed") or f:find("fertilizer") or f:find("wateringcan") or f:find("plantspray") then
        return "kit.farming"
    end
    if d.display=="tailoring" or f:find("needle") or f:find("thread") or f:find("scissors") or f:find("sewing") then
        return "kit.tailoring"
    end
    if d.display=="vehicle" or d.display=="mechanics" or f:find("lugwrench") or f:find("tirepump") or f:find("carbattery") or f:find("jack") then
        return "kit.mechanic"
    end

    -- 2. Food (Rotten / Meals / Perishable / Stable)
    if d.food or d.display=="food" then
        if d.rotten then return "scrap.compost" end
        if d.cooked or f:find("soup") or f:find("stew") or f:find("roast") or f:find("salad") or f:find("pie") or f:find("sandwich") or f:find("burger") then
            return "food.meals"
        end
        if d.perishable then return "food.perishable" end
        return "food.stable"
    end

    -- 3. Medical (Bandages vs Pills)
    if d.display:find("medical",1,true) or d.display=="firstaid" or f:find("bandage") or f:find("disinfectant") or f:find("alcohol") or f:find("suture") or f:find("splint") or f:find("pills") or f:find("antibiotic") then
        if f:find("pills") or f:find("vitamin") or f:find("antibiotic") or f:find("painkiller") or f:find("sedative") then
            return "medical.pills"
        end
        return "medical.bandages"
    end

    -- 4. Trade & Valuables (Currency / Jewelry / Gems)
    if f:find("money") or f:find("coin") or f:find("token") or f:find("ember") then
        return "trade.currency"
    end
    if f:find("ring") or f:find("necklace") or f:find("earring") or f:find("gold") or f:find("silver") or f:find("jewelry") or f:find("gem") or f:find("diamond") then
        return "trade.valuables"
    end

    -- 5. Weapons (Guns / Ammo / Melee / Parts)
    if d.display=="ammo" or d.display=="ammunition" or f:find("ammo") or f:find("bullets") then
        return "weapons.ammo"
    end
    if d.ranged then return "weapons.guns" end
    if d.display=="weaponpart" or f:find("gunpart") or f:find("scope") or f:find("silencer") then
        return "weapons.parts"
    end
    if d.category=="weapon" or d.display:find("weapon",1,true) then
        return "weapons.other"
    end

    -- 6. Apparel (Armor / Bags / Clothing)
    if d.container or d.category=="container" or f:find("bag") or f:find("backpack") or f:find("duffel") then
        return "apparel.bags"
    end
    if f:find("vest") or f:find("helmet") or f:find("armor") or f:find("bullet") then
        return "apparel.armor"
    end
    if d.clothing or d.category=="clothing" or d.display=="clothing" or f:find("glasses") or f:find("watch") then
        return "apparel.clothing"
    end

    -- 7. Literature & Media (Books / Comics / Magazines / Manuals / Maps / VHS)
    if d.category=="literature" or d.display=="literature" or d.display=="book" or d.display=="media"
        or f:find("book") or f:find("comic") or f:find("magazine") or f:find("manual") or f:find("newspaper")
        or f:find("map") or f:find("vhs") or f:find("tape") or f:find("cd") then
        if f:find("skill") or f:find("recipe") or f:find("vol.") or f:find("volume") then
            return "literature.skills"
        end
        return "literature.entertainment"
    end

    -- 8. Scrap & Waste (Explicit Junk/Trash/Scrap or Rotten/Dirty)
    if d.display=="junk" or d.display=="trash" or d.display=="scrap" or d.rotten or f:find("dirty") then
        return "scrap.waste"
    end

    -- 8. Tools & Materials (Electronics / Tools / Materials)
    if d.display:find("electronic",1,true) or f:find("electronic") or f:find("battery") or f:find("radio") or f:find("wire") then
        return "materials.electronics"
    end
    if d.display:find("tool",1,true) or f:find("hammer") or f:find("saw") or f:find("screwdriver") or f:find("wrench") or f:find("welding") then
        return "tools"
    end
    if d.display:find("material",1,true) or d.display=="crafting" or f:find("plank") or f:find("nail") or f:find("metal") or f:find("sheet") or f:find("glue") or f:find("tape") then
        return "materials"
    end

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
