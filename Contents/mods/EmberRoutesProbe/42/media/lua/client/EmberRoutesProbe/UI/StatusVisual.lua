-- Prepared, bounded visual states. No timers, scans or text measurement in draw.
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Visual={}
Visual.colors={neutral=Theme.muted,active=Theme.accent,done=Theme.status.READY,
    paused={r=0.94,g=0.73,b=0.36,a=1},blocked=Theme.status.ERROR}
function Visual.mark(owner,x,y,size,state,color)
    local u=math.max(1,size/5)
    if state=="done" then
        Theme.rect(owner,x,y+u*2,u,u*2,color)
        Theme.rect(owner,x+u,y+u*3,u,u,color)
        Theme.rect(owner,x+u*2,y+u,u*2,u,color)
        Theme.rect(owner,x+u*2,y+u*2,u,u,color)
    elseif state=="paused" then
        Theme.rect(owner,x,y,u,size,color) Theme.rect(owner,x+u*3,y,u,size,color)
    elseif state=="blocked" then
        Theme.rect(owner,x+u*2,y,u,u*3,color) Theme.rect(owner,x+u*2,y+u*4,u,u,color)
    elseif state=="active" then
        Theme.rect(owner,x,y,u,size,color) Theme.rect(owner,x+u,y+u,u,u*3,color)
        Theme.rect(owner,x+u*2,y+u*2,u,u,color)
    else Theme.rect(owner,x,y,size,size,color,true) end
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
function Visual.steps(labels,width,h,p,index,state)
    local cells={} local slot=width/#labels
    for i,label in ipairs(labels) do
        local phase=i<index and "done" or i==index and state or "neutral"
        if state=="done" then phase="done" end
        cells[i]={x=(i-1)*slot,width=slot-p/2,label=Text.wrapLimited(label,slot-p,UIFont.Small,2),
            state=phase,color=Visual.colors[phase] or Theme.muted}
    end
    return {cells=cells,h=h,p=p,height=h*3+p}
end
function Visual.drawSteps(owner,x,y,track)
    local h,p=track.h,track.p
    for _,cell in ipairs(track.cells) do
        local cx=x+cell.x
        local thickness=cell.state=="active" and math.max(3,p/2) or math.max(2,p/4)
        Theme.rect(owner,cx,y,cell.width,thickness,cell.color)
        Visual.mark(owner,cx,y+p,h/2,cell.state,cell.color)
        for i,label in ipairs(cell.label) do Theme.text(owner,label,cx,y+p+h/2+(i-1)*h,cell.color) end
    end
end
return Visual
