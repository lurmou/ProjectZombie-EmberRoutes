-- Native stencil scope for custom canvases. Content coordinates remain intact:
-- partially visible text/icons are submitted and clipped by the renderer.
local Viewport={}
function Viewport.draw(owner,bounds,draw)
    local native=owner.setStencilRect and owner.clearStencilRect
    if native then owner:setStencilRect(bounds.x,bounds.y,bounds.width,bounds.height) end
    local ok,result=pcall(draw)
    if native then
        owner:clearStencilRect()
        if owner.doRepaintStencil and owner.repaintStencilRect then
            owner:repaintStencilRect(bounds.x,bounds.y,bounds.width,bounds.height)
        end
    end
    if not ok then error(result) end
    return result
end
function Viewport.install(panel)
    local original=panel.prerender
    panel.prerender=function(self)
        return Viewport.draw(self,{x=0,y=0,width=self.width,height=self.height},function() return original(self) end)
    end
end
return Viewport
