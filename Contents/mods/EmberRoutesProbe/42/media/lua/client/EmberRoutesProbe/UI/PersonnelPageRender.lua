-- PersonnelPageRender.lua - EmberRoutes UI
-- Frame rendering and tick: column header + bottom notice in prerender,
-- 5s refresh cadence in update. Attached to EmberRoutesPersonnelPage by
-- PersonnelPage.lua (mixin pattern: this module receives the class table,
-- so there is no circular require back to the page module). Moved verbatim
-- from PersonnelPage.lua; behaviour unchanged.

local C = require 'EmberRoutesProbe/UI/PersonnelPageConstants'
local Theme = require 'EmberRoutesProbe/UI/Theme'

local function attach(Page)
function Page:prerender()
    ISPanel.prerender(self)
    local h,p=self.fontHeight,self.pad

    -- Column 1 header (Worker Name)
    if self.colHeaders and self.colHeaders[1] then
        Theme.text(self,C.text('worker'),self.colHeaders[1].x+p/2,self.colHeaders[1].y+(self.colHeaders[1].height-h)/2,Theme.textColor)
    end

    -- Bottom notice
    local notice=self.store.value.notice or ''
    if notice~='' and self.bottomNoticeBounds then
        Theme.text(self,self.noticeLine or '',self.bottomNoticeBounds.x,self.bottomNoticeBounds.y,Theme.accent)
    end
end

function Page:update()
    ISPanel.update(self)
    if not self.active or self.disposed then return end
    local now=getTimestampMs()
    if not self.nextSyncCheck or now>self.nextSyncCheck then
        self.nextSyncCheck=now+5000
        self:refresh()
    end
end

end

return attach
