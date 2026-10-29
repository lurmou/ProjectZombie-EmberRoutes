require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISComboBox'
require 'ISUI/ISButton'
local Public=require 'EmberRoutesProbe/PublicWork'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
EmberRoutesWorkPriorityDialog=ISCollapsableWindow:derive('EmberRoutesWorkPriorityDialog')
function EmberRoutesWorkPriorityDialog.open(owner)
    local categories=Public.categories()
    local h=owner.fontHeight local w=math.min(getCore():getScreenWidth()*0.9,h*27) local height=math.min(getCore():getScreenHeight()*0.94,h*(11+#categories))
    local o=ISCollapsableWindow.new(EmberRoutesWorkPriorityDialog,(getCore():getScreenWidth()-w)/2,(getCore():getScreenHeight()-height)/2,w,height)
    o.owner,o.actor,o.entry=owner,owner.actor,owner.entry o.fontHeight,o.pad=h,owner.pad
    o.categories=categories
    o.title=text('priorities') o.backgroundColor=Theme.window o.borderColor=Theme.border o.resizable=false
    o:initialise() o:addToUIManager() return o
end
function EmberRoutesWorkPriorityDialog:initialise() ISCollapsableWindow.initialise(self) end
function EmberRoutesWorkPriorityDialog:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad local y=self:titleBarHeight()+p
    self.combo=ISComboBox:new(p,y,self.width-p*2,h+p,self,function() self:selectWorker() end)
    self.combo:initialise() self:addChild(self.combo) self.ids={}
    for _,worker in ipairs(require('EmberRoutesProbe/CraftingService').status(self.actor,self.entry.id).workers) do
        self.ids[#self.ids+1]=worker.id self.combo:addOption(worker.name)
    end
    self.fields={}
    for i,key in ipairs(self.categories) do
        local c=ISComboBox:new(self.width/2,y+(h+p)*(i+1),self.width/2-p,h+p,self,nil)
        c:initialise() self:addChild(c)
        for n=0,4 do c:addOption(text('priority_'..n)) end self.fields[key]=c
    end
    self.save=ISButton:new(p,self.height-h*4,self.width-p*2,h+p,text('savePriorities'),self,function()
        if not self.owner:valid() then self:close() return end
        local id=self.ids[self.combo.selected] if not id then return end
        local values={} for key,combo in pairs(self.fields) do values[key]=combo.selected-1 end
        self.notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(Public.setPriorities(self.actor,self.entry.id,id,values,self.revision))
        self:selectWorker()
    end)
    self.save:initialise() Theme.button(self.save,true) self:addChild(self.save) self:selectWorker()
end
function EmberRoutesWorkPriorityDialog:selectWorker()
    local id=self.ids[self.combo.selected]
    Theme.enable(self.save,id~=nil,true) if not id then return end
    local p=Public.priorities(id) self.revision=p.revision
    for key,combo in pairs(self.fields) do combo.selected=p[key]+1 end
end
function EmberRoutesWorkPriorityDialog:prerender()
    ISCollapsableWindow.prerender(self)
    local h,p=self.fontHeight,self.pad local y=self:titleBarHeight()+p
    for i,key in ipairs(self.categories) do Theme.text(self,text(key),p,y+(h+p)*(i+1)+p/2,Theme.textColor) end
    local lines=Text.wrapLimited(self.notice or text('priorityHint'),self.width-p*2,UIFont.Small,2)
    for i,line in ipairs(lines) do Theme.text(self,line,p,self.height-h*2-p/2+(i-1)*h,Theme.muted) end
end
function EmberRoutesWorkPriorityDialog:close()
    if self.disposed then return end self.disposed=true
    self.combo:hidePopup() for _,combo in pairs(self.fields) do combo:hidePopup() end
    ISCollapsableWindow.close(self) self:removeFromUIManager()
    if self.owner.priorityDialog==self then self.owner.priorityDialog=nil end
end
return EmberRoutesWorkPriorityDialog
