-- warehouse-ae2-test.lua: Verification of AE2 style continuous scrollbar & Scheme A status badge
local count=0
local function check(v,s) count=count+1 assert(v,s) end

-- Mock minimal PZ environment
local Base={
    derive=function(self,type)
        local o={} setmetatable(o,self) self.__index=self
        o.Type=type return o
    end,
    new=function(self,x,y,w,h)
        local o={x=x,y=y,width=w,height=h,items={}}
        setmetatable(o,self) self.__index=self
        return o
    end,
    initialise=function(self) end,
    addChild=function(self,c) end,
    setWantKeyEvents=function(self,v) end,
    getMouseX=function(self) return 0 end,
    getMouseY=function(self) return 0 end
}
_G.ISPanel=Base
_G.ISButton=Base
_G.ISScrollingListBox=Base
_G.ISComboBox=Base
_G.UIFont={Small=0}

for _,name in ipairs({"ISButton","ISScrollingListBox","ISPanel","ISComboBox"}) do
    package.loaded['ISUI/'..name]=true
end

function getText(k,a1,a2)
    if a1 and a2 then return k..':'..tostring(a1)..'/'..tostring(a2) end
    if a1 then return k..':'..tostring(a1) end
    return k
end
function getTextOrNull(k) return k end
function getItemNameFromFullType(k) return k end
getTextManager=function()
    return {
        getFontHeight=function() return 14 end,
        MeasureStringX=function(_,str) return #tostring(str)*7 end
    }
end

-- 1. Test WarehouseQuery.all & Query.all
local Query=require "EmberRoutesProbe/WarehouseQuery"
local rows={}
for i=1,150 do
    rows[#rows+1]={fullType="Item_"..i,label="Item "..i,count=i,node="tools"}
end
for i=151,200 do
    rows[#rows+1]={fullType="Food_"..i,label="Food "..i,count=i,node="food"}
end

local q=Query.new()
local all,p1,p2,total=q:all(rows,"",false,"default")
check(#all==200 and total==200 and p1==1 and p2==1,"Query:all returns all 200 items in single continuous stream")

-- Filtered all
local foodOnly,_,_,foodTotal=q:all(rows,"Food",false,"default")
check(#foodOnly==50 and foodTotal==50,"Query:all respects search string without truncation")

-- Backwards compatibility with Query:page
local page1,curPage,maxPages,totalCount=q:page(rows,"",false,1)
check(#page1==60 and curPage==1 and maxPages==4 and totalCount==200,"Query:page retains 60-item pagination compatibility")

-- 2. Test WarehouseGrid AE2 Scrollbar
local Grid=require "EmberRoutesProbe/UI/WarehouseGrid"
local mockOwner={fontHeight=14,pad=6,store={value={selection=false}},focusList=function() end}
local bounds={x=0,y=0,width=300,height=200}
local grid=Grid.new(mockOwner,bounds,function() end)

-- Test with empty or small dataset (no scrolling required)
grid:setRows({rows[1],rows[2]})
local trackX,trackY,trackW,trackH,thumbY,thumbH,canScroll=grid:getScrollbarGeometry()
check(canScroll==false,"Small dataset cannot scroll, thumb disabled")
check(trackW>=10 and trackX>0,"Track geometry is properly calculated")

-- Test with large dataset (AE2 scrollable)
grid:setRows(rows)
check(grid.maxScrollY>0,"Large dataset sets positive maxScrollY")
trackX,trackY,trackW,trackH,thumbY,thumbH,canScroll=grid:getScrollbarGeometry()
check(canScroll==true,"Large dataset enables AE2 scrollbar")
check(thumbY==trackY,"Initial scroll at 0 maps thumb to track top")
check(thumbH<trackH,"Thumb height dynamically scales smaller than track height")

-- Test Mouse Wheel
grid:onMouseWheel(2)
check(grid.scrollY>0,"Mouse wheel moves scrollY downward")
local _,_,_,_,newThumbY=grid:getScrollbarGeometry()
check(newThumbY>thumbY,"Thumb moves down as scrollY increases")

-- Test Scrollbar hit detection & dragging
grid.scrollY=0
local mx=trackX+2
local my=trackY+2
local handled=grid:onMouseDown(mx,my)
check(handled==true and grid.isDraggingThumb==true,"Clicking inside thumb starts dragging")

-- Simulate dragging down
grid.getMouseY=function() return trackY+50 end
grid:onMouseMove(0,10)
check(grid.scrollY>0,"Dragging thumb updates scrollY proportionally")

grid:onMouseUp(0,0)
check(grid.isDraggingThumb==false,"Mouse up terminates dragging")

-- Test track click (page jump)
grid.scrollY=0
local trackBottomClick=trackY+trackH-2
grid:onMouseDown(trackX+2,trackBottomClick)
check(grid.scrollY>0,"Clicking below thumb jumps scroll forward by viewport height")

-- Test cellAt does not trigger inside scrollbar track
local hit=grid:cellAt(trackX+2,50)
check(hit==nil,"cellAt ignores clicks within the AE2 scrollbar track column")

print("PASS "..count.." warehouse AE2 scrollbar & data stream checks")
