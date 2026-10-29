-- Independent NPC debug entry for EmberRoutes carriers.
-- Vanilla debug tooling (ISStatsAndBody, player skill widgets) binds to getPlayer();
-- this file re-targets only calls that accept any IsoGameCharacter.
-- Vanilla files are never modified, and this stays inert unless CarrierProbe is on.
require "DebugUIs/DebugContextMenu"
require "DebugUIs/DebugMenu/Base/ISDebugSubPanelBase"
require "DebugUIs/DebugMenu/ISDebugUtils"
require "ISUI/ISCollapsableWindow"
require "ISUI/ISButton"
require "ISUI/ISTextBox"
local Log=require "EmberRoutesProbe/Log"
local NpcDebug={}

local function text(id) return getText("IGUI_EmberRoutesProbe_NpcDebug_"..id) end
local function log(message) Log.write("NPC_DEBUG",tostring(message)) end

-- Returns the carrier character and stable ID, or nil for players/zombies/animals.
function NpcDebug.carrier(object)
    if not object or not EmberRoutesProbeJava or not EmberRoutesProbeJava.carrierId then return nil end
    if not instanceof(object, "IsoGameCharacter") then return nil end
    local id=EmberRoutesProbeJava.carrierId(object)
    if not id or id=="" then return nil end
    return object, id
end

