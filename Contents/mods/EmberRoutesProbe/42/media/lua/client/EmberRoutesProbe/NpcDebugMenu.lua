-- Independent NPC debug entry for EmberRoutes carriers.
-- Vanilla debug tooling (ISStatsAndBody, player skill widgets) binds to getPlayer();
-- this file re-targets only calls that accept any IsoGameCharacter.
-- Vanilla files are never modified, and this stays inert unless CarrierProbe is on.
require "DebugUIs/DebugContextMenu"
require "DebugUIs/DebugMenu/Base/ISDebugSubPanelBase"
require "DebugUIs/DebugMenu/ISDebugUtils"
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

EmberRoutesNpcStats=ISPanel:derive("EmberRoutesNpcStats")
EmberRoutesNpcStats.instance=nil

function EmberRoutesNpcStats:createChildren()
    ISPanel.createChildren(self)
    local pad=10
    local labelW=150
    local sliderW=self.width-labelW-pad*3
    local y=pad
    local _,title=ISDebugUtils.addLabel(self,nil,pad,y,text("statsTitle"),UIFont.Medium)
    title.center=true
    title:setX(pad+(self.width-pad*2)/2-title:getWidth()/2)
    y=y+getTextManager():getFontHeight(UIFont.Medium)+pad
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
    self:setScrollHeight(y+pad)
end

function EmberRoutesNpcStats:prerender()
    ISPanel.prerender(self)
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
    self:setVisible(false)
    self:removeFromUIManager()
end

function EmberRoutesNpcStats:new(x,y,width,height,target)
    local o=ISPanel:new(x,y,width,height)
    setmetatable(o,self) self.__index=self
    o.backgroundColor={r=0.05,g=0.05,b=0.05,a=0.9}
    o.borderColor={r=0.4,g=0.4,b=0.4,a=1}
    o.target=target
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
    local height=64+24*#SLIDERS+20
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
    local rootOption=parent:addOption(text("title").." ("..string.sub(id,1,8)..")",nil,nil)
    local rootMenu=ISContextMenu:getNew(parent)
    parent:addSubMenu(rootOption,rootMenu)
    rootMenu:addOption(text("report"),actor,NpcDebug.execute,npc,"report")
    rootMenu:addOption(text("stats"),actor,NpcDebug.execute,npc,"openStats")
    local allOption=rootMenu:addOption(text("allPerks"),nil,nil)
    local allMenu=ISContextMenu:getNew(rootMenu)
    rootMenu:addSubMenu(allOption,allMenu)
    for level=0,10 do allMenu:addOption(tostring(level),actor,NpcDebug.execute,npc,"allPerks",level) end
    local perkOption=rootMenu:addOption(text("perk"),nil,nil)
    local perkMenu=ISContextMenu:getNew(rootMenu)
    rootMenu:addSubMenu(perkOption,perkMenu)
    for _,perk in ipairs(perks()) do
        local name=perk:getName()
        local entry=perkMenu:addOption(tostring(name).." ("..tostring(npc:getPerkLevel(perk))..")",nil,nil)
        local levelMenu=ISContextMenu:getNew(perkMenu)
        perkMenu:addSubMenu(entry,levelMenu)
        for level=0,10 do
            levelMenu:addOption(tostring(level),actor,NpcDebug.setPerkFromMenu,npc,name,level)
        end
    end
    rootMenu:addOption(text("itemAdd"),actor,NpcDebug.promptItem,npc)
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
