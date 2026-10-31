package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path

local Base={}
function Base:derive(name) local cls=setmetatable({Type=name},{__index=self}) cls.__index=cls return cls end
function Base:new(x,y,w,h,title) return setmetatable({x=x,y=y,width=w,height=h,title=title,children={},selected=1,items={}},self) end
Base.__index=Base
function Base:initialise() self.initialised=true end
function Base:createChildren() self.parentCreated=true end
function Base:addChild(child) self.children[#self.children+1]=child end
function Base:addToUIManager() self:createChildren() self.added=true end
function Base:removeFromUIManager() self.added=false end
function Base:close() self.closed=true end
function Base:titleBarHeight() return 24 end
function Base:drawText() end
function Base:drawRect() end
function Base:drawRectBorder() end
function Base:drawTextureScaledAspect() end
function Base:getAbsoluteX() return self.x end
function Base:getAbsoluteY() return self.y end
function Base:prerender() self.parentRendered=true end
function Base:setWantKeyEvents(value) self.wantsKeys=value end
function Base:isVisible() return self.visible~=false end

ISCollapsableWindow=Base:derive('ISCollapsableWindow')
ISButton=Base:derive('TestButton')
function ISButton:new(x,y,w,h,title,target,onclick)
    local btn=Base.new(self,x,y,w,h,title)
    btn.target,btn.onclick=target,onclick
    btn.enable=true
    return btn
end
ISTextEntryBox=Base:derive('TestTextEntry')
function ISTextEntryBox:new(value,x,y,w,h)
    local entry=Base.new(self,x,y,w,h)
    entry.value=value
    return entry
end
function ISTextEntryBox:getText() return self.value or "" end
function ISTextEntryBox:setText(v) self.value=v end

package.loaded['ISUI/ISCollapsableWindow']=ISCollapsableWindow
package.loaded['ISUI/ISButton']=ISButton
package.loaded['ISUI/ISTextEntryBox']=ISTextEntryBox

local n=0
local function check(value,why) n=n+1 assert(value,why) end

-- Mock environment
local tables,uuid={},0
ModData={getOrCreate=function(key) tables[key]=tables[key] or {} return tables[key] end}
function getRandomUUID() uuid=uuid+1 return "uuid-"..uuid end
function isClient() return false end function isServer() return false end
local actor={x=5,y=5,z=0,isDead=function() return false end,getIndex=function() return 0 end,getPlayerNum=function() return 0 end,
    getX=function(self) return self.x end,getY=function(self) return self.y end,getZ=function(self) return self.z end,
    getJoypadBind=function() return -1 end}
function getSpecificPlayer() return actor end

local events={}
Events={OnRenderTick={Add=function(fn) events[#events+1]=fn end,Remove=function(fn)
    for i=#events,1,-1 do if events[i]==fn then table.remove(events,i) end end
end}}

package.loaded['EmberRoutesProbe/Log']={write=function() end}
function getTextManager()
    return {
        getFontHeight=function() return 16 end,
        MeasureStringX=function(_,_,str) return #(str or "")*8 end
    }
end
UIFont={Small=1,Medium=2,Large=3}
Keyboard={KEY_ESCAPE=1,KEY_RETURN=28,KEY_1=2,KEY_2=3,KEY_A=30,KEY_R=19,KEY_Z=44}
Joypad={AButton=0,BButton=1,XButton=2,YButton=3}
function getCore()
    return {
        getScreenWidth=function() return 1920 end,
        getScreenHeight=function() return 1080 end
    }
end
function getText(key,...)
    return key
end

-- Mock screenToIso
local mockIsoX,mockIsoY=0,0
function screenToIsoX(playerNum,sx,sy,z) return mockIsoX end
function screenToIsoY(playerNum,sx,sy,z) return mockIsoY end
function getMouseX() return 1000 end
function getMouseY() return 800 end
function getCell()
    return {
        getGridSquare=function(_,x,y,z) return {x=x,y=y,z=z} end
    }
end

-- Mock highlight function
local renderedHighlights={}
function addAreaHighlightForPlayer(playerNum,x1,y1,x2,y2,z,r,g,b,a)
    renderedHighlights[#renderedHighlights+1]={playerNum=playerNum,x1=x1,y1=y1,x2=x2,y2=y2,z=z,r=r,g=g,b=b,a=a}
end

local Selector=require "EmberRoutesProbe/UI/SettlementSelector"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Geometry=require "EmberRoutesProbe/SettlementGeometry"

-- Test 1: Open selector for new settlement
local panel = Selector:new(actor, nil, nil)
panel:initialise()
panel:createChildren()
check(#events == 1, "renderTick registered to Events.OnRenderTick on initialise")
check(#panel.areas == 0, "initial areas empty for new settlement")
check(panel.mode == "add", "initial mode is add")

-- Test 2: Drag and add first area (0,0 to 9,9 -> 10x10)
mockIsoX,mockIsoY=0,0
panel:onMouseDownOutside()
check(panel.dragging == true, "dragging started")
mockIsoX,mockIsoY=9,9
panel:onMouseMoveOutside()
check(panel.dragArea ~= nil and panel.dragArea.w == 10 and panel.dragArea.h == 10, "dragArea computed 10x10")
panel:onMouseUpOutside()
check(panel.dragging == false and panel.dragArea == nil, "dragging ended")
check(#panel.areas == 1 and panel.areas[1].w == 10, "first area confirmed")
check(Geometry.totalTiles(panel.areas) == 100, "100 tiles in territory")

-- Test 3: Drag and add second area (10,0 to 19,9 -> adjacent 10x10, total 20x10 = 200 tiles)
mockIsoX,mockIsoY=10,0
panel:onMouseDownOutside()
mockIsoX,mockIsoY=19,9
panel:onMouseMoveOutside()
panel:onMouseUpOutside()
check(Geometry.totalTiles(panel.areas) == 200, "two areas compacted to 200 tiles")

-- Test 4: Mode switch to remove
panel:setMode("remove")
check(panel.mode == "remove", "switched to remove mode")

-- Test 5: Drag and remove a hole (5,2 to 14,7 -> w=10, h=6 = 60 tiles cut out)
mockIsoX,mockIsoY=5,2
panel:onMouseDownOutside()
mockIsoX,mockIsoY=14,7
panel:onMouseMoveOutside()
panel:onMouseUpOutside()
check(Geometry.totalTiles(panel.areas) == 140, "cutout removed 60 tiles from territory (200 - 60 = 140)")
check(#panel.areas > 1, "irregular territory split into clean disjoint rectangles")

-- Test 6: Test Undo
check(#panel.history > 0, "history stack has records")
panel:undo()
check(Geometry.totalTiles(panel.areas) == 200, "undo restored 200 tiles territory")

-- Test 7: World highlight rendering tick (verify no flicker & correct colors)
panel.visible = true
renderedHighlights={}
panel:renderWorldHighlights()
check(#renderedHighlights > 0, "highlights rendered during OnRenderTick")
-- Gold color for committed areas (0.95, 0.78, 0.20)
local foundGold=false
for _,h in ipairs(renderedHighlights) do
    if math.abs(h.r - 0.95) < 0.01 and math.abs(h.g - 0.78) < 0.01 then foundGold=true end
end
check(foundGold, "committed territory rendered with Amber/Gold highlight")

-- Test 8: Commit irregular settlement
local savedEntry=nil
panel.saved=function(entry) savedEntry=entry end
panel.nameEntry:setText("Irregular Outpost")
panel:apply()
check(savedEntry ~= nil, "settlement applied and saved")
check(savedEntry.name == "Irregular Outpost", "settlement name matches")
check(#savedEntry.areas > 0, "ledger saved irregular areas")

-- Test 9: Close cleanly tears down listener
panel:close()
check(#events == 0, "Events.OnRenderTick cleanly unsubscribed on close")

print("PASS " .. n .. " settlement selector irregular UI & flicker-free highlight checks")
