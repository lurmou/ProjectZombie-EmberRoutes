-- Prepared, bounded visual states. No timers, scans or text measurement in draw.
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Visual={}
Visual.colors={neutral=Theme.muted,active=Theme.accent,done=Theme.status.READY,
    paused={r=0.94,g=0.73,b=0.36,a=1},blocked=Theme.status.ERROR}
-- Texture-backed icons: 32x32 antialiased white PNGs (tools GenIcons.java),
-- tinted at draw time via drawTextureScaled's RGB multipliers - the same
-- approach CleanUI uses. `false` marks a failed lookup so a missing texture
-- never turns into a per-frame getTexture call; geometry stays as fallback.
local TEX={}
local TEX_DIR="media/ui/EmberRoutes/ICON/"
local TEX_NAME={
    done="check",active="disc",paused="pause",blocked="warn",
    waiting="square",neutral="square",reconcile="diamond",["return"]="return",
    transit="transit",plus="plus",minus="minus",
    chevronUp="chevronUp",chevronDown="chevronDown",bullet="bullet",
    box="box",hammer="hammer",arrowDown="arrowDown",arrowRight="arrowRight",moon="moon",
}
local function texFor(kind)
    local cached=TEX[kind]
    if cached~=nil then return cached or nil end
    local tex=false
    local path=TEX_NAME[kind] and (TEX_DIR..TEX_NAME[kind]..".png")
    if path and type(getTexture)=="function" then
        local ok,res=pcall(getTexture,path)
        if ok and res then tex=res end
    end
    TEX[kind]=tex
    return tex or nil
end
local function drawIcon(owner,x,y,size,kind,color)
    local tex=texFor(kind)
    if tex and owner.drawTextureScaled then
        owner:drawTextureScaled(tex,x,y,size,size,color.r,color.g,color.b,color.a or 1)
        return true
    end
    return false
end
-- One 5x5 scalar grid cell. Module-level (no closure, no per-frame table).
-- The grid pitch u MUST be an integer: fractional pitches rasterize some cells
-- onto the same pixel or drop them entirely, breaking thin strokes (missing
-- segments in the stage icons). The pattern is centered inside the box.
local function cell(owner,ox,oy,u,cx,cy,w,h,color)
    Theme.rect(owner,ox+u*cx,oy+u*cy,u*w,u*h,color)
end
-- Eight distinct silhouettes per the UI master guide (colour-blind safe):
-- hollow ring / filled disc / warning triangle / dashed square / pause bars /
-- left return arrow / diamond / check, plus neutral box and right transit arrow.
function Visual.mark(owner,x,y,size,state,color)
    local texKind=TEX_NAME[state]
    if texKind and drawIcon(owner,x,y,size,texKind,color) then return end
    local u=math.max(1,math.floor(size/5))
    local ox=x+math.floor((size-u*5)/2)
    local oy=y+math.floor((size-u*5)/2)
    if state=="done" then
        cell(owner,ox,oy,u,0,2,1,2,color) cell(owner,ox,oy,u,1,3,1,1,color)
        cell(owner,ox,oy,u,2,1,2,1,color) cell(owner,ox,oy,u,2,2,1,1,color)
    elseif state=="paused" then
        cell(owner,ox,oy,u,0,0,1,5,color) cell(owner,ox,oy,u,3,0,1,5,color)
    elseif state=="blocked" then
        cell(owner,ox,oy,u,2,0,1,1,color) cell(owner,ox,oy,u,1,1,3,1,color)
        cell(owner,ox,oy,u,1,2,1,1,color) cell(owner,ox,oy,u,3,2,1,1,color)
        cell(owner,ox,oy,u,0,3,5,1,color) cell(owner,ox,oy,u,2,2,1,1,color)
    elseif state=="active" then
        cell(owner,ox,oy,u,1,0,3,1,color) cell(owner,ox,oy,u,0,1,5,3,color)
        cell(owner,ox,oy,u,1,4,3,1,color)
    elseif state=="waiting" then
        cell(owner,ox,oy,u,1,0,3,1,color) cell(owner,ox,oy,u,1,4,3,1,color)
        cell(owner,ox,oy,u,0,1,1,3,color) cell(owner,ox,oy,u,4,1,1,3,color)
    elseif state=="handoff" then
        cell(owner,ox,oy,u,0,0,2,1,color) cell(owner,ox,oy,u,3,0,2,1,color)
        cell(owner,ox,oy,u,0,4,2,1,color) cell(owner,ox,oy,u,3,4,2,1,color)
        cell(owner,ox,oy,u,0,1,1,2,color) cell(owner,ox,oy,u,4,1,1,2,color)
    elseif state=="return" then
        cell(owner,ox,oy,u,1,2,4,1,color) cell(owner,ox,oy,u,0,1,1,1,color)
        cell(owner,ox,oy,u,1,0,1,1,color) cell(owner,ox,oy,u,0,3,1,1,color)
        cell(owner,ox,oy,u,1,4,1,1,color)
    elseif state=="reconcile" then
        cell(owner,ox,oy,u,2,0,1,1,color) cell(owner,ox,oy,u,1,1,1,1,color)
        cell(owner,ox,oy,u,3,1,1,1,color) cell(owner,ox,oy,u,0,2,1,1,color)
        cell(owner,ox,oy,u,4,2,1,1,color) cell(owner,ox,oy,u,1,3,1,1,color)
        cell(owner,ox,oy,u,3,3,1,1,color) cell(owner,ox,oy,u,2,4,1,1,color)
    elseif state=="transit" then
        cell(owner,ox,oy,u,0,2,4,1,color) cell(owner,ox,oy,u,3,1,1,1,color)
        cell(owner,ox,oy,u,4,0,1,1,color) cell(owner,ox,oy,u,3,3,1,1,color)
        cell(owner,ox,oy,u,4,4,1,1,color)
    elseif state=="plus" then
        cell(owner,ox,oy,u,0,2,5,1,color) cell(owner,ox,oy,u,2,0,1,5,color)
    elseif state=="minus" then
        cell(owner,ox,oy,u,0,2,5,1,color)
    elseif state=="chevronUp" then
        cell(owner,ox,oy,u,0,2,1,1,color) cell(owner,ox,oy,u,1,1,1,1,color)
        cell(owner,ox,oy,u,2,0,1,1,color) cell(owner,ox,oy,u,3,1,1,1,color)
        cell(owner,ox,oy,u,4,2,1,1,color)
    elseif state=="chevronDown" then
        cell(owner,ox,oy,u,0,2,1,1,color) cell(owner,ox,oy,u,1,3,1,1,color)
        cell(owner,ox,oy,u,2,4,1,1,color) cell(owner,ox,oy,u,3,3,1,1,color)
        cell(owner,ox,oy,u,4,2,1,1,color)
    elseif state=="bullet" then
        cell(owner,ox,oy,u,2,1,1,1,color) cell(owner,ox,oy,u,1,2,3,1,color)
        cell(owner,ox,oy,u,2,3,1,1,color)
    else Theme.rect(owner,x,y,size,size,color,true) end
