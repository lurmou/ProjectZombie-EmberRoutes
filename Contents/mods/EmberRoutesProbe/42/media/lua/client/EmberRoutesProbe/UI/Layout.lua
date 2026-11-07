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
--- Intelligent drawer docking & displacement:
--- Ensures dash and drawer fit side-by-side without overflowing or overlapping.
--- Shifts dash left if needed and centers the combined unit.
---@param dash any
---@param drawerW number
---@param gap number?
---@param screenW number?
---@return number x
---@return number y
---@return number w
---@return number h
function Layout.dockDrawer(dash, drawerW, gap, screenW)
    gap = gap or 8
    screenW = screenW or (getCore and getCore():getScreenWidth()) or 1920
    local dashX = (dash.getX and dash:getX()) or dash.x or 0
    local dashY = (dash.getY and dash:getY()) or dash.y or 0
    local dashW = dash.width or 0
    local dashH = dash.height or 0

    local combinedW = dashW + gap + drawerW
    local targetDashX = dashX
    local targetDrawerX = dashX + dashW + gap

    if targetDrawerX + drawerW > screenW - 8 then
        if combinedW <= screenW - 16 then
            targetDashX = math.max(8, math.floor((screenW - combinedW) / 2))
        else
            targetDashX = 8
            drawerW = math.max(280, math.min(drawerW, screenW - dashW - gap - 16))
        end
        if dash._drawerSavedX == nil then
            dash._drawerSavedX = dashX
        end
        dash._dockedDashX = targetDashX
        if dash.setX and math.abs(dash:getX() - targetDashX) > 2 then
            dash:setX(targetDashX)
        end
        targetDrawerX = targetDashX + dashW + gap
        if targetDrawerX + drawerW > screenW - 8 then
            targetDrawerX = math.max(8, screenW - drawerW - 8)
        end
    end

    return targetDrawerX, dashY, drawerW, dashH
end

--- Restores dashboard position when drawer closes, unless player manually moved it.
---@param dash any
function Layout.undockDrawer(dash)
    if not dash then return end
    if dash._drawerSavedX ~= nil then
        local currentX = (dash.getX and dash:getX()) or dash.x or 0
        local dockedX = dash._dockedDashX or currentX
        if math.abs(currentX - dockedX) <= 6 then
            if dash.setX then
                local screenW = (getCore and getCore():getScreenWidth()) or 1920
                local restoreX = math.max(8, math.min(dash._drawerSavedX, screenW - (dash.width or 0) - 8))
                dash:setX(restoreX)
            end
        end
        dash._drawerSavedX = nil
        dash._dockedDashX = nil
    end
end

return Layout
