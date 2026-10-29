-- Prepared recipe/material/chain drawing, isolated from dialog commands and subscriptions.
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local Rows={}
function Rows.style(self)
    local h,p=self.fontHeight,self.pad
    local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
    local function craftText(key,...) return getText('IGUI_EmberRoutesProbe_Crafting_'..key,...) end
    local blueprintStyle={emptyColor=Theme.muted}

    function blueprintStyle.prepare(list,row)
        local icon=row.fullType and self.presentation:icon(row.fullType) or nil
        if row.kind=='heading' then
            return {height=math.floor(h*1.5),icon=nil}
        elseif row.kind=='output' then
            local slotSize=math.floor(h*2.2)
            local textW=math.max(1,list.width-slotSize-p*3)
            local titleLines=Text.wrapLimited(row.title or row.label,textW,UIFont.Small,1)
            local subLines=row.sub and Text.wrapLimited(row.sub,textW,UIFont.Small,1) or {}
            local headerH=math.floor(h*1.2)
            return {
                height=slotSize+p+headerH,
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or '',
                sub=subLines[1] or '',
                headerH=headerH,
                sectionTitle=row.heading or text('outputHeading')
            }
        elseif row.kind=='input' then
            local slotSize=math.floor(h*2.0)
            local textW=math.max(1,list.width-slotSize-p*3)
            local titleLines=Text.wrapLimited(row.title or row.label,textW,UIFont.Small,1)
            local subLines=row.sub and Text.wrapLimited(row.sub,textW,UIFont.Small,1) or {}
            return {
                height=slotSize+p,
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or '',
                sub=subLines[1] or ''
            }
        elseif row.kind=='chain_step' then
            local slotSize=math.floor(h*1.8)
            local cardH=slotSize+math.floor(p*0.6)
            local connectorH=row.isLast and 0 or math.floor(h*0.9)
            local gap=math.floor(p/2)
            local textX=p+4+slotSize+gap
            local right=list.width-p-4
            local hasSurface=row.surfaceBadge and row.surfaceBadge~=''
            local available=math.max(0,right-textX-gap*(hasSurface and 2 or 1))
            local manager=getTextManager()
            local badgeLimit=math.floor(available/3)
            local stepW=math.min(manager:MeasureStringX(UIFont.Small,row.stepBadge or '')+p,badgeLimit)
            local surfaceW=hasSurface and math.min(manager:MeasureStringX(UIFont.Small,row.surfaceBadge)+p,badgeLimit) or 0
            local surfaceX=right-surfaceW
            local nameX=textX+stepW+gap
            local nameW=math.max(0,(hasSurface and surfaceX-gap or right)-nameX)
            local function fit(label,width)
                if not label or width<=0 then return '' end
                local clipped=Text.wrapLimited(label,width,UIFont.Small,1)[1] or ''
                return manager:MeasureStringX(UIFont.Small,clipped)<=width and clipped or ''
            end
            return {
                width=list.width,
                height=cardH+connectorH,
                icon=icon,
                slotSize=slotSize,
                cardH=cardH,
                connectorH=connectorH,
                title=fit(row.title or row.label,nameW),
                sub=fit(row.sub,math.max(0,right-textX-(row.canSwitch and row.switchText and (manager:MeasureStringX(UIFont.Small,row.switchText)+p+gap) or 0))),
                switchW=row.canSwitch and row.switchText and (manager:MeasureStringX(UIFont.Small,row.switchText)+p) or 0,
                stepBadge=fit(row.stepBadge,stepW-p),
                surfaceBadge=fit(row.surfaceBadge,surfaceW-p),
                textX=textX,nameX=nameX,stepW=stepW,surfaceX=surfaceX,surfaceW=surfaceW,
                isLast=row.isLast
            }
        else
            local lines=Text.wrapLimited(row.label or '',list.width-p*3,UIFont.Small,2)
            return {height=math.max(h+p,#lines*h+math.floor(p/2)),lines=lines,icon=nil}
        end
    end

    local activeList, activeScroll
    local function safeText(txt,tx,ty,color)
        if not txt or txt=='' then return end
        local sy=ty+activeScroll
        if sy+h>0 and sy<activeList.height then Theme.text(activeList,txt,tx,ty,color) end
    end

    local function safeRect(rx,ry,rw,rh,color,border)
        if not color or rw<=0 or rh<=0 then return end
        local sy=ry+activeScroll
        if sy+rh<=0 or sy>=activeList.height then return end
        local clipTop=math.max(0,-sy)
        local clipBottom=math.max(0,(sy+rh)-activeList.height)
        local drawY=ry+clipTop
        local drawH=rh-clipTop-clipBottom
        if drawH>0 then Theme.rect(activeList,rx,drawY,rw,drawH,color,border) end
    end

    local function safeTexture(tex,tx,ty,tw,th)
        if not tex then return end
        local sy=ty+activeScroll
        if sy+th>0 and sy<activeList.height then activeList:drawTextureScaledAspect(tex,tx,ty,tw,th,1,1,1,1) end
    end

    function blueprintStyle.draw(list,y,entry)
        local row,v=entry.item.value,entry.item.visual
        if row.kind=='chain_step' and v.width~=list.width then
            v=blueprintStyle.prepare(list,row) entry.item.visual=v
        end
        local scroll=list:getYScroll()
        local visible=y+scroll
        if visible+entry.height<=0 or visible>=list.height then return y+entry.height end
        activeList=list activeScroll=scroll

        if row.kind=='heading' then
            local barH=math.floor(h*1.2)
            local barY=y+math.floor((entry.height-barH)/2)
            safeRect(p,barY,list.width-p*2,barH,Theme.control,false)
            local accentColor=row.section=='tools' and {r=0.94,g=0.73,b=0.36,a=1} or Theme.accent
            safeRect(p,barY,3,barH,accentColor,false)
            safeText(row.label,p+8,barY+math.floor((barH-h)/2),Theme.textColor)
            return y+entry.height
        end

        if row.kind=='output' then
            local headerH=v.headerH or math.floor(h*1.2)
            local barH=math.floor(h*1.1)
            safeRect(p,y+2,list.width-p*2,barH,Theme.control,false)
            safeRect(p,y+2,3,barH,Theme.gold,false)
            safeText(v.sectionTitle or text('outputHeading'),p+8,y+2+math.floor((barH-h)/2),Theme.gold)

            local slotSize=v.slotSize or math.floor(h*2.2)
            local slotX=p
            local slotY=y+headerH+math.floor(p/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.panel,false)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.gold,true)

            if v.icon then safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4) end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            safeText(v.title or '',textX,titleY,Theme.textColor)
            if v.sub and v.sub~='' then safeText(v.sub,textX,subY,Theme.muted) end
            return y+entry.height
        end

        if row.kind=='input' then
            local slotSize=v.slotSize or math.floor(h*2.0)
            local slotX=p
            local slotY=y+math.floor((entry.height-slotSize)/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.panel,false)

            local borderColor=Theme.border
            local countColor=Theme.textColor
            if row.precursor then
                borderColor=Theme.accent countColor=Theme.accent
            elseif row.isTool then
                borderColor={r=0.94,g=0.73,b=0.36,a=1}
                countColor=row.missing and {r=0.95,g=0.35,b=0.30,a=1} or {r=0.35,g=0.88,b=0.60,a=1}
            elseif row.missing then
                borderColor={r=0.95,g=0.35,b=0.30,a=1}
                countColor={r=0.95,g=0.35,b=0.30,a=1}
            elseif row.known then
                borderColor=Theme.border
                countColor={r=0.35,g=0.88,b=0.60,a=1}
            end
            safeRect(slotX,slotY,slotSize,slotSize,borderColor,true)

            if v.icon then safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4) end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            safeText(v.title or '',textX,titleY,Theme.textColor)
            safeText(v.sub or '',textX,subY,countColor)

            if row.isTool then
                local badgeText=craftText('toolBadge')
                local bw=getTextManager():MeasureStringX(UIFont.Small,badgeText)+p
                local bx=list.width-p-bw
                safeRect(bx,titleY,bw,h,Theme.control,false)
                safeRect(bx,titleY,bw,h,borderColor,true)
                safeText(badgeText,bx+math.floor(p/2),titleY,borderColor)
            elseif row.precursor then
                local chainText=text('chainSupplyTag')
                local bw=getTextManager():MeasureStringX(UIFont.Small,chainText)+p
                local bx=list.width-p-bw
                safeRect(bx,titleY,bw,h,Theme.control,false)
                safeRect(bx,titleY,bw,h,Theme.accent,true)
                safeText(chainText,bx+math.floor(p/2),titleY,Theme.accent)
            end

            return y+entry.height
        end

        if row.kind=='chain_step' then
            local cardW=list.width-p*2
            local cardH=v.cardH or math.floor(h*2.4)
            local cardY=y
            local isLast=row.isLast
            local nodeColor=isLast and Theme.gold or Theme.accent

            safeRect(p,cardY,cardW,cardH,Theme.panel,false)
            safeRect(p,cardY,cardW,cardH,isLast and nodeColor or Theme.border,true)

            local slotSize=v.slotSize or math.floor(h*1.8)
            local slotX=p+4
            local slotY=cardY+math.floor((cardH-slotSize)/2)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.control,false)
            safeRect(slotX,slotY,slotSize,slotSize,isLast and nodeColor or Theme.border,true)
            if v.icon then safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4) end

            local badgeH=math.floor(h*1.0)
            local badgeW=v.stepW
            local textX=v.textX
            local titleY=cardY+math.max(2,math.floor((cardH-h*2)/2))
            local subY=titleY+h

            safeRect(textX,titleY,badgeW,badgeH,Theme.control,false)
            safeRect(textX,titleY,badgeW,badgeH,nodeColor,true)
            safeText(v.stepBadge,textX+math.floor(p/2),titleY+math.floor((badgeH-h)/2),nodeColor)

            local nameX=v.nameX
            safeText(v.title or '',nameX,titleY,Theme.textColor)
            safeText(v.sub or '',textX,subY,nodeColor)

            if row.canSwitch and v.switchW and v.switchW>0 and row.switchText then
                local sx=list.width-p-4-v.switchW
                safeRect(sx,subY-1,v.switchW,badgeH,Theme.control,false)
                safeRect(sx,subY-1,v.switchW,badgeH,Theme.accent,true)
                safeText(row.switchText,sx+math.floor(p/2),subY+math.floor((badgeH-h)/2),Theme.accent)
            end

            if row.surfaceBadge then
                local sW=v.surfaceW
                local sX=v.surfaceX
                safeRect(sX,titleY,sW,badgeH,Theme.control,false)
                safeRect(sX,titleY,sW,badgeH,Theme.border,true)
                safeText(v.surfaceBadge,sX+math.floor(p/2),titleY+math.floor((badgeH-h)/2),Theme.muted)
            end

            if not isLast then
                local pipeX=math.floor(list.width/2)
                local pipeTop=cardY+cardH
                local connH=v.connectorH or math.floor(h*0.9)
                local pipeBottom=pipeTop+connH
                safeRect(pipeX-1,pipeTop,2,connH-5,Theme.accent,false)
                safeRect(pipeX-4,pipeBottom-6,8,1,Theme.accent,false)
                safeRect(pipeX-3,pipeBottom-5,6,1,Theme.accent,false)
                safeRect(pipeX-2,pipeBottom-4,4,1,Theme.accent,false)
                safeRect(pipeX-1,pipeBottom-3,2,2,Theme.accent,false)
            end

            return y+entry.height
        end

        local color=row.missing and {r=0.95,g=0.35,b=0.30,a=1} or Theme.textColor
        for i,line in ipairs(v.lines or {}) do
            safeText(line,p,y+math.floor(p/4)+(i-1)*h,color)
        end
        return y+entry.height
    end

    return blueprintStyle
end
return Rows