local function perks()
    local list={}
    for i=1,Perks.getMaxIndex() do
        local perk=PerkFactory.getPerk(Perks.fromIndex(i-1))
        if perk and perk:getParent()~=Perks.None then list[#list+1]=perk end
    end
    return list
end

local function perksByCategory()
    local categories = {}
    local catOrder = {}
    for i = 1, Perks.getMaxIndex() do
        local perk = PerkFactory.getPerk(Perks.fromIndex(i - 1))
        if perk and perk:getParent() ~= Perks.None then
            local parent = perk:getParent()
            local pName = parent:getName()
            if not categories[pName] then
                categories[pName] = { parent = parent, name = pName, list = {} }
                catOrder[#catOrder + 1] = pName
            end
            table.insert(categories[pName].list, perk)
        end
    end
    for _, cat in pairs(categories) do
        table.sort(cat.list, function(a, b) return tostring(a:getName()) < tostring(b:getName()) end)
    end
    return categories, catOrder
end

local function clampLevel(level)
    return math.max(0, math.min(10, math.floor(tonumber(level) or 0)))
end

function NpcDebug.report(actor,npc,id)
    log(string.format("npc=%s name=%s pos=(%.1f,%.1f,%d) health=%s",
        tostring(id), tostring(npc:getFullName()), npc:getX(), npc:getY(), npc:getZ(),
        tostring(npc:getBodyDamage():getOverallBodyHealth())))
    for _,perk in ipairs(perks()) do
        log(string.format("  perk=%s level=%d xp=%s", tostring(perk:getName()),
            npc:getPerkLevel(perk), tostring(npc:getXp():getXP(perk))))
    end
    local items=npc:getInventory():getItems()
    for i=0,items:size()-1 do
        local item=items:get(i)
        log(string.format("  item=%s count=%d", tostring(item:getFullType()), item:getCount()))
    end
    actor:Say(text("reported"))
end

-- Level only, mirroring setPerkLevelDebug. Existing XP is left untouched.
function NpcDebug.setPerk(npc,perkName,level)
    local target=NpcDebug.carrier(npc)
    if not target then return false end
    local perk=PerkFactory.getPerk(Perks.FromString(perkName))
    if not perk then return false end
    target:setPerkLevelDebug(perk, clampLevel(level))
    return true
end

function NpcDebug.setAllPerks(npc,level)
    local target=NpcDebug.carrier(npc)
    if not target then return false,0 end
    local count=0
    for _,perk in ipairs(perks()) do
        target:setPerkLevelDebug(perk, clampLevel(level)) count=count+1
    end
    return true,count
end

function NpcDebug.addItem(npc,fullType,count)
    local target=NpcDebug.carrier(npc)
    if not target or not fullType or fullType=="" then return false,0 end
    count=math.max(1, math.min(100, math.floor(tonumber(count) or 1)))
    local added=0
    for _=1,count do
        if not target:getInventory():AddItem(fullType) then break end
        added=added+1
    end
    return true,added
end

-- ---------------------------------------------------------------------------
-- Stats panel: mirrors the ISStatsAndBody slider set but binds to a carrier.
-- Player-only toggles (god mode, ghost, invisible) and multiplayer broadcasts
-- from the vanilla panel are intentionally not copied.
-- ---------------------------------------------------------------------------
local SLIDERS={
    {enum=CharacterStat.HUNGER},{enum=CharacterStat.THIRST},{enum=CharacterStat.FATIGUE},
    {enum=CharacterStat.ENDURANCE},{enum=CharacterStat.FITNESS,step=0.01},{enum=CharacterStat.PAIN,step=1},
    {enum=CharacterStat.PANIC,step=1},{enum=CharacterStat.MORALE},{enum=CharacterStat.STRESS},
    {enum=CharacterStat.BOREDOM,step=1},{enum=CharacterStat.UNHAPPINESS,step=1},
    {enum=CharacterStat.SICKNESS},{enum=CharacterStat.WETNESS,step=1},{enum=CharacterStat.TEMPERATURE,step=0.1},
    {enum=CharacterStat.ZOMBIE_INFECTION,step=1},
}

local function statLabel(statEnum)
    local id=statEnum:getId()
    return getTextOrNull("IGUI_StatsAndBody_"..tostring(id)) or tostring(id)
end

EmberRoutesNpcStats=ISCollapsableWindow:derive("EmberRoutesNpcStats")
EmberRoutesNpcStats.instance=nil

function EmberRoutesNpcStats:initialise()
    ISCollapsableWindow.initialise(self)
end

function EmberRoutesNpcStats:createChildren()
    ISCollapsableWindow.createChildren(self)
    local th=self:titleBarHeight()
    local pad=10
    local labelW=150
    local sliderW=self.width-labelW-pad*3
    local y=th+pad
    self.options={}
    for _,config in ipairs(SLIDERS) do
        local enum=config.enum
        local option={enum=enum,min=enum:getMinimumValue(),max=enum:getMaximumValue(),
            step=config.step or 0.01}
        local _,label=ISDebugUtils.addLabel(self,option,pad,y,statLabel(enum),UIFont.Small)
        _,option.valueLabel=ISDebugUtils.addLabel(self,option,pad+labelW+sliderW+pad,y,"0",UIFont.Small)
        local _,slider=ISDebugUtils.addSlider(self,option,pad+labelW,y,sliderW,20,
            EmberRoutesNpcStats.onSliderChange)
        slider.valueLabel=option.valueLabel
        slider:setValues(option.min,option.max,option.step,option.step,true)
        option.slider=slider
        self.options[#self.options+1]=option
        y=y+24
    end

    y=y+pad
    local fontH=getTextManager():getFontHeight(UIFont.Small)
    local btnH=fontH+6
    local btnW=120
    local closeBtn=ISButton:new((self.width-btnW)/2,y,btnW,btnH,text("close"),self,EmberRoutesNpcStats.close)
    closeBtn:initialise()
    closeBtn:instantiate()
    closeBtn.borderColor={r=1,g=1,b=1,a=0.2}
    self:addChild(closeBtn)
    self.bottomCloseBtn=closeBtn
    y=y+btnH+pad

    self:setScrollHeight(y)
end

function EmberRoutesNpcStats:prerender()
    ISCollapsableWindow.prerender(self)
    local target=self.target
    if not target then return end
    for _,option in ipairs(self.options) do
        local value=target:getStats():get(option.enum)
        option.slider.currentValue=value
        option.valueLabel:setName(ISDebugUtils.printval(value,3))
    end
end

function EmberRoutesNpcStats:onSliderChange(value,slider)
    local option=slider.customData
    local target=self.target
    if not option or not target then return end
    target:getStats():set(option.enum,value)
end

function EmberRoutesNpcStats:close()
    ISCollapsableWindow.close(self)
    self:removeFromUIManager()
    if EmberRoutesNpcStats.instance==self then
        EmberRoutesNpcStats.instance=nil
    end
end

function EmberRoutesNpcStats:new(x,y,width,height,target)
    local o=ISCollapsableWindow.new(self,x,y,width,height)
    o.backgroundColor={r=0.05,g=0.05,b=0.05,a=0.9}
    o.borderColor={r=0.4,g=0.4,b=0.4,a=1}
    o.target=target
    o.resizable=false
    local name=target and target.getFullName and target:getFullName()
    local id=target and EmberRoutesProbeJava and EmberRoutesProbeJava.carrierId and EmberRoutesProbeJava.carrierId(target)
    local titleStr=text("statsTitle")
    if name and name~="" and name~=" " then
        titleStr=titleStr.." · "..name
    end
    if id and id~="" then
        titleStr=titleStr.." ("..string.sub(tostring(id),1,8)..")"
    end
    o.title=titleStr
    return o
end

local identity=""

function NpcDebug.openStats(actor,npc,id)
    local target=NpcDebug.carrier(npc)
    if not target then actor:Say(text("unavailable")) return end
    local wanted=id or EmberRoutesProbeJava.carrierId(target)
    local panel=EmberRoutesNpcStats.instance
    if panel and panel.target and EmberRoutesProbeJava.carrierId(panel.target)==wanted then
        panel:setVisible(true)
        panel:addToUIManager()
        return
    end
    if panel then panel:close() EmberRoutesNpcStats.instance=nil end
    local width=440
    local fontH=getTextManager():getFontHeight(UIFont.Small)
    local btnH=fontH+6
    local th=20
    local contentH=th+10+24*#SLIDERS+10+btnH+14
    local height=math.min(getCore():getScreenHeight()-40,contentH)
    local x=math.max(0,(getCore():getScreenWidth()-width)/2)
    local y=math.max(0,(getCore():getScreenHeight()-height)/2)
    local created=EmberRoutesNpcStats:new(x,y,width,height,target)
    created:initialise()
    created:addToUIManager()
    EmberRoutesNpcStats.instance=created
    actor:Say(text("statsOpened").." "..string.sub(tostring(wanted),1,8))
end

function NpcDebug.execute(actor,npc,action,arg1,arg2)
    local target,id=NpcDebug.carrier(npc)
    if not target then actor:Say(text("unavailable")) return end
    if action=="report" then
        NpcDebug.report(actor,target,id)
    elseif action=="openStats" then
        NpcDebug.openStats(actor,target,id)
    elseif action=="allPerks" then
        local _,count=NpcDebug.setAllPerks(target,arg1)
        actor:Say(text("allPerksDone").." "..tostring(count).." = "..tostring(clampLevel(arg1)))
    end
end

function NpcDebug.setPerkFromMenu(actor,npc,perkName,level)
    local ok=NpcDebug.setPerk(npc,perkName,level)
    actor:Say(text(ok and "perkSet" or "perkFailed").." "..tostring(perkName).." = "..tostring(clampLevel(level)))
end

-- ISTextBox callback receives (target, button, param1).
function NpcDebug.itemEntered(actor,button,npc)
    if button.internal~="OK" then return end
    local value=button.parent.entry:getText()
    local ok,count=NpcDebug.addItem(npc,value,1)
    actor:Say(text("itemAdded").." "..tostring(value).." x"..tostring(count))
end

function NpcDebug.promptItem(actor,npc)
    local target=NpcDebug.carrier(npc)
    if not target then actor:Say(text("unavailable")) return end
    local modal=ISTextBox:new(0,0,320,180,text("itemPrompt"),"Base.",actor,NpcDebug.itemEntered,actor:getPlayerNum(),npc)
    modal:initialise() modal:addToUIManager()
end

local function fillCarrier(parent,actor,npc,id)
    local name = npc and npc.getFullName and npc:getFullName()
    local titleText = text("title")
    local label
    if name and name ~= "" and name ~= " " then
        label = titleText .. " · " .. name .. " (" .. string.sub(id, 1, 8) .. ")"
    else
        label = titleText .. " (" .. string.sub(id, 1, 8) .. ")"
    end
    local rootOption = parent:addOption(label, nil, nil)
    local rootMenu = ISContextMenu:getNew(parent)
    parent:addSubMenu(rootOption, rootMenu)

    -- 1. 最常用的属性与需求面板（居首）
    rootMenu:addOption(text("stats"), actor, NpcDebug.execute, npc, "openStats")

    -- 2. 全部技能快捷设置（按常用等级整理）
    local allOption = rootMenu:addOption(text("allPerks"), nil, nil)
    local allMenu = ISContextMenu:getNew(rootMenu)
    rootMenu:addSubMenu(allOption, allMenu)
    allMenu:addOption(string.format(text("allPerksMax"),10), actor, NpcDebug.execute, npc, "allPerks", 10)
    allMenu:addOption(string.format(text("allPerksFive"),5), actor, NpcDebug.execute, npc, "allPerks", 5)
    allMenu:addOption(string.format(text("allPerksZero"),0), actor, NpcDebug.execute, npc, "allPerks", 0)
    local customLevelOption = allMenu:addOption(text("allPerksCustom"), nil, nil)
    local customLevelMenu = ISContextMenu:getNew(allMenu)
    allMenu:addSubMenu(customLevelOption, customLevelMenu)
    for level = 0, 10 do
        customLevelMenu:addOption("Lv." .. tostring(level), actor, NpcDebug.execute, npc, "allPerks", level)
    end

    -- 3. 单项技能设置（按原版大类归类整理，告别20+技能长列表）
    local perkOption = rootMenu:addOption(text("perk"), nil, nil)
    local perkMenu = ISContextMenu:getNew(rootMenu)
    rootMenu:addSubMenu(perkOption, perkMenu)
    local categories, catOrder = perksByCategory()
    for _, catName in ipairs(catOrder) do
        local cat = categories[catName]
        local catOption = perkMenu:addOption(tostring(catName), nil, nil)
        local catSubMenu = ISContextMenu:getNew(perkMenu)
        perkMenu:addSubMenu(catOption, catSubMenu)
        for _, perk in ipairs(cat.list) do
            local perkName = perk:getName()
            local currentLevel = npc:getPerkLevel(perk)
            local entry = catSubMenu:addOption(tostring(perkName) .. " (Lv." .. tostring(currentLevel) .. ")", nil, nil)
            local levelMenu = ISContextMenu:getNew(catSubMenu)
            catSubMenu:addSubMenu(entry, levelMenu)
            for level = 0, 10 do
                levelMenu:addOption("Lv." .. tostring(level), actor, NpcDebug.setPerkFromMenu, npc, perkName, level)
            end
        end
    end

    -- 4. 添加物品
    rootMenu:addOption(text("itemAdd"), actor, NpcDebug.promptItem, npc)

    -- 5. 查看并写入诊断日志
    rootMenu:addOption(text("report"), actor, NpcDebug.execute, npc, "report")
end

-- Append one submenu per carrier standing on the clicked square.
local original=DebugContextMenu.doDebugMenu
DebugContextMenu.doDebugMenu=function(playerIndex,context,worldobjects,test)
    local result=original(playerIndex,context,worldobjects,test)
    if test or not isDebugEnabled() then return result end
    if not SandboxVars or not SandboxVars.EmberRoutes or not SandboxVars.EmberRoutes.CarrierProbe then return result end
    local actor=getSpecificPlayer(playerIndex)
    if not actor or actor:isDead() then return result end
    local option=context:getOptionFromName(getText("ContextMenu_Debug"))
    local parent=option and option.subOption and context:getSubMenu(option.subOption)
    if not parent then return result end
    local square=DebugContextMenu.pickSquare and DebugContextMenu.pickSquare(getMouseX(),getMouseY())
    if not square then
        for _,object in ipairs(worldobjects) do
            if object.getSquare then square=object:getSquare() end
            if square then break end
        end
    end
    if not square then return result end
    local moving=square:getMovingObjects()
    local seen={}
    for i=1,moving:size() do
        local npc,id=NpcDebug.carrier(moving:get(i-1))
        if npc and id and not seen[id] then
            seen[id]=true
            fillCarrier(parent,actor,npc,id)
        end
    end
    return result
end

return NpcDebug
