-- Six compact counters and a measured-container coverage meter, prepared on change.
local Layout=require "EmberRoutesProbe/UI/Layout"
local Text=require "EmberRoutesProbe/UI/Text"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Visual=require "EmberRoutesProbe/UI/StatusVisual"
local Summary={}
local methods={} methods.__index=methods
function Summary.new(bounds,definitions,h,p,badges)
    local columns=assert(Layout.axis(bounds,{{grow=1},{grow=1},{grow=1}},{gap=p}))
    local self=setmetatable({cells={},badges=badges,fontHeight=h,pad=p,bounds=bounds,noteLines={}},methods)
    for i,definition in ipairs(definitions) do
        local r=columns[(i-1)%3+1]
        self.cells[i]={id=definition.id,label=Text.wrapLimited(definition.label,r.width*0.65-p-h,UIFont.Small,1)[1],
            x=r.x,y=r.y+math.floor((i-1)/3)*(h+p/3),width=r.width,value="--",valueX=r.x+r.width-p}
    end
    self.statusX=bounds.x self.statusY=bounds.y+(h+p/3)*2+p/3
    self.badgeWidth=math.min(bounds.width*0.4,h*10)
    self.noteX=self.statusX+self.badgeWidth+p self.noteWidth=bounds.width-self.badgeWidth-p
    self.color=Theme.muted
    return self
end
function methods:setValues(values)
    local changed=0
    for _,cell in ipairs(self.cells) do
        local value=values and values[cell.id]
        local display=value~=nil and value~=false and tostring(value) or "--"
        if cell.value~=display then
            cell.value=display changed=changed+1
            cell.valueX=cell.x+cell.width-self.pad/2-getTextManager():MeasureStringX(UIFont.Small,display)
        end
        cell.alert=(cell.id=="missing" or cell.id=="limited" or cell.id=="unloaded" or cell.id=="private") and tonumber(value) and tonumber(value)>0
        cell.color=(cell.id=="missing" or cell.id=="limited") and tonumber(value) and tonumber(value)>0
            and Visual.colors.blocked or cell.id=="unloaded" and tonumber(value) and tonumber(value)>0
            and Visual.colors.paused or Theme.textColor
    end
    return changed
end
function methods:setCoverage(loaded,total)
    self.coverage=loaded and total and total>0 and math.max(0,math.min(1,loaded/total)) or nil
end
function methods:setStatus(code,note)
    if self.status~=code then
        self.status=code self.color=code=="PARTIAL" and Visual.colors.paused or Theme.status[code] or Theme.status.ERROR
        self.badge=Visual.badge(self.badges[code] or code,code=="READY" and "done" or code=="UPDATING" and "active" or code=="PARTIAL" and "paused" or "blocked",
            self.badgeWidth,self.fontHeight,self.pad/3)
    end
    if self.note~=note then
        self.note=note self.noteLines=Text.wrapLimited(note,self.noteWidth,UIFont.Small,1)
    end
end
function methods:draw(owner)
    for _,cell in ipairs(self.cells) do
        Theme.rect(owner,cell.x,cell.y,cell.width,self.fontHeight+self.pad/6,Theme.control)
        if cell.alert then Visual.mark(owner,cell.x+self.pad/2,cell.y+self.fontHeight/4,self.fontHeight/2,"blocked",cell.color) end
        Theme.text(owner,cell.label,cell.x+self.pad/2+(cell.alert and self.fontHeight or 0),cell.y,Theme.muted)
        Theme.text(owner,cell.value,cell.valueX,cell.y,cell.color or Theme.textColor)
    end
    if self.badge then Visual.drawBadge(owner,self.statusX,self.statusY,self.badge) end
    for i,line in ipairs(self.noteLines) do Theme.text(owner,line,self.noteX,self.statusY+(i-1)*self.fontHeight,Theme.muted) end
    local r=self.bounds
    Visual.meter(owner,r.x,r.y+r.height-math.max(3,self.pad/3),r.width,math.max(3,self.pad/3),self.coverage,self.color)
end
return Summary
