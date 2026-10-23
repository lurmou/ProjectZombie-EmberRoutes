local Text=require "EmberRoutesProbe/UI/Text"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Table={}
function Table.columns(list,hasIcon)
    if list.emberColumns then return list.emberColumns end
    local h,p=list.emberFontHeight,list.emberPad
    local quantityWidth=math.max(getTextManager():MeasureStringX(UIFont.Small,"20000"),
        getTextManager():MeasureStringX(UIFont.Small,getText("IGUI_EmberRoutesProbe_Settlement_quantity")))+p*2
    local icon=hasIcon and h*1.6 or 0
    list.emberColumns={quantity=list.width-h-p-quantityWidth,name=p+icon+(icon>0 and p+4 or 0),icon=icon}
    list.emberNames={}
    return list.emberColumns
end
function Table.style(presentation,name,secondary)
    return {
        emptyColor=Theme.muted,
        prepare=function(list,value)
            local h,p=list.emberFontHeight,list.emberPad
            local columns=Table.columns(list,presentation~=nil)
            local label=name(value)
            local cached=list.emberNames[label]
            if not cached then
                cached=Text.wrapLimited(label,math.max(1,columns.quantity-p-columns.name),UIFont.Small,2)
                list.emberNames[label]=cached
            end
            local sub=secondary and Text.wrapLimited(secondary(value),list.width-h-p*2,UIFont.Small,2) or {}
            local quantity=value.pending and "..." or tostring(value.count)
            local block=math.max(columns.icon,#cached*h)
            return {
                lines=cached,
                secondary=sub,
                quantity=quantity,
                quantityX=list.width-h-p-getTextManager():MeasureStringX(UIFont.Small,quantity),
                height=p+block+#sub*h+4,
                block=block,
                icon=presentation and presentation:icon(value.fullType) or nil,
                pending=value.pending,
                pinned=value.pinned==true
            }
        end,
        draw=function(list,y,entry)
            local height=entry.height
            local visible=y+list:getYScroll()
            if visible+height<0 or visible>=list.height then return y+height end
            local h,p=list.emberFontHeight,list.emberPad
            local v,c=entry.item.visual,list.emberColumns
            if list.selected==entry.index then
                Theme.rect(list,0,y,list.width,height,Theme.selected)
                Theme.rect(list,0,y,math.max(2,h/6),height,Theme.accent)
            elseif list.mouseoverselected==entry.index then
                Theme.rect(list,0,y,list.width,height,Theme.hover)
            end

            -- Slot Icon Box (AE2 style slot frame)
            if c.icon>0 then
                local iconY=y+p/2+(v.block-c.icon)/2
                local slotBorder=v.pinned and Theme.gold or Theme.border
                Theme.rect(list,p,iconY,c.icon,c.icon,Theme.panel)
                Theme.rect(list,p,iconY,c.icon,c.icon,slotBorder,true)
                if v.icon then
                    list:drawTextureScaledAspect(v.icon,p+2,iconY+2,c.icon-4,c.icon-4,1,1,1,1)
                else
                    Theme.text(list,"?",p+c.icon/3,iconY+(c.icon-h)/2,Theme.muted)
                end
                if v.pinned then
                    Theme.text(list,"★",p+1,iconY-1,Theme.gold)
                end
            end

            local titleColor=v.pinned and Theme.gold or Theme.textColor
            for i,line in ipairs(v.lines) do
                Theme.text(list,line,c.name,y+p/2+(i-1)*h,i==1 and titleColor or Theme.textColor)
            end
            Theme.text(list,v.quantity,v.quantityX,y+p/2+(v.block-h)/2,v.pending and Theme.muted or Theme.accent)
            for i,line in ipairs(v.secondary) do
                Theme.text(list,line,p,y+p/2+v.block+(i-1)*h,Theme.muted)
            end

            -- Subtle bottom separator
            Theme.rect(list,0,y+height-1,list.width,1,{r=0.20,g=0.25,b=0.30,a=0.4})
            return y+height
        end
    }
end
function Table.empty(owner,list,label)
    if list.emberEmptyLabel~=label then
        list.emberEmptyLabel=label
        list.emberEmptyLines=Text.wrap(label,list.width-owner.pad*2,UIFont.Small)
        local capacity=math.max(0,math.floor((list.height-owner.pad*2)/owner.fontHeight))
        while #list.emberEmptyLines>capacity do table.remove(list.emberEmptyLines) end
    end
end
return Table
