-- WarehousePageRefresh.lua - EmberRoutes UI
-- Snapshot receive, store projection, query/search state.
-- Attached to EmberRoutesWarehousePage by WarehousePage.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the page module). Moved verbatim from the
-- pre-split WarehousePage.lua (p1-split-warehousepage); behaviour unchanged.

local Metrics=require "EmberRoutesProbe/Warehouse/WarehouseMetrics"
local Rows=require "EmberRoutesProbe/UI/WarehouseRows"
local Text=require "EmberRoutesProbe/UI/Text"
local Theme=require "EmberRoutesProbe/UI/Theme"

local function text(key) return getText("IGUI_EmberRoutesProbe_Settlement_"..key) end

---@param Page EmberRoutesWarehousePage
local function attach(Page)
    function Page:receive(snapshot)
        if not self.active then return end
        local measured=Metrics.begin("ui.update")
        local copy={state=snapshot.state,counts=snapshot.counts,reason=snapshot.reason,revision=snapshot.revision,retain=snapshot.retain,rows={}}
        copy.rows=Rows.project(snapshot,self.store.value.snapshot.rows,function(fullType)
            local label=self.itemNames[fullType]
            if not label then
                local resolve=_G.getItemNameFromFullType
                label=type(resolve)=="function" and resolve(fullType) or fullType
                if not label or label=="" then label=fullType end
                self.itemNames[fullType]=label
            end
            return label
        end)
        if not self.resume and self.itemGrid and snapshot.state=='UPDATING' and not snapshot.retain then
            local selection=self.store.value.selection
            self.resume={fullType=selection and selection.fullType,page=self.actualPage,
                gridScroll=self.itemGrid.scrollY}
        end
        local restore=self.resume and snapshot.state=="READY"
        local selection=self.store.value.selection
        if restore then
            self.actualPage=self.resume.page
            selection=false
            for _,row in ipairs(copy.rows) do
                if row.fullType==self.resume.fullType then selection=row break end
            end
        end
        self.pinnedItems=self.pinnedItems or {}
        for _,r in ipairs(copy.rows) do
            if self.pinnedItems[r.fullType] then r.pinned=true end
        end
        self.store:setState({snapshot=copy,selection=selection})
        if restore then self.resume=nil end
        Metrics.finish("ui.update",measured)
    end

    function Page:project(snapshot,changed)
        if not self.active then return end
        if changed.snapshot then
            local s=snapshot.snapshot
            local c=s.counts or {}
            local capRatio=c.usedWeight and c.totalCapacity and c.totalCapacity>0 and c.usedWeight/c.totalCapacity or nil
            if s.state=="READY" then
                self.summary:setValues({loaded=c.loaded.."/"..c.containers,unloaded=c.unloaded,private=c.private,
                    missing=c.missing,limited=c.limited,items=c.items}, s.rows and #s.rows or nil)
                self.summary:setCoverage(c.usedWeight or c.loaded,c.totalCapacity or c.containers)
            elseif s.state~="UPDATING" or not s.retain then self.summary:setValues(nil) self.summary:setCoverage(nil,nil) end
            local note=""
            if s.state=="ERROR" and s.reason then note=text(s.reason)
            elseif s.state=="READY" and c and (c.fullCount or capRatio) then
                if c.fullCount and c.fullCount>0 then note="^ "..c.fullCount.." "..text("limited")
                elseif capRatio then note=text(capRatio>0.8 and "capacityWarning" or "capacityAdequate").." ("..math.floor(capRatio*100).."%)" end
            end
            self.summary:setStatus(s.state,note)
        end
        if not self.syncingPage and (changed.snapshot or changed.search or changed.category or changed.sort or changed.page) then
            local explicit=changed.search or changed.category or changed.sort or changed.page
            if explicit then
                if self.itemGrid then self.itemGrid.scrollY=0 end
            end
            local measured=Metrics.begin("ui.query")
            local rows,_,_,total=self.query:all(snapshot.snapshot.rows,snapshot.search,snapshot.category,snapshot.sort)
            Metrics.finish("ui.query",measured)
            local allCount=#(snapshot.snapshot.rows or {})
            local isFiltered=(snapshot.search~="" or snapshot.category~=false)
            self.badgeStats={matched=total,total=allCount,isFiltered=isFiltered}
            if self.controls.clear then Theme.enable(self.controls.clear,snapshot.search~="") end
            if self.notice~="" then self.hintLines=Text.wrapLimited(text("shortHint"),self.width-self.pad*2,UIFont.Small,1) end
            self.notice=""

            local selection=nil
            if self.resume and snapshot.snapshot.state=="READY" then
                for _,row in ipairs(rows) do
                    if row.fullType==self.resume.fullType then
                        selection=row
                        break
                    end
                end
            end
            if not selection and snapshot.selection then
                for _,row in ipairs(rows) do
                    if row.fullType==snapshot.selection.fullType then
                        selection=row
                        break
                    end
                end
            end
            if not selection and #rows>0 then
                selection=rows[1]
            end

            if self.itemGrid then
                self.itemGrid:setRows(rows,selection)
                if self.resume and snapshot.snapshot.state=='READY' then
                    self.itemGrid.scrollY=math.max(0,math.min(self.resume.gridScroll or 0,self.itemGrid.maxScrollY))
                end
                local gridEmpty=snapshot.snapshot.state=="UPDATING" and "waitingItems" or "noItems"
                self.itemGrid.emptyLabel=snapshot.snapshot.state=="ERROR" and text(snapshot.snapshot.reason or "ERROR") or text(gridEmpty)
            end
            self.syncingPage=true self.store:setState({page=snapshot.page or 1,selection=selection}) self.syncingPage=false
            if #rows==0 then self.details:setItem(nil) end
        end
        if changed.selection then
            self.details:setItem(snapshot.selection or nil)
        end
    end

    function Page:queryChanged()
        if not self.active or not self.itemGrid then return end
        self.resume=nil
        self.store:setState({search=self.search:getText(),category=self.categories:getSelectedData() or false,page=1,
            sort=self.controls.sort:getSelectedData() or "default"})
    end

    function Page:clearSearch() self.search:setText("") self:queryChanged() end
end

return attach
