package.path="Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;"..package.path
local State=require "EmberRoutesProbe/UI/State"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Text=require "EmberRoutesProbe/UI/Text"
local calls=0
local original={selected="food",message=""}
local store=State.new(original)
local release=store:subscribe(function(value,changed)
    calls=calls+1 assert(changed.selected and value.selected=="tools","single changed branch notification")
end)
assert(not store:setState({selected="food"}) and calls==0,"unchanged state must not notify")
assert(store:setState({selected="tools"}) and calls==1 and original.selected=="food","replace snapshot without mutating old state")
release() store:setState({selected="medical"})
assert(calls==1,"disposed UI listener must stop receiving state")
local bounds={x=5,y=7,width=1000,height=400}
local row=assert(Layout.axis(bounds,{{grow=1},{grow=2},{grow=1}},{padding=10,gap=10}))
assert(row[2].width>row[1].width and row[1].x>=bounds.x and row[3].x+row[3].width<=bounds.x+bounds.width,"relative row fits and distributes grow")
local col=assert(Layout.axis(bounds,{{basis=50,margin=5},{grow=1},{basis=30}},{direction="column",padding=10,gap=5}))
assert(col[1].y+col[1].height<col[2].y and col[2].y+col[2].height<col[3].y,"column tracks never overlap")
assert(not Layout.axis({x=0,y=0,width=5,height=5},{{basis=50}},{padding=5}),"insufficient area rejected rather than negative layout")
assert(not Layout.axis({x=0,y=0,width=5,height=400},{{grow=1}},{direction="column",padding=5}),"insufficient cross-axis width rejected")
local manager=getTextManager
function getTextManager() return {MeasureStringX=function(_,_,s) return #s*10 end} end
local sample=ERTestTranslations and ERTestTranslations.IGUI_EmberRoutesProbe_Filter_food or "Food / tools"
assert(table.concat(Text.wrap(sample,15,1),"")==sample,"translated text preserved")
assert(#Text.wrap("A\nB",500,1)==2,"explicit line breaks preserved")
local limited=Text.wrapLimited(string.rep(sample,8),60,1,2)
assert(#limited==2 and limited[2]:sub(-3)=='...','long translated labels have a bounded line count and ellipsis')
for _,line in ipairs(limited) do assert(getTextManager():MeasureStringX(1,line)<=60,'ellipsis must fit inside its reserved column') end
getTextManager=manager
print("PASS UI state subscriptions/disposal, relative layout bounds and text regressions")
