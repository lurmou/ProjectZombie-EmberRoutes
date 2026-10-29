-- Bounded item matching; physical endpoints and target ranking remain the existing warehouse policy.
local Supply=require "EmberRoutesProbe/CraftSupply"
local Membership=require "EmberRoutesProbe/SettlementMembership"
local Sort=require "EmberRoutesProbe/SortPolicy"
local Filter=require "EmberRoutesProbe/StorageFilter"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Store=require "EmberRoutesProbe/LaborStore"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Plan={}
function Plan.new(entry,npc,spec,record,select,units)
    local ids,why=Membership.query(entry) if not ids then return nil,why end
    local self={entry=entry,npc=npc,spec=spec,ids=ids,index=Sort.index(),locations={},position=1,phase="TARGETS",read=0,
        wanted={},demands={},select=select,matched=0}
    for _,name in ipairs({"materials","tools","outputs","held"}) do for _,asset in ipairs(record[name] or {}) do self.wanted[asset.id]=true end end
    if select then
        local pinned={}
        for _,tool in ipairs(record.tools) do
            pinned[tool.slot]=pinned[tool.slot] or {} table.insert(pinned[tool.slot],tool.id)
        end
        for _,input in ipairs(spec.inputs) do
            local count=input.count*(input.keep and 1 or units or 1)
            if units and #self.demands+count>256 then return nil,"PREVIEW_LIMIT" end
            for i=1,count do
                self.demands[#self.demands+1]={input=input,pinned=pinned[input.slot] and pinned[input.slot][i]}
            end
        end
    end
    function self:counts()
        local result={}
        for _,demand in ipairs(self.demands) do
            local slot=demand.input.slot local row=result[slot] or {required=0,available=0,fullType=false}
            result[slot]=row row.required=row.required+1
            if demand.candidate then row.available=row.available+1 row.fullType=row.fullType or demand.candidate.item:getFullType() end
        end
        return result
    end
    local npcItems=npc:getInventory():getItems()
    if npcItems:size()>512 then return nil,"INVENTORY_LIMIT" end
    self.npcItems=npcItems self.npcSize=npcItems:size() self.npcOffset=0
    -- Explicit augmenting-path stack: one edge or one commit per operation.
    -- No candidate changes until a complete augmenting path has been found.
    local function matchStep()
        local m=self.match local frames=m.frames local frame=frames[#frames]
        if m.commit then
            self.demands[frame.slot].candidate=frame.candidate
            frames[#frames]=nil
            if #frames==0 then self.matched=self.matched+1 self.match=nil end
            return
        end
        local i=frame.index local demand=self.demands[i]
        if not demand then
            frames[#frames]=nil if #frames==0 then self.match=nil end return
        end
        frame.index=i+1
        local candidate=frame.candidate
        if not m.seen[i] and (not candidate.npcOnly or demand.input.keep)
            and (not demand.pinned or demand.pinned==candidate.item:getID())
            and (demand.input.accept and demand.input.accept(candidate.item)
                or not demand.input.accept and demand.input.io:canUseItem(candidate.item,npc)) then
            m.seen[i]=true frame.slot=i
            if not demand.candidate then m.commit=true
            else frames[#frames+1]={candidate=demand.candidate,index=1} end
        end
    end
    local function inspect(item,endpoint)
        local id=item:getID()
        if self.wanted[id] then
            if self.locations[id] then return nil,"ITEM_ID_CONFLICT" end
            self.locations[id]={item=item,endpoint=endpoint}
        end
        if self.select and self.matched<#self.demands and Producers.eligible(item) and not item:getIsCraftingConsumed() then
            local owner=Store.owner(id)
            if (not owner or owner.taskId==record.id) and (not endpoint or
                (Registry.logistics(endpoint)=="STORAGE" and Registry.accepts(endpoint,item))) then
                self.match={frames={{candidate={item=item,endpoint=endpoint,npcOnly=endpoint==nil},index=1}},seen={}}
            end
        end
        return true
    end
    function self:step(budget)
        if self.done then return true end
        for _=1,budget do
            if self.match then matchStep()
            elseif self.finalIndex then
                local demand=self.demands[self.finalIndex]
                if not demand then self.done=true return true end
                local c=demand.candidate
                if not c then return nil,demand.input.keep and not demand.input.fluid and "TOOLS_UNAVAILABLE" or "MATERIALS_UNAVAILABLE" end
                local id=c.item:getID()
                if self.finalUsed[id] then return nil,"ITEM_ID_CONFLICT" end self.finalUsed[id]=true
                local asset={id=id,slot=demand.input.slot,source=c.endpoint and c.endpoint.id}
                table.insert(demand.input.keep and self.tools or self.materials,asset)
                self.locations[id]=c self.finalIndex=self.finalIndex+1
            elseif self.npcOffset<self.npcSize then
                if self.npcItems:size()~=self.npcSize then return nil,"INVENTORY_CHANGED" end
                local item=self.npcItems:get(self.npcOffset) self.npcOffset=self.npcOffset+1
                local ok,reason=inspect(item,nil) if not ok then return nil,reason end
            elseif self.phase=="TARGETS" then
                local id=self.ids[self.position]
                if not id then self.phase="ITEMS" self.position=1
                else
                    self.position=self.position+1 local endpoint=Supply.endpoint(entry,id,"put")
                    if endpoint and Registry.logistics(endpoint)=="STORAGE" then
                        endpoint.filter=Filter.copy(Registry.filter(endpoint.object,endpoint.container)) self.index:add(endpoint)
                    end
                end
            elseif not self.source then
                local id=not (self.select and self.matched==#self.demands) and self.ids[self.position]
                if not id then
                    if self.select then
                        self.materials,self.tools,self.finalUsed={},{},{} self.finalIndex=1
                    else
                        self.done=true return true
                    end
                else
                self.position=self.position+1 local endpoint,why=Supply.endpoint(entry,id,"take")
                if units and why=="CONTAINER_UNLOADED" then self.partial=true end
                if endpoint then
                    if endpoint.container:getItems():size()>2000 then return nil,"SOURCE_SCAN_LIMIT" end
                    self.source=endpoint self.offset=0 self.size=endpoint.container:getItems():size()
                end
                end
            else
                local source=self.source local items=source.container:getItems()
                if not Registry.revalidate(source,"take","local-world") or items:size()~=self.size then return nil,"INVENTORY_CHANGED" end
                if self.offset>=self.size then self.source=nil
                else
                    local item=items:get(self.offset) self.offset=self.offset+1 self.read=self.read+1
                    if self.read>20000 then return nil,"INVENTORY_SCAN_LIMIT" end
                    if item:getContainer()~=source.container then return nil,"ITEM_LOCATION_CHANGED" end
                    local ok,reason=inspect(item,source) if not ok then return nil,reason end
                    if self.select and self.matched==#self.demands then self.source=nil end
                end
            end
        end
        return false
    end
    return self
end
return Plan
