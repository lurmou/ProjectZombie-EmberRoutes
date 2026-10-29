-- One bounded scan per scope, using existing permission and invalidation services.
-- A partial/changed scan is never published as confirmed zero food.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Members=require 'EmberRoutesProbe/SettlementMembership'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local Read=require 'EmberRoutesProbe/InventoryRead'
local Food=require 'EmberRoutesProbe/CookingFood'
local Facilities=require 'EmberRoutesProbe/CookingFacilities'
local Store=require 'EmberRoutesProbe/LaborStore'
local M={}
function M.new(entry,clock)
    local ids,why=Members.query(entry) if not ids then return nil,why end
    local s={entry=entry,world=Registry.data(),watch=Wake.capture(entry),ids=ids,index=1,
        seen={},amount=0,items=0,readyByType={},typeCount=0,done=false,unknown=false,clock=clock}
    local function valid()
        return Registry.data()==s.world and not Wake.changed(s.watch)
    end
    function s:step(budget)
        if type(budget)~='number' or budget<1 or budget>32 or budget~=math.floor(budget) then return nil,'SCAN_BUDGET_INVALID' end
        if not valid() then return nil,'SUPPLY_CHANGED' end
        if self.done then return true end
        for _=1,budget do
            if self.rows then
                local item,id=self.rows[self.offset],self.rows[self.offset+1]
                if not item then self.rows=nil
                else
                    self.offset=self.offset+3
                    if item:getContainer()~=self.endpoint.container then return nil,'SUPPLY_CHANGED' end
                    if self.seen[id] then return nil,'ITEM_ID_CONFLICT' end
                    self.seen[id]=true
                    if not Store.owner(id) and Registry.accepts(self.endpoint,item) then
                        local row,reason=Food.read(item)
                        if not row then self.unknown=true self.reason=reason
                        else
                            if row.food and row.safe and not row.needsHeat and not row.frozen and not row.requiresTool and row.effective>0 then
                                if not self.readyByType[row.fullType] then
                                    self.typeCount=self.typeCount+1
                                    if self.typeCount>1024 then return nil,'RESOURCE_SCAN_LIMIT' end
                                end
                                self.readyByType[row.fullType]=(self.readyByType[row.fullType] or 0)+1
                            end
                            if row.ready then self.amount=self.amount+row.effective self.items=self.items+1 end
                        end
                    end
                end
            elseif self.endpoint then
                local e,reason=Registry.revalidate(self.endpoint,'take','local-world')
                if not e then return nil,reason or 'SUPPLY_CHANGED' end
                local cold,reason2=Facilities.cold(e)
                if not cold or not cold.cold then return nil,reason2 or 'COLD_CHANGED' end
                if self.cursor>=self.size then self.endpoint=nil
                else
                    local n=math.min(8,self.size-self.cursor)
                    local rows,reason2=Read.slice(e.container,self.list,self.size,self.cursor,n)
                    if not rows then return nil,reason2 end
                    self.rows,self.offset,self.cursor=rows,1,self.cursor+n
                end
            else
                local id=self.ids[self.index]
                if not id then self.done=true return true end
                self.index=self.index+1
                local e,reason=Registry.resolve(id,'take','local-world')
                if not e then
                    if reason~='CONTAINER_PRIVATE' and reason~='CONTAINER_REMOVED' then
                        self.unknown=true self.reason=reason or 'SUPPLY_UNKNOWN'
                    end
                elseif Registry.logistics(e)=='STORAGE' then
                    local cold,reason2=Facilities.cold(e)
                    if not cold then self.unknown=true self.reason=reason2
                    elseif cold.cold then
                        self.endpoint=e self.list=e.container:getItems() self.size=self.list:size() self.cursor=0
                        if self.size>2000 then return nil,'RESOURCE_SCAN_LIMIT' end
                    end
                end
            end
        end
        return false
    end
    function s:result()
        if not self.done or not valid() then return nil,'SUPPLY_NOT_OBSERVED' end
        if self.unknown then return {scopeId=entry.id,complete=false,reason=self.reason or 'SUPPLY_UNKNOWN'} end
        return {scopeId=entry.id,complete=true,ready=self.amount,items=self.items,readyByType=self.readyByType,
            observedAt=self.clock and self.clock() or nil}
    end
    return s
end
return M
