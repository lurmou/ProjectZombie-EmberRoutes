-- Relative row/column layout; units come from screen bounds/font metrics at the caller.
local Layout={}
function Layout.axis(bounds,tracks,style)
    local pad,gap=style.padding or 0,style.gap or 0
    local vertical=style.direction=="column"
    local space=(vertical and bounds.height or bounds.width)-pad*2-gap*math.max(0,#tracks-1)
    local fixed,grow=0,0
    for _,track in ipairs(tracks) do
        fixed=fixed+(track.basis or 0)+(track.margin or 0)*2
        grow=grow+(track.grow or 0)
    end
    if space<fixed or bounds.width<pad*2 or bounds.height<pad*2 then return nil,"INSUFFICIENT_SPACE" end
    local result,cursor={},pad
    for index,track in ipairs(tracks) do
        local margin=track.margin or 0
        local extent=(track.basis or 0)+(grow>0 and (space-fixed)*(track.grow or 0)/grow or 0)
        cursor=cursor+margin
        result[index]={x=bounds.x+(vertical and pad or cursor),y=bounds.y+(vertical and cursor or pad),
            width=vertical and bounds.width-pad*2 or extent,height=vertical and extent or bounds.height-pad*2}
        cursor=cursor+extent+margin+gap
    end
    return result
end
-- Bounded dossier index; compact retains the existing list/detail toggle.
function Layout.split(bounds,h,gap)
    gap=gap or 0
    local width=math.max(0,bounds.width)
    if width<14*h+28*h+gap then
        return {index={x=bounds.x,y=bounds.y,width=width,height=bounds.height},
            main={x=bounds.x,y=bounds.y,width=width,height=bounds.height},compact=true}
    end
    local index=math.min(22*h,math.max(14*h,width*0.24),width-gap-28*h)
    return {index={x=bounds.x,y=bounds.y,width=index,height=bounds.height},
        main={x=bounds.x+index+gap,y=bounds.y,width=width-index-gap,height=bounds.height},compact=false}
end
return Layout
