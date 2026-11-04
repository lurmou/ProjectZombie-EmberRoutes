-- Display-only primitive. No item instances, inventory or domain records.
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Badge=require 'EmberRoutesProbe/UI/SemanticBadge'
local Text=require 'EmberRoutesProbe/UI/Text'
local Slot={}
function Slot.prepare(spec,bounds,themeRevision)
    local h=getTextManager():getFontHeight(UIFont.Small)
    local p=math.ceil(h*.4)
    local size=math.min(h*2,math.max(0,bounds.height-p*2))
    local count=spec.countText or ''
    local countW=getTextManager():MeasureStringX(UIFont.Small,count)
    local status=spec.status
    local statusText=status and Badge.resolve(status).displayText or ''
    statusText=Text.wrapLimited(statusText,math.max(1,bounds.width-size-p*3),UIFont.Small,1)[1] or ''
    local d=Theme.dossier
    return {x=bounds.x,y=bounds.y,width=bounds.width,height=bounds.height,revision=themeRevision,
        icon=spec.icon,name=Text.wrapLimited(spec.name or '',math.max(1,bounds.width-size-countW-p*4),UIFont.Small,1)[1] or '',
        countText=count,countW=countW,status=status,statusText=statusText,selected=spec.selected,p=p,h=h,size=size,
        text=d.text,muted=d.muted,line=d.separator,gold=d.gold,
        indicator=(status=='RECONCILE' or status=='MISSING' or status=='DISCREPANCY') and d.alert or nil}
end
function Slot.draw(owner,c,offsetY)
    local x,y,p=c.x,c.y+(offsetY or 0),c.p
    Theme.rect(owner,x,y+c.height-1,c.width,1,c.line)
    if c.selected then Theme.rect(owner,x,y,2,c.height,c.gold) end
    if c.indicator then Theme.rect(owner,x,y,2,c.height,c.indicator) end
    if c.icon then owner:drawTextureScaledAspect(c.icon,x+p,y+p,c.size,c.size,1,1,1,1) end
    Theme.text(owner,c.name,x+c.size+p*2,y+p,c.text)
    Theme.text(owner,c.statusText,x+c.size+p*2,y+p+c.h,c.indicator or c.muted)
    Theme.text(owner,c.countText,x+c.width-c.countW-p,y+p,c.muted)
end
function Slot.hit(c,x,y)
    return x>=c.x and y>=c.y and x<c.x+c.width and y<c.y+c.height
end
return Slot
