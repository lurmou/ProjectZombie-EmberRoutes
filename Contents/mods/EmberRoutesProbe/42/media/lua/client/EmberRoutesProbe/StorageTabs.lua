require "ISUI/ISInventoryPage"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Filter=require "EmberRoutesProbe/StorageFilter"
local ContainerMenu=require "EmberRoutesProbe/ContainerMenu"
local Configuration=require "EmberRoutesProbe/ContainerConfiguration"
local Work=require "EmberRoutesProbe/Work"
local Log=require "EmberRoutesProbe/Log"
local Flow=require "EmberRoutesProbe/UIFlow"
---@class EmberRoutesInventoryPage: ISInventoryPage
---@field player integer
local Tabs={}
local buttons=setmetatable({},{__mode="k"})
local icons={}
for id,path in pairs({food="Container_Fridge",weapons="Container_Crate",materials="Item_Logs",
        tools="Container_ToolCabinet",medical="Container_Medicine",scrap="Container_Garbage",other="Container_Cabinet",
        mixed="Container_Crate",private="lock"}) do
    icons[id]=getTexture("media/ui/"..path..".png")
end
icons.weapons=getTexture("media/textures/Item_HandGun3.png") or icons.weapons
local function enabled()
    return SandboxVars and SandboxVars.EmberRoutes and SandboxVars.EmberRoutes.CarrierProbe==true
        and not isClient() and not isServer()
end
function Tabs.object(container)
    if not container then return nil end
    local object=container:getParent()
    if not object or not object.getContainer or not object.getSquare then return nil end
    local square=object:getSquare()
    if not square or Registry.containerIndex(object,container)==nil or not square:getObjects():contains(object) then return nil end
    return object
end
local function text(id) return getText("IGUI_EmberRoutesProbe_Filter_"..id) end
-- Restore only values we still own. Another adapter may have replaced them.
local function release(button)
    if button.emberImage and button.image==button.emberImage then button:setImage(button.emberBaseImage) end
    if button.emberTooltip and button.tooltip==button.emberTooltip then button.tooltip=button.emberBaseTooltip end
    button.emberImage,button.emberTooltip=nil,nil
end
function Tabs.refresh(button)
    release(button)
    local object=enabled() and Tabs.object(button.inventory)
    if not object then return end
    local config=Registry.filter(object,button.inventory)
    if not config then return end
    button.emberBaseImage,button.emberBaseTooltip=button.image,button.tooltip
    local categories,names=Filter.badges(config),{}
    local allowed,denied=0,0
    for _,value in pairs(config.types or {}) do
        if value==true then allowed=allowed+1 else denied=denied+1 end
    end
    local selectedCount=0
    for _,id in ipairs(Filter.order) do
        if not Filter.nodes[id].hasChildren then
            local current,value=id,false
            while current do
                if config.groups[current]~=nil then value=config.groups[current]==true break end
                current=Filter.nodes[current] and Filter.nodes[current].parent
            end
            if value then
                selectedCount=selectedCount+1
                if #names<12 then names[#names+1]=text(id) end
            end
        end
    end
    local id,status
    if not config.enabled then id,status="private","disabled"
    elseif config.private then id,status="private","privateShort"
    elseif #categories==1 and allowed==0 then id,status=categories[1].id,"storage"
    elseif #categories>1 or allowed>0 then id,status="mixed","mixed"
    else id,status="other","empty" end
    local texture=icons[id]
    if texture then button.emberImage=texture button:setImage(texture) end
    local lines={button.emberBaseTooltip or button.name or text("title"),text(status)}
    local role=Registry.logistics({object=object,container=button.inventory})
    lines[#lines+1]=Configuration.text(role)
    lines[#lines+1]=Configuration.warning(config,role)
    if Filter.access(config) then
        lines[#lines+1]=text("categories")..(#names>0 and table.concat(names,", ") or text("empty"))
        if selectedCount>#names then lines[#lines+1]="…" end
        if allowed+denied>0 then lines[#lines+1]=text("exactSummary")..allowed.." / "..denied end
    end
    local wrapped={}
    local width=math.max(120,math.min(420,getCore():getScreenWidth()*0.65))
    for _,line in ipairs(lines) do
        for _,part in ipairs(Flow.wrap(line,width,UIFont.Small)) do wrapped[#wrapped+1]=part end
    end
    button.emberTooltip=table.concat(wrapped,"\n")
    button.tooltip=button.emberTooltip
end
local function rightClick(button,x,y)
    local result
    if button.emberNativeRight then result=button.emberNativeRight(button,x,y) end
    if not enabled() then return result end
    local object=Tabs.object(button.inventory)
    if not object then return result end
    local actor=getSpecificPlayer(button.emberPlayer)
    if not actor or actor:isDead() then return result end
    -- Reuse the menu created by the original handler; get() would erase it.
    local context=getPlayerContextMenu(button.emberPlayer)
    if context then
        local option=context:addOption(getText("IGUI_EmberRoutesProbe_ContainerSettings"),nil,nil)
        local menu=ISContextMenu:getNew(context) context:addSubMenu(option,menu)
        ContainerMenu.fill(actor,menu,object,button.inventory)
        for _,role in ipairs({"source","destination"}) do
            context:addOption(getText("IGUI_EmberRoutesProbe_Work_"..role),actor,function(a,o,c)
                Work.execute(a,role,o,c)
            end,object,button.inventory)
        end
    end
    return result
end
function Tabs.bind(button,player,fresh)
    if not button then return end
    -- addContainerButton has already reset image/tooltip; never restore stale pool state over it.
    if fresh then button.emberImage,button.emberTooltip=nil,nil end
    button.emberPlayer=player
    if button.onRightMouseDown~=rightClick then
        button.emberNativeRight=button.onRightMouseDown button.onRightMouseDown=rightClick
    end
    buttons[button]=true
    Tabs.refresh(button)
end
function Tabs.install()
    if not ISInventoryPage or type(ISInventoryPage.addContainerButton)~="function" then
        Log.write("STORAGE_FILTER","TAB_ADAPTER_UNAVAILABLE world menu retained") return
    end
    if not ISInventoryPage.emberStorageWrapped then
        local native=ISInventoryPage.addContainerButton
        -- Deliberate chain-preserving method adapter, covered by pooled-button tests.
        ---@param page EmberRoutesInventoryPage
        ---@diagnostic disable-next-line: duplicate-set-field
        ISInventoryPage.addContainerButton=function(page,...)
            local pooled=page.buttonPool and page.buttonPool[1]
            if pooled then release(pooled) end
            local button=native(page,...)
            Tabs.bind(button,page.player,true)
            return button
        end
        ISInventoryPage.emberStorageWrapped=true
    end
    -- Current vanilla uses this global; the older lint inventory omits it.
    local activePlayers=_G.getNumActivePlayers
    if type(activePlayers)~="function" then
        Log.write("STORAGE_FILTER","TAB_INITIAL_BIND_UNAVAILABLE world menu retained") return
    end
    for player=0,activePlayers()-1 do
        local data=getPlayerData(player)
        if data then
            for _,page in pairs({data.playerInventory,data.lootInventory}) do
                for _,button in ipairs(page.backpacks or {}) do Tabs.bind(button,player) end
            end
        end
    end
    Log.write("STORAGE_FILTER","TAB_ADAPTER_INSTALLED main icons; primary world containers only")
end
Registry.listeners[#Registry.listeners+1]=function() for button in pairs(buttons) do Tabs.refresh(button) end end
Events.OnGameStart.Add(Tabs.install)
return Tabs
