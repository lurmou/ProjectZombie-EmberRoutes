-- PersonnelPageInteraction.lua - EmberRoutes UI
-- List interaction: keyboard focus/activation, member context menu,
-- dossier drawer toggle, close and joypad focus. Attached to
-- EmberRoutesPersonnelPage by PersonnelPage.lua (mixin pattern: this module
-- receives the class table, so there is no circular require back to the
-- page module). Moved verbatim from PersonnelPage.lua; behaviour unchanged.

require 'ISUI/ISContextMenu'
local C = require 'EmberRoutesProbe/UI/PersonnelPageConstants'
local Layout = require 'EmberRoutesProbe/UI/Layout'
local DossierDrawer = require 'EmberRoutesProbe/UI/PersonnelDossierDrawer'

---@param Page EmberRoutesPersonnelPage
local function attach(Page)
function Page:onListFocus(_,direction)
    self.editCategory=direction<0 and 'crafting' or 'hauling'
    self.store:setState({notice=C.text('editHint',C.text(self.editCategory))})
end

function Page:toggleDossierDrawer(forceState)
    local newState=(forceState~=nil) and forceState or not self.dossierDrawerOpen
    self.dossierDrawerOpen=newState
    local sel=self.store.value.selected
    if newState and sel then
        local dash=self.owner
        local w=math.min(380,math.max(320,math.floor(dash.width*0.35)))
        local x,y,drawerW,drawerH=Layout.dockDrawer(dash,w,8)
        if not self.dossierDrawer then
            self.dossierDrawer=DossierDrawer:new(self,x,y,drawerW,drawerH)
            self.dossierDrawer:addToUIManager()
        else
            self.dossierDrawer:setX(x)
            self.dossierDrawer:setY(y)
            self.dossierDrawer:setWidth(drawerW)
            self.dossierDrawer:setHeight(drawerH)
            if not self.dossierDrawer:isVisible() then
                self.dossierDrawer:addToUIManager()
            end
        end
        self.dossierDrawer:setVisible(true)
        self.dossierDrawer:bringToTop()
        self.dossierDrawer:setWorker(sel)
    else
        if self.dossierDrawer then
            self.dossierDrawer:close()
        end
    end
end

function Page:onListKey(key)
    if key==Keyboard.KEY_RETURN then self:onListActivate()
    elseif key==Keyboard.KEY_LEFT or key==Keyboard.KEY_RIGHT then self:onListFocus(nil,key==Keyboard.KEY_LEFT and -1 or 1) end
end

function Page:onListActivate()
    local worker=self.store.value.selected if not worker then return end
    local category=self.editCategory or 'crafting'
    if not self.active or not self.activationScope or not self.activationScope:isCurrent() then return end
    if self.memberMenu then self.memberMenu:release() self.memberMenu=nil end
    local menu=ISContextMenu.get(self.actor:getIndex(),self:getAbsoluteX(),self:getAbsoluteY())
    self.memberMenu=self.activationScope:own(menu,function(value) value:hideSelfAndChildren2() end)
    local activation=self.activation
    local function guard() return self.active and not self.disposed and self.activation==activation and self.owner:valid() end
    local members=require 'EmberRoutesProbe/Integration/MembershipMenu'
    members.posting(self.actor,menu,worker.id,guard)
    members.batch(self.actor,menu,self.entry.id,self.store.value.workers,guard,function(results)
        if not guard() then return end
        self.batchResults=results self:refresh()
    end)
    for value=0,4 do menu:addOption(C.text(category)..': '..C.pubText('priority_'..value),self,function()
        if not guard() then return end
        local result=self:setWorkerPriority(worker,category,value)
        self.store:setState({notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)}) self:refresh()
    end) end
end

function Page:close() if self.dossierDrawer then self.dossierDrawer:close() end self.owner:close() end

function Page:focusContent()
    if self.actor:getJoypadBind()~=-1 then setJoypadFocus(self.actor:getIndex(),self.matrixList) end
end

end

return attach
