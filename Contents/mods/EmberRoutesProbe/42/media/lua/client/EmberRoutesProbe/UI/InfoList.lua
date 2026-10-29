local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Text=require 'EmberRoutesProbe/UI/Text'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local StatMeter=require 'EmberRoutesProbe/UI/StatMeter'
local SemanticBadge=require 'EmberRoutesProbe/UI/SemanticBadge'
local Info={}
function Info.new(owner,bounds)
    local icons=require('EmberRoutesProbe/UI/ItemPresentation').new()
    local style={emptyColor=Theme.muted,prepare=function(list,row)
        if row.isAssetRow then
            local icon=icons:icon(row.fullType)
            local h=owner.fontHeight
            local rowH=math.max(26,math.floor(h*1.6))
            local badgeDesc=SemanticBadge.resolve(row.status or 'STORED',row.statusText)
            local tm=getTextManager()
            local badgeW=tm:MeasureStringX(UIFont.Small,badgeDesc.displayText or badgeDesc.label or '')+12
            local countStr='× '..tostring(row.count or 1)
            local countW=tm:MeasureStringX(UIFont.Small,countStr)
            return {isAssetRow=true,icon=icon,badgeDesc=badgeDesc,badgeW=badgeW,countStr=countStr,countW=countW,height=rowH+4}
        end
        local icon=icons:icon(row.fullType)
        local offset=icon and owner.fontHeight*1.5+owner.pad or 0
        if row.compact then
            local labelW=row.labelW or math.max(36,getTextManager():MeasureStringX(UIFont.Small,row.text or '')+8)
            local meterH=math.max(12,math.floor(owner.fontHeight*0.85))
            return {lines={},icon=nil,offset=0,labelW=labelW,meterH=meterH,compact=true,
                    height=owner.fontHeight+math.max(4,math.floor(owner.pad*0.4))}
        end
        local lines=Text.wrap(row.text or '',math.max(1,list.width-owner.pad*3-offset),UIFont.Small)
        local meterH=row.fraction and math.max(6,math.floor(owner.fontHeight*0.55)) or 0
        return {lines=lines,icon=icon,offset=offset,meterH=meterH,compact=false,
                height=math.max(icon and owner.fontHeight*1.5 or 0,#lines*owner.fontHeight)+owner.pad/2+(meterH>0 and (meterH+owner.pad/3) or 0)}
    end,draw=function(list,y,entry)
        local v=entry.item.visual local row=entry.item.value
        if y+list:getYScroll()+entry.height<=0 or y+list:getYScroll()>=list.height then return y+entry.height end
        if v.isAssetRow then
            local cardX=owner.pad
            local cardY=y+2
            local cardW=math.max(10,list.width-owner.pad*2)
            local cardH=entry.height-4
            local tm=getTextManager()
            local h=owner.fontHeight

            local isAlert=(row.status=='MISSING' or row.status=='DISCREPANCY')
            local bg=isAlert and {r=0.20,g=0.08,b=0.08,a=0.85} or Theme.control
            local border=isAlert and {r=0.65,g=0.25,b=0.25,a=0.80} or Theme.border
            Theme.rect(list,cardX,cardY,cardW,cardH,bg)
            Theme.rect(list,cardX,cardY,cardW,cardH,border,true)

            local iconSize=cardH-6
            local iconX=cardX+3
            local iconY=cardY+3
            Theme.rect(list,iconX,iconY,iconSize,iconSize,{r=0.04,g=0.06,b=0.08,a=0.90})
            Theme.rect(list,iconX,iconY,iconSize,iconSize,{r=0.25,g=0.30,b=0.35,a=0.50},true)
            if v.icon then
                list:drawTextureScaledAspect(v.icon,iconX+1,iconY+1,iconSize-2,iconSize-2,1,1,1,1)
            end

            local countX=cardX+cardW-v.countW-6
            local textY=cardY+math.floor((cardH-h)/2)
            Theme.text(list,v.countStr,countX,textY,Theme.gold or Theme.textColor)

            local badgeH=h+2
            local badgeY=cardY+math.floor((cardH-badgeH)/2)
            local badgeX=countX-v.badgeW-8
            if badgeX>iconX+iconSize+60 then
                SemanticBadge.draw(list,badgeX,badgeY,v.badgeW,badgeH,v.badgeDesc)
            end

            local nameX=iconX+iconSize+6
            local availNameW=math.max(20,(badgeX>iconX+iconSize+60 and badgeX or countX)-nameX-4)
            local nameStr=row.name or (row.fullType and getItemNameFromFullType(row.fullType)) or '?'
            local displayName=Text.wrapLimited(nameStr,availNameW,UIFont.Small,1)[1] or nameStr
            Theme.text(list,displayName,nameX,textY,Theme.textColor)

            return y+entry.height
        end
        if v.compact then
            local rowH=entry.height
            local labelW=v.labelW
            local pad=owner.pad
            local top=y+(rowH-owner.fontHeight)/2
            Theme.text(list,row.text or '',pad,top,row.color or Theme.textColor)
            local barX=pad+labelW
            local barW=math.max(10,list.width-barX-pad*2)
            local barY=y+(rowH-v.meterH)/2
            StatMeter.draw(list,barX,barY,barW,v.meterH,row.fraction or 0,{
                mode=row.meterMode or 'health',
                color=row.barColor or row.color,
                showPercent=(row.showPercent~=false),
                label=row.meterLabel,
                labelW=row.meterLabelW
            })
            return y+entry.height
        end
        if v.icon then list:drawTextureScaledAspect(v.icon,owner.pad,y,owner.fontHeight*1.5,owner.fontHeight*1.5,1,1,1,1) end
        for i,line in ipairs(v.lines) do
            local top=y+(i-1)*owner.fontHeight
            if top+list:getYScroll()+owner.fontHeight>0 and top+list:getYScroll()<list.height then
                Theme.text(list,line,owner.pad+v.offset,top,row.color or Theme.textColor)
            end
        end
        if row.fraction and v.meterH>0 then
            StatMeter.draw(list,owner.pad,y+#v.lines*owner.fontHeight+2,
                math.max(1,list.width-owner.pad*3),v.meterH,row.fraction,
                {mode=row.meterMode or 'custom',color=row.color,capFraction=row.capFraction})
        end
        return y+entry.height
    end}
    local list=Cached.create(owner,bounds,nil,style) Theme.list(list) owner:addChild(list)
    local api={list=list}
    function api:set(rows)
        for i,row in ipairs(rows) do row.key=i end
        Cached.reconcile(list,rows,function(row)
            return (row.text or '')..tostring(row.color)..tostring(row.fraction)
                ..tostring(row.fullType)..tostring(row.compact)..tostring(row.meterLabel)
                ..tostring(row.isAssetRow)..tostring(row.status)..tostring(row.count)
                ..tostring(row.name)..tostring(row.credited)
        end,function(row) return row.key end,true)
    end
    return api
end
return Info
