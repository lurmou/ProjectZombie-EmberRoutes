local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Text=require 'EmberRoutesProbe/UI/Text'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local StatMeter=require 'EmberRoutesProbe/UI/StatMeter'
local SemanticBadge=require 'EmberRoutesProbe/UI/SemanticBadge'
local CardPanel=require 'EmberRoutesProbe/UI/CardPanel'
local progressStyle={mode='progress'}
local Info={}
function Info.new(owner,bounds,options)
    local dossier=options and options.dossier
    local Slot=dossier and require 'EmberRoutesProbe/UI/ItemSlot'
    local Avatar=dossier and require 'EmberRoutesProbe/UI/Avatar3DView'
    local icons=require('EmberRoutesProbe/UI/ItemPresentation').new()
    local style={emptyColor=Theme.muted,prepare=function(list,row)
        if row.isCardRow then
            local h,p=owner.fontHeight,owner.pad
            local width=math.max(1,list.width-p*2)
            local titleFont=row.hero and (UIFont.Medium or UIFont.Small) or UIFont.Small
            local titleFontH=getTextManager():getFontHeight(titleFont)
            local badge=not dossier and row.status and SemanticBadge.resolve(row.status,row.statusText)
            local badgeW=0
            if badge then
                badge.fontHeight=h
                badge.displayText=Text.wrapLimited(badge.displayText,math.max(1,width-p*2),UIFont.Small,1)[1] or ''
                badge.textWidth=getTextManager():MeasureStringX(UIFont.Small,badge.displayText)
                badgeW=badge.textWidth+SemanticBadge.ICON_SLOT+p*2
            end
            local below=badge and width-p*3-badgeW<h*6
            local title=Text.wrap(row.title or '',math.max(1,width-p*2-(row.portrait and h*3+p or 0)-(below and 0 or badgeW+p)),titleFont)
            local titleH=math.max(titleFontH,#title*titleFontH)
            local badgeY=below and p+titleH+p/2 or p
            local top=below and badgeY+h+p*1.5 or p+math.max(titleH,badge and h+p or 0)+p/2
            local lines={}
            local lineStart=top
            for _,line in ipairs(row.lines or {}) do
                local value=type(line)=='table' and line.text or line
                local color=type(line)=='table' and line.color or Theme.muted
                if value and value~='' then
                    for _,part in ipairs(Text.wrap(value,math.max(1,width-p*2-(row.portrait and h*3+p or 0)),UIFont.Small)) do
                        lines[#lines+1]={text=part,y=top,color=dossier and Theme.dossier.muted or color or Theme.muted} top=top+h
                    end
                end
            end
            if dossier then top=lineStart end
            local meters={}
            for _,meter in ipairs(row.meters or {}) do
                local values=meter.value and (dossier and Text.wrap(meter.value,math.max(1,width-p*2),titleFont) or {meter.value}) or {}
                local valueW=0
                for _,value in ipairs(values) do valueW=math.max(valueW,getTextManager():MeasureStringX(titleFont,value)) end
                local label=Text.wrap(meter.text or '',math.max(1,width-p*3-valueW),UIFont.Small)
                local labelH=math.max(#label*h,math.max(1,#values)*titleFontH)
                meters[#meters+1]={lines=label,y=top+p/2,fraction=meter.fraction,value=meter.value,values=values,valueW=valueW,labelH=labelH}
                top=top+p/2+labelH+h/2+p/2
            end
            if dossier then
                local offset=top-lineStart
                for _,line in ipairs(lines) do line.y=line.y+offset end
                top=top+#lines*h
            end
            local portrait=row.portrait
            local portraitSize=portrait and h*3 or 0
            if portrait then top=math.max(top,portraitSize+p*2) end
            local frame=dossier and {frameStyle=row.hero and 'briefing' or 'plain',
                backgroundColor=row.hero and Theme.dossier.control or Theme.dossier.background,
                borderColor=Theme.dossier.separator,statusColor=row.alert and Theme.dossier.alert or nil}
            return {portrait=portrait,portraitSize=portraitSize,alert=row.alert,dossier=dossier,isCardRow=true,width=width,height=top+p*1.5,title=title,lines=lines,meters=meters,
                badge=badge,badgeW=badgeW,badgeY=badgeY,frame=frame or {statusColor=badge and badge.color,
                    frameStyle=row.hero and 'briefing' or nil,backgroundColor=row.hero and Theme.control or nil},p=p,h=h,
                titleFont=titleFont,titleFontH=titleFontH}
        end
        if row.isSlotRow and dossier then
            local h,p=owner.fontHeight,owner.pad
            local cols=list.width>=h*24 and 2 or 1
            local cellW=math.max(1,(list.width-p*(cols+1))/cols)
            local cellH=h*3+p
            local slots={}
            for i,asset in ipairs(row.slots) do
                slots[i]=Slot.prepare({icon=icons:icon(asset.fullType),name=asset.name,
                    countText='x '..tostring(asset.count or 1),status=asset.status},
                    {x=p+((i-1)%cols)*(cellW+p),y=math.floor((i-1)/cols)*cellH,width=cellW,height=cellH},Theme.revision)
            end
            return {slots=slots,height=math.ceil(#slots/cols)*cellH}
        end
        if row.isAssetRow then
            local icon=icons:icon(row.fullType)
            local h=owner.fontHeight
            local rowH=math.max(26,math.floor(h*1.6))
            local badgeDesc=SemanticBadge.resolve(row.status or 'STORED',row.statusText)
            local tm=getTextManager()
            local badgeW=tm:MeasureStringX(UIFont.Small,badgeDesc.displayText or badgeDesc.label or '')+SemanticBadge.ICON_SLOT+12
            badgeDesc.fontHeight=h badgeDesc.textWidth=badgeW-SemanticBadge.ICON_SLOT-12
            local countStr='x '..tostring(row.count or 1)
            local countW=tm:MeasureStringX(UIFont.Small,countStr)
            local cardW=math.max(10,list.width-owner.pad*2)
            local iconSize=rowH-6
            local countX=cardW-countW-6
            local badgeX=countX-badgeW-8
            local showBadge=badgeX>3+iconSize+60
            local nameX=3+iconSize+6
            local nameW=math.max(20,(showBadge and badgeX or countX)-nameX-4)
            local displayName=Text.wrapLimited(row.name or (row.fullType and getItemNameFromFullType(row.fullType)) or '?',nameW,UIFont.Small,1)[1] or ''
            return {isAssetRow=true,icon=icon,badgeDesc=badgeDesc,badgeW=badgeW,countStr=countStr,countW=countW,height=rowH+4,
                cardW=cardW,iconSize=iconSize,countX=countX,badgeX=badgeX,showBadge=showBadge,nameX=nameX,name=displayName,
                frame={statusColor=badgeDesc.color}}
        end
        local icon=icons:icon(row.fullType)
        local offset=icon and owner.fontHeight*1.5+owner.pad or 0
        if row.compact then
            local tm=getTextManager()
            local labelW=row.labelW or math.max(36,tm:MeasureStringX(UIFont.Small,row.text or '')+8)
            local meterH=math.max(10,math.floor(owner.fontHeight*0.65))
            local pctStr=row.meterLabel or (row.fraction and (math.floor(row.fraction*100)..'%') or '')
            local pctW=pctStr~='' and (tm:MeasureStringX(UIFont.Small,pctStr)+8) or 0
            return {lines={},icon=nil,offset=0,labelW=labelW,meterH=meterH,pctStr=pctStr,pctW=pctW,compact=true,
                    height=owner.fontHeight+math.max(4,math.floor(owner.pad*0.4))}
        end
        local lines=Text.wrap(row.text or '',math.max(1,list.width-owner.pad*3-offset),UIFont.Small)
        local meterH=row.fraction and math.max(6,math.floor(owner.fontHeight*0.55)) or 0
        return {lines=lines,icon=icon,offset=offset,meterH=meterH,compact=false,
                height=math.max(icon and owner.fontHeight*1.5 or 0,#lines*owner.fontHeight)+owner.pad/2+(meterH>0 and (meterH+owner.pad/3) or 0)}
    end,draw=function(list,y,entry)
        local v=entry.item.visual local row=entry.item.value
        if y+list:getYScroll()+entry.height<=0 or y+list:getYScroll()>=list.height then return y+entry.height end
        if v.slots then
            -- Cached local coordinates share the list's native row transform.
            for _,slot in ipairs(v.slots) do list:drawItemSlot(y,slot) end
            return y+entry.height
        end
        if v.isCardRow then
            local x,p,h=owner.pad,v.p,v.h
            local textX=x+p+(v.portrait and v.portraitSize+p or 0)
            CardPanel.draw(list,x,y+p/2,v.width,entry.height-p,v.frame)
            for i,line in ipairs(v.title) do local color=v.dossier and (v.alert and Theme.dossier.alert or Theme.dossier.text) or Theme.textColor
                list:drawText(line,textX,y+p+(i-1)*v.titleFontH,color.r,color.g,color.b,color.a or 1,v.titleFont)
            end
            if v.portrait then Avatar.drawSnapshot(list,v.portrait,x+p,y+p,v.portraitSize) end
            if v.badge then SemanticBadge.draw(list,x+v.width-v.badgeW-p,y+v.badgeY,v.badgeW,h+p,v.badge) end
            for _,line in ipairs(v.lines) do Theme.text(list,line.text,textX,y+line.y,line.color) end
            for _,meter in ipairs(v.meters) do
                for i,line in ipairs(meter.lines) do Theme.text(list,line,x+p,y+meter.y+(i-1)*h,v.dossier and Theme.dossier.muted or Theme.textColor) end
                if meter.value then local color=v.dossier and Theme.dossier.gold or Theme.gold
                    for i,value in ipairs(meter.values) do list:drawText(value,x+v.width-p-meter.valueW,y+meter.y+(i-1)*v.titleFontH,color.r,color.g,color.b,color.a or 1,v.titleFont) end
                end
                if meter.fraction~=nil then StatMeter.draw(list,x+p,y+meter.y+meter.labelH+p/3,math.max(1,v.width-p*2),h/3,meter.fraction,v.dossier and list.dossierMeter or progressStyle) end
            end
            return y+entry.height
        end
        if v.isAssetRow then
            local cardX=owner.pad
            local cardY=y+2
            local cardW=v.cardW
            local cardH=entry.height-4
            local h=owner.fontHeight

            CardPanel.draw(list,cardX,cardY,cardW,cardH,v.frame)

            local iconSize=v.iconSize
            local iconX=cardX+3
            local iconY=cardY+3
            if v.icon then
                list:drawTextureScaledAspect(v.icon,iconX+1,iconY+1,iconSize-2,iconSize-2,1,1,1,1)
            end

            local countX=cardX+v.countX
            local textY=cardY+math.floor((cardH-h)/2)
            Theme.text(list,v.countStr,countX,textY,Theme.gold or Theme.textColor)

            local badgeH=h+2
            local badgeY=cardY+math.floor((cardH-badgeH)/2)
            local badgeX=cardX+v.badgeX
            if v.showBadge then
                SemanticBadge.draw(list,badgeX,badgeY,v.badgeW,badgeH,v.badgeDesc)
            end

            Theme.text(list,v.name,cardX+v.nameX,textY,Theme.textColor)

            return y+entry.height
        end
        if v.compact then
            local rowH=entry.height
            local labelW=v.labelW
            local pad=owner.pad
            local top=y+(rowH-owner.fontHeight)/2
            Theme.text(list,row.text or '',pad,top,row.color or Theme.textColor)
            local barX=pad+labelW
            local barW=math.max(10,list.width-barX-pad*2-(v.pctW or 0))
            local barY=y+(rowH-v.meterH)/2
            StatMeter.draw(list,barX,barY,barW,v.meterH,row.fraction or 0,{
                mode=row.meterMode or 'health',
                color=row.barColor or row.color,
                showPercent=false,
                label=nil
            })
            if v.pctStr and v.pctStr~='' then
                Theme.text(list,v.pctStr,barX+barW+6,top,Theme.textColor)
            end
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
    if dossier then
        Theme.dossierList(list)
        list.dossierMeter={mode='progress',color=Theme.dossier.active,plain=true,trough=Theme.dossier.panel}
        function list:drawItemSlot(y,cache) Slot.draw(self,cache,y) end
    end
    local api={list=list}
    function api:set(rows)
        if dossier then list.dossierMeter={mode='progress',color=Theme.dossier.active,plain=true,trough=Theme.dossier.panel} end
        if dossier then
            local packed,group={},nil
            for _,row in ipairs(rows) do
                if row.isAssetRow then
                    if not group then group={isSlotRow=true,slots={}} packed[#packed+1]=group end
                    group.slots[#group.slots+1]=row
                else group=nil packed[#packed+1]=row end
            end
            rows=packed
        end
        for i,row in ipairs(rows) do row.key=i end
        Cached.reconcile(list,rows,function(row)
            local parts={row.title or '',row.statusText or '',row.status or '',tostring(row.hero),tostring(row.portrait),tostring(Theme.revision)}
            for _,line in ipairs(row.lines or {}) do parts[#parts+1]=type(line)=='table' and line.text or line end
            for _,asset in ipairs(row.slots or {}) do parts[#parts+1]=tostring(asset.fullType)..tostring(asset.name)..tostring(asset.status)..tostring(asset.count) end
            for _,meter in ipairs(row.meters or {}) do parts[#parts+1]=meter.text parts[#parts+1]=tostring(meter.fraction) parts[#parts+1]=meter.value or '' end
            return table.concat(parts,'|')..(row.text or '')..tostring(row.color)..tostring(row.fraction)
                ..tostring(row.fullType)..tostring(row.compact)..tostring(row.meterLabel)
                ..tostring(row.isAssetRow)..tostring(row.statusText)..tostring(row.status)..tostring(row.count)
                ..tostring(row.name)..tostring(row.credited)
        end,function(row) return row.key end,true)
    end
    return api
end
return Info
