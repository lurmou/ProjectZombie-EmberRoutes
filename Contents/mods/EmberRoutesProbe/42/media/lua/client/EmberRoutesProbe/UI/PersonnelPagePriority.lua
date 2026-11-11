-- PersonnelPagePriority.lua - EmberRoutes UI
-- Worker priority editing: single/batch priority set and cycle, plus the
-- work-command button visibility derived from the selected work row.
-- Attached to EmberRoutesPersonnelPage by PersonnelPage.lua (mixin pattern:
-- this module receives the class table, so there is no circular require
-- back to the page module). Moved verbatim from PersonnelPage.lua;
-- behaviour unchanged.

require 'ISUI/ISContextMenu'
local C = require 'EmberRoutesProbe/UI/PersonnelPageConstants'
local Public = require 'EmberRoutesProbe/Work/PublicWork'

---@param Page EmberRoutesPersonnelPage
local function attach(Page)
function Page:hasWorkCommands()
    if not self.workCommands then return false end
    local caps=(self.currentWork and self.currentWork.row) and require('EmberRoutesProbe/Work/WorkCommandAdapter').capabilities(self.currentWork.row) or {}
    return (caps.stop or caps.resume or caps['return'] or caps.stopBody) == true
end

function Page:syncCommandVisibility()
    if not self.workCommands then return end
    local caps=(self.currentWork and self.currentWork.row) and require('EmberRoutesProbe/Work/WorkCommandAdapter').capabilities(self.currentWork.row) or {}
    for key,button in pairs(self.workCommands) do
        button:setVisible(caps[key]==true)
    end
    if self.pageHost and self.pageHost:isActivationValid() then
        self.pageHost:syncVisibility()
    end
end

function Page:setWorkerPriority(worker,category,value)
    local values={}
    for _,key in ipairs(self.workCategories) do
        values[key]=(worker.priorities and worker.priorities[key]) or 3
    end
    values[category]=value
    local rev=(worker.priorities and worker.priorities.revision) or 0
    return Public.setPriorities(self.actor,self.entry.id,worker.id,values,rev)
end

function Page:cycleWorkerPriority(worker,category,delta)
    if not self.active or not self.owner:valid() then return end
    self.store:setState({selected=worker})
    local result=self:setWorkerPriority(worker,category,((worker.priorities[category] or 3)+(delta or 1))%5)
    self.store:setState({notice=require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)})
    self:refresh()
end

function Page:batchCycle(category)
    if not self.active or not self.activationScope or not self.activationScope:isCurrent() then return end
    local menu=ISContextMenu.get(self.actor:getIndex(),self.colHeaders[2].x+self:getAbsoluteX(),self.headerBounds.y+self:getAbsoluteY())
    self.activationScope:own(menu,function(m) m:hideSelfAndChildren2() end)
    for value=0,4 do
        menu:addOption(C.text('setAll',C.pubText(category),C.pubText('priority_'..value)),self,function()
            if not self.active or self.disposed or not self.owner:valid() then return end
            local ok,failed=0,{}
            for _,worker in ipairs(self.store.value.workers or {}) do
                local result=self:setWorkerPriority(worker,category,value)
                if result=='PRIORITY_SAVED' then ok=ok+1 else
                    failed[#failed+1]=worker.name..': '..require('EmberRoutesProbe/UI/OrderMonitorCards').reason(result)
                end
            end
            self.store:setState({notice=C.text('batchResult',ok,#failed)..(#failed>0 and (' | '..table.concat(failed,'; ')) or '')})
            self:refresh()
        end)
    end
end

end

return attach
