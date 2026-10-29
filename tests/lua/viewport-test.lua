local n=0 local function check(v,s) n=n+1 assert(v,s) end
local View=require 'EmberRoutesProbe/UI/Viewport'
local calls={} local owner={doRepaintStencil=true}
function owner:setStencilRect(x,y,w,h) calls[#calls+1]={'set',x,y,w,h} end
function owner:clearStencilRect() calls[#calls+1]={'clear'} end
function owner:repaintStencilRect(x,y,w,h) calls[#calls+1]={'restore',x,y,w,h} end
local bounds={x=0,y=0,width=100,height=50}
local drawn={}
View.draw(owner,bounds,function() drawn[#drawn+1]={y=45,h=20} end)
check(calls[1][1]=='set' and calls[1][5]==50,'stencil is the viewport, not content height or scroll offset')
check(#drawn==1,'partially visible bottom content remains submitted, never hidden early')
check(calls[2][1]=='clear' and calls[3][1]=='restore','child canvas restores native parent stencil contract')
local ok=pcall(function() View.draw(owner,bounds,function() error('draw failed') end) end)
check(not ok and calls[#calls][1]=='restore','draw failure restores clipping and rethrows instead of hiding the error')
local panel={width=100,height=50,setStencilRect=owner.setStencilRect,clearStencilRect=owner.clearStencilRect}
local renders=0 panel.prerender=function() renders=renders+1 end
View.install(panel) panel:prerender() check(renders==1,'canvas decorator retains original renderer exactly once')
print('PASS '..n..' viewport scope/partial-edge checks; GPU not run')
