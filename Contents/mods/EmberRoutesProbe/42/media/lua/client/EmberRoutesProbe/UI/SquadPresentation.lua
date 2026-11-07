-- Pure projection: all measurement and string work happens before rendering.
local Text=require 'EmberRoutesProbe/UI/Text'
local Badge=require 'EmberRoutesProbe/UI/SemanticBadge'
local P={}
function P.cards(rows,selected,width,layout,palette,preferences,hovered,scroll)
    local cards={} local y=0 local h,pad=layout.h,layout.pad
    local top=math.max(layout.portrait+pad,h*2+10)
    local ch=top+h*4+pad+4
    for _,row in ipairs(rows) do
        local alias=preferences.callsigns[row.id]
        local display=alias or row.name
        local healthColor=row.health==nil and palette.muted or row.health<=30 and palette.status.ERROR
            or row.health<=60 and palette.status.UPDATING or palette.status.READY
        local card={id=row.id,y=layout.header+y-scroll,contentY=y,height=ch,portrait=row.portrait,health=row.health,
            healthColor=healthColor,top=top,badges={},
            opts={selected=selected[row.id],hover=hovered==row.id,statusColor=row.blocked and palette.status.ERROR or nil}}
        local textWidth=width-pad*4
        card.name=Text.wrapLimited(tostring(row.slot+1)..'  '..display,textWidth-layout.portrait-pad,UIFont.Small,1)[1]
        card.healthText=Text.wrapLimited(row.healthText,textWidth-layout.portrait-pad,UIFont.Small,1)[1]
        -- Two adjacent lines are position-only otherwise; prefix them with the
        -- existing Order / Activity labels so the distinction survives without
        -- relying on colour or row order.
        card.command=Text.wrapLimited(getText('IGUI_EmberRoutesProbe_Squad_command')..': '..tostring(row.command),textWidth,UIFont.Small,1)[1]
        card.actual=Text.wrapLimited(getText('IGUI_EmberRoutesProbe_Squad_actual')..': '..tostring(row.actual),textWidth,UIFont.Small,1)[1]
        card.feedback=Text.wrapLimited(row.feedback,textWidth,UIFont.Small,1)[1]
        card.feedbackColor=row.blocked and palette.status.ERROR or palette.muted
        local lines={display}
        if alias then lines[#lines+1]=row.name end
        for _,text in ipairs({row.healthText,row.command,row.actual,row.feedback}) do if text~='' then lines[#lines+1]=text end end
        local badgeWidth=math.floor((textWidth-pad)/2)
        for i,mood in ipairs(row.moods) do
            lines[#lines+1]=mood.label
            if i<=2 then
                local descriptor=Badge.resolve(mood.tone,mood.label)
                descriptor.displayText=Text.wrapLimited(descriptor.displayText,badgeWidth-8-Badge.ICON_SLOT,UIFont.Small,1)[1]
                descriptor.fontHeight=h descriptor.textWidth=getTextManager():MeasureStringX(UIFont.Small,descriptor.displayText)
                card.badges[#card.badges+1]={x=(i-1)*(badgeWidth+pad),width=badgeWidth,descriptor=descriptor}
            end
        end
        card.tooltip=table.concat(lines,' <LINE> ')
        cards[#cards+1]=card y=y+ch+pad
    end
    return cards,math.max(0,y-pad)
end
return P
