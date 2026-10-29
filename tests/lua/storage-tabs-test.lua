package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter=require "EmberRoutesProbe/StorageFilter"
local count=0
local function check(value,why) count=count+1 assert(value,why) end
local events={}
Events=setmetatable({OnGameStart={Add=function(fn) events[#events+1]=fn end}},{
    __index=function(t,k) t[k]={Add=function(fn) events[#events+1]=fn end} return t[k] end
})
function getTexture(path) return path end
function getText(key) return ERTestTranslations and ERTestTranslations[key] or key end
function getTextOrNull(key) return ERTestTranslations and ERTestTranslations[key] end
UIFont={Small=1}
function getCore() return {getScreenWidth=function() return 1920 end} end
function getTextManager() return {MeasureStringX=function(_,_,s) return #s*8 end} end
function isClient() return false end function isServer() return false end
SandboxVars={EmberRoutes={CarrierProbe=true}}
package.loaded['ISUI/ISInventoryPage']=true
local applied=Filter.new() applied.groups.food=true
local Registry={containerIndex=function(o,c)
    if o:getContainer()==c then return 0 end
    if o.getContainerCount then for i=0,o:getContainerCount()-1 do if o:getContainerByIndex(i)==c then return i end end end
end,listeners={},filter=function() return applied end,logistics=function() return "STORAGE" end,metadata=function() return nil end}
package.loaded['EmberRoutesProbe/ContainerRegistry']=Registry
package.loaded['EmberRoutesProbe/StorageFilterPanel']={open=function() end}
package.loaded['EmberRoutesProbe/Log']={write=function() end}
local options={}
local lastOption
local context={addOption=function(_,label,a,fn,o,c) options[#options+1]=label lastOption={actor=a,callback=fn,object=o,container=c} return {} end,
    addSubMenu=function() end}
local subcontext={addOption=function() return {} end,addSubMenu=function() end}
ISContextMenu={getNew=function() return subcontext end}
function getPlayerContextMenu() return context end
local actor={isDead=function() return false end}
function getSpecificPlayer() return actor end
function getNumActivePlayers() return 0 end
local originalCalls,renderCalls=0,0
local function newButton(container)
    return {inventory=container,image="native-image",tooltip="native-name",setImage=function(self,image) self.image=image end,
        getWidth=function() return 36 end,getHeight=function() return 36 end,
        drawRect=function() end,drawTextureScaledAspect=function() end,
        render=function() renderCalls=renderCalls+1 end,
        onRightMouseDown=function() originalCalls=originalCalls+1 options={"vanilla-rename"} return "native-result" end}
end
local object,container={},{}
local objects={contains=function(_,o) return o==object end}
local square={getObjects=function() return objects end}
function object:getSquare() return square end
function object:getContainer() return container end
function container:getParent() return object end
ISInventoryPage={addContainerButton=function(_,inventory) return newButton(inventory) end}
local selectedRole,selectedContainer
package.loaded['EmberRoutesProbe/Work']={execute=function(_,role,_,c) selectedRole,selectedContainer=role,c end}
local Tabs=require "EmberRoutesProbe/StorageTabs"
Tabs.install() Tabs.install()
local button=ISInventoryPage.addContainerButton({player=0},container)
check(button:onRightMouseDown(0,0)=="native-result" and originalCalls==1,"original handler return and call retained exactly once")
check(options[1]=="vanilla-rename" and #options==4,"filter entry appends without clearing native options")
check(button.image=="media/ui/Container_Fridge.png","single category replaces main image")
check(button.tooltip:find("native%-name") and button.tooltip:gsub("\n",""):find(getText("IGUI_EmberRoutesProbe_Filter_food.stable"),1,true),"tooltip retains container name and categories")
-- Prove render never consults registry or classifier.
local nativeFilter=Registry.filter
Registry.filter=function() error("render queried registry") end
button:render() button:render()
check(renderCalls==2,"native render retained with no registry reads")
Registry.filter=nativeFilter
Tabs.bind(button,0)
button:onRightMouseDown(0,0)
check(originalCalls==2 and #options==4,"pooled rebind does not stack handlers")
local bag={getParent=function() return nil end}
button.inventory=bag Tabs.bind(button,0)
check(button.image=="native-image" and button.tooltip=="native-name","unsupported rebind restores original image and tooltip")
button:onRightMouseDown(0,0)
check(#options==1,"personal bag never receives world-storage settings")
button.inventory=container Tabs.bind(button,0)
applied.private=true
for _,fn in ipairs(Registry.listeners) do fn("container-id") end
check(button.image=="media/ui/lock.png","privacy event replaces whole image with lock")
applied.private=false applied.groups.tools=true Tabs.refresh(button)
check(button.image=="media/ui/Container_Crate.png","multiple categories use one mixed-storage icon")
applied.groups.tools=nil applied.types['Base.Hammer']=true Tabs.refresh(button)
check(button.image=="media/ui/Container_Crate.png","allow exception conservatively uses mixed icon")
applied.enabled=false Tabs.refresh(button)
check(button.image=="media/ui/lock.png" and button.tooltip:gsub("\n",""):find(getText("IGUI_EmberRoutesProbe_Filter_disabled"),1,true),"disabled policy visibly blocks NPC access")
-- Another adapter's later write survives release when the probe is disabled.
button.image,button.tooltip="third-party-image","third-party-tooltip"
SandboxVars.EmberRoutes.CarrierProbe=false Tabs.refresh(button)
check(button.image=="third-party-image" and button.tooltip=="third-party-tooltip","release never restores over another adapter's values")
SandboxVars.EmberRoutes.CarrierProbe=true applied.enabled=true applied.types={}
-- Simulate exact native pool order, including the same Texture value as our old applied icon.
Tabs.refresh(button)
local pooledButton=button
ISInventoryPage.emberStorageWrapped=nil
ISInventoryPage.addContainerButton=function(page,inventory)
    local reused=table.remove(page.buttonPool,1)
    reused.inventory=inventory reused.image="media/ui/Container_Fridge.png" reused.tooltip="new-bag-name"
    return reused
end
Tabs.install()
button=ISInventoryPage.addContainerButton({player=0,buttonPool={pooledButton}},bag)
check(button.image=="media/ui/Container_Fridge.png" and button.tooltip=="new-bag-name","native rebind wins even if new image equals old replacement")
local render=button.render
button.inventory=container Tabs.bind(button,0)
check(button.render==render,"no rendering wrapper or extra icon draw")
local priorFilter=Registry.filter
Registry.filter=function() return nil end Tabs.refresh(button)
check(button.image=="media/ui/Container_Fridge.png" and button.tooltip=="new-bag-name","removing configuration restores current native baseline")
Registry.filter=priorFilter
Filter.registerCategory('custom')
local oldApplied=applied
applied=Filter.new() applied.groups.custom=true Tabs.refresh(button)
check(button.image=="media/ui/Container_Fridge.png","unknown category texture keeps native image rather than erasing it")
applied=oldApplied
local alternate={getParent=function() return object end}
check(not Tabs.object(alternate),"secondary container does not silently configure primary")
function object:getContainerCount() return 2 end
function object:getContainerByIndex(i) return i==0 and container or (i==1 and alternate or nil) end
check(Tabs.object(alternate)==object,"registered secondary freezer can open its own settings")
button.inventory=alternate Tabs.bind(button,0) button:onRightMouseDown(0,0)
check(#options==4,"freezer preserves native menu and receives storage settings")
lastOption.callback(lastOption.actor,lastOption.object,lastOption.container)
check(selectedRole=='destination' and selectedContainer==alternate,"sidebar route command preserves freezer identity and selected role")
print("PASS "..count.." storage sidebar adapter checks; vanilla/CleanUI runtime NOT RUN")