end
-- Semantic glyphs on a 6x6 integer grid: shape encodes WHAT the item is,
-- colour (applied by the caller) encodes its state. Unknown names fall back
-- to the state marks so callers can pass user-defined keys safely.
--   box        crate for prepare/staging steps
--   hammer     crafting / work
--   arrowDown  collecting / retrieving
--   arrowRight delivering / dispatching
--   moon       rest / leisure (Z shape)
local GLYPHS={
    box={ {0,0,6,1},{0,5,6,1},{0,1,1,4},{5,1,1,4},{2,1,2,1} },
    hammer={ {1,0,4,2},{2,2,1,4} },
    arrowDown={ {2,0,2,3},{0,3,6,1},{1,4,4,1},{2,5,2,1} },
    arrowRight={ {0,2,3,2},{3,0,1,6},{4,1,1,4},{5,2,1,2} },
    moon={ {0,0,5,1},{4,1,1,1},{3,2,1,1},{2,3,1,1},{1,4,4,1} },
}
function Visual.glyph(owner,x,y,size,name,color)
    if name and drawIcon(owner,x,y,size,name,color) then return true end
    local rects=name and GLYPHS[name]
    if not rects then return false end
    local u=math.floor(size/6)
    if u<1 then return false end
    local ox=x+math.floor((size-u*6)/2)
    local oy=y+math.floor((size-u*6)/2)
    for _,rc in ipairs(rects) do
        Theme.rect(owner,ox+u*rc[1],oy+u*rc[2],u*rc[3],u*rc[4],color)
    end
    return true
end
function Visual.badge(label,state,width,h,p)
    return {label=Text.wrapLimited(label,math.max(1,width-h-p*2),UIFont.Small,1)[1],
        state=state,color=Visual.colors[state] or Theme.muted,width=width,height=h+p,h=h,p=p}
end
function Visual.drawBadge(owner,x,y,badge)
    Theme.rect(owner,x,y,badge.width,badge.height,Theme.control)
    Theme.rect(owner,x,y,badge.width,badge.height,badge.color,true)
    Visual.mark(owner,x+badge.p/2,y+badge.p/2+badge.h/4,badge.h/2,badge.state,badge.color)
    Theme.text(owner,badge.label,x+badge.h,y+badge.p/2,badge.color)
end
function Visual.meter(owner,x,y,width,height,fraction,color)
    Theme.rect(owner,x,y,width,height,Theme.control)
    if fraction and fraction>0 then
        local fillW=math.max(1,math.floor(width*math.min(1,fraction)))
        Theme.rect(owner,x,y,fillW,height,color or Theme.accent)
    end
    Theme.rect(owner,x,y,width,height,Theme.border,true)
end
function Visual.steps(labels,width,h,p,index,state,kinds)
    local cells={} local slot=width/#labels
    for i,label in ipairs(labels) do
        local phase=i<index and "done" or i==index and state or "neutral"
        if state=="done" then phase="done" end
        cells[i]={x=(i-1)*slot,width=slot-p/2,label=Text.wrapLimited(label,slot-p,UIFont.Small,2),
            state=phase,color=Visual.colors[phase] or Theme.muted,kind=kinds and kinds[i] or nil}
    end
    return {cells=cells,h=h,p=p,height=h*3+p}
end
function Visual.drawSteps(owner,x,y,track)
    local h,p=track.h,track.p
    -- Give the icon nearly a full line of pixels (12px at UIFont.Small):
    -- a 6x6 semantic glyph at 12px reads clearly; unknown kinds fall back
    -- to the 5x5 state mark.
    local markH=math.max(5,h-2)
    for _,cell in ipairs(track.cells) do
        local cx=x+cell.x
        local thickness=cell.state=="active" and math.max(3,p/2) or math.max(2,p/4)
        Theme.rect(owner,cx,y,cell.width,thickness,cell.color)
        if not (cell.kind and Visual.glyph(owner,cx,y+p,markH,cell.kind,cell.color)) then
            Visual.mark(owner,cx,y+p,markH,cell.state,cell.color)
        end
        for i,label in ipairs(cell.label) do Theme.text(owner,label,cx,y+p+markH+(i-1)*h,cell.color) end
    end
end
return Visual
