-- PersonnelPageRefresh.lua - EmberRoutes UI
-- Data refresh and projection: enrich workers, build work lines, keep the
-- selection, and project store state into the matrix list and the detail
-- inspector. Attached to EmberRoutesPersonnelPage by PersonnelPage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from
-- PersonnelPage.lua; behaviour unchanged.

local C = require 'EmberRoutesProbe/UI/PersonnelPageConstants'
local Cached = require 'EmberRoutesProbe/UI/CachedList'
local Theme = require 'EmberRoutesProbe/UI/Theme'
local Text = require 'EmberRoutesProbe/UI/Text'
local Crafting = require 'EmberRoutesProbe/Crafting/CraftingService'

local function attach(Page)
function Page:refresh()
    if not self.active or self.disposed then return end
    local status=Crafting.status(self.actor,self.entry.id)
    local rawWorkers=status.workers or {}
    local enriched=require('EmberRoutesProbe/Settlement/PersonnelService').enrichWorkers(self.actor,self.entry.id,rawWorkers)
    self.overview=require('EmberRoutesProbe/Work/WorkOverviewService').status(self.actor,self.entry.id)
    for _,w in ipairs(enriched) do
        local work=self.overview.byNpc[w.id]
        local state=work and work.state or 'idle'
        local title=work and work.title or ''
        if not work then
            local idle=require('EmberRoutesProbe/Leisure/LeisureService').status(w.id)
            title=idle and idle.reason and (getTextOrNull('IGUI_EmberRoutesProbe_Leisure_'..idle.reason) or '') or ''
        end
        w.workLine=title..' | '..getText('IGUI_EmberRoutesProbe_Distributed_'..state)
    end
    local selected=self.store.value.selected
    if selected then
        local found=false
        for _,w in ipairs(enriched) do
            if w.id==selected.id then selected=w found=true break end
        end
        if not found then selected=false end
    elseif not self.selectionInitialized then
        selected=enriched[1] or false
    end
    self.selectionInitialized=true
    local batchLines=require('EmberRoutesProbe/Integration/MembershipMenu').batchLines(self.batchResults)
    self.store:setState({workers=enriched,selected=selected,batchLines=batchLines,revision=self.store.value.revision+1})
end

function Page:project(value)
    if not self.active or self.disposed or not self.matrixList or not self.info then return end
    local rows={}
    for _,w in ipairs(value.workers or {}) do
        if require('EmberRoutesProbe/Work/WorkOverviewPresenter').visible(self.overview.byNpc[w.id],self.workFilter) then rows[#rows+1]=w end
    end
    local noticeW=self.bottomNoticeBounds and self.bottomNoticeBounds.width or (self.width or 400)
    self.noticeLine=Text.wrapLimited(value.notice or '',noticeW,UIFont.Small,1)[1] or ''
    local sel=value.selected
    local Personnel=require 'EmberRoutesProbe/Settlement/PersonnelService'
    if self.detailNpc~=(sel and sel.id) then
        Personnel.release(self.detailNpc) self.detailNpc=sel and sel.id self.knowledgePage=1
    end

    -- 2. Prepare Colonist Inspector detail items for self.info
    local detail={}
    if sel then
        local work=self.overview.byNpc[sel.id]
        detail[#detail+1]={text=sel.name,color=Theme.accent}
        if work then
            for _,line in ipairs(require('EmberRoutesProbe/UI/OrderMonitorCards').detailRows(work.row,false)) do detail[#detail+1]=line end
        else
            detail[#detail+1]={text=sel.workLine or '',color=Theme.muted}
        end
        self.currentWork=work
        local caps=require('EmberRoutesProbe/Work/WorkCommandAdapter').capabilities(work and work.row)
        for key,button in pairs(self.workCommands or {}) do button:setVisible(caps[key]==true) end
        if sel.isBleeding or sel.isInfected or sel.hasInjury then
            detail[#detail+1]={text=getText('IGUI_EmberRoutesProbe_Layout_injury'),color=Theme.status.ERROR}
        end

    else
        self.currentWork=nil
        for _,button in pairs(self.workCommands or {}) do button:setVisible(false) end
        detail[#detail+1]={text=C.text('noWorkers'),color=Theme.muted}
    end
    if sel then
        local extra=require('EmberRoutesProbe/UI/PersonnelPresentation').rows(Personnel.details(self.actor,self.entry.id,sel.id),self.detailMode,self.knowledgePage)
        if self.detailMode=='skills' or self.detailMode=='knowledge' then detail={} end
        for _,row in ipairs(extra) do detail[#detail+1]=row end
    end
    for _,line in ipairs(value.batchLines or {}) do detail[#detail+1]=line end
    self.info:set(detail)
    if self.dossierDrawer and self.dossierDrawerOpen then
        self.dossierDrawer:setWorker(sel)
    end

    -- 3. Reconcile matrix list
    local signature=function(w)
        local p=w.priorities or {}
        local prioParts={}
        for _,cat in ipairs(self.workCategories) do
            prioParts[#prioParts+1]=cat..'='..(p[cat] or 0)
        end
        return (w.workLine or '')..'|'..w.id..'|'..w.name..'|'..(w.busy and '1' or '0')..'|'..(p.revision or 0)..'|'..table.concat(prioParts,',')
    end
    Cached.reconcile(self.matrixList,rows,signature,function(w) return w.id end,true)
end

end

return attach
