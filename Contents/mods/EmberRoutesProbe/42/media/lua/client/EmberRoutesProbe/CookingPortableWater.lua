-- Incremental discovery of actual portable clean-water originals. No liquid
-- pooling is offered to fixed recipes: this adapter only supplies a cooking pot.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Read=require 'EmberRoutesProbe/InventoryRead'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Carry=require 'EmberRoutesProbe/ProductionCarry'
local P={}
local function safe(item)
    if not instanceof(item,'Food') then return true end
    local food=require('EmberRoutesProbe/CookingFood').read(item)
    return food and food.safe and not food.frozen or false
end
function P.new(c,targetId)
    local ids,why=Membership.query(c.entry) if not ids then return nil,why end
    local root=Registry.data()
    local q={position=1,offset=0,read=0,tried={},container=c.npc:getInventory()}
    q.size=q.container:getItems():size()
    if q.size>512 then return nil,'INVENTORY_LIMIT' end
    function q:skip(row) self.tried[row.id]=row.amount self.position=0 self.container=nil self.rows=nil end
    function q:step(budget)
        if Registry.data()~=root then return nil,'WORLD_RESET' end
        for _=1,math.min(budget or 16,32) do
            if self.rows then
                local item=self.rows[self.row]
                if not item then self.rows=nil
                else
                    self.row=self.row+3
                    local id=item:getID()
                    if item:getContainer()~=self.container then return nil,'INPUT_CHANGED' end
                    if id~=targetId and not Store.owner(id) and Producers.eligible(item) and safe(item)
                        and not item:getIsCraftingConsumed() and (not self.endpoint or Registry.accepts(self.endpoint,item)) then
                        local fluid=item.getFluidContainer and item:getFluidContainer()
                        local water=fluid and Fluids.water(fluid)
                        local carry=not self.endpoint or Carry.fits(c.npc,item:getUnequippedWeight())
                        if water and water.amount>.000001 and carry and (not self.tried[id] or water.amount>self.tried[id]+.000001) then
                            return {id=id,item=item,endpoint=self.endpoint,amount=water.amount}
                        end
                    end
                end
            elseif self.container then
                if self.endpoint and not Registry.revalidate(self.endpoint,'take','local-world') then return nil,'SOURCE_ACCESS_CHANGED' end
                if self.offset>=self.size then self.container=nil
                else
                    local list=self.container:getItems() local count=math.min(8,self.size-self.offset)
                    local rows,err=Read.slice(self.container,list,self.size,self.offset,count)
                    if not rows then return nil,err end
                    self.rows=rows self.row=1 self.offset=self.offset+count self.read=self.read+count
                    if self.read>20000 then return nil,'INVENTORY_SCAN_LIMIT' end
                end
            else
                local id=ids[self.position] self.position=self.position+1
                if self.position==1 then
                    self.endpoint=nil self.container=c.npc:getInventory()
                elseif not id then return nil,self.unloaded and 'CONTAINER_UNLOADED' or 'PURE_WATER_UNAVAILABLE'
                else
                    local endpoint,err=Supply.endpoint(c.entry,id,'take')
                    if err=='CONTAINER_UNLOADED' then self.unloaded=true end
                    if endpoint and Registry.logistics(endpoint)=='STORAGE' then self.endpoint=endpoint self.container=endpoint.container end
                end
                if self.container then
                    self.offset=0 self.size=self.container:getItems():size()
                    if self.size>2000 then return nil,'SOURCE_SCAN_LIMIT' end
                end
            end
        end
        return nil,'SITE_OBSERVING'
    end
    return q
end
function P.adopt(c,row)
    if not Context.active(c) or c.job.effects~='KNOWN' or Store.owner(row.id) then return nil,'INPUT_CHANGED' end
    local held=row.item:getContainer()==c.npc:getInventory()
    if not held and (not row.endpoint or row.item:getContainer()~=row.endpoint.container
        or not Registry.revalidate(row.endpoint,'take','local-world') or not Registry.accepts(row.endpoint,row.item)) then return nil,'INPUT_CHANGED' end
    local water=Fluids.water(row.item:getFluidContainer())
    if not water or water.amount<=.000001 or not Producers.eligible(row.item) or not safe(row.item)
        or row.item:getIsCraftingConsumed() then return nil,'PURE_WATER_REQUIRED' end
    if not held and not Carry.fits(c.npc,row.item:getUnequippedWeight()) then return nil,'CAPACITY_UNAVAILABLE' end
    local j=Record.copy(c.job) local inputs=j.payload.liquidInputs or {}
    if #inputs>=8 or #j.payload.assets>=Record.limit or #j.payload.claims>=Record.limit then return nil,'COOKING_ASSET_LIMIT' end
    inputs[#inputs+1]={id=row.id,fullType=row.item:getFullType(),sourceId=not held and row.endpoint.id or nil}
    j.payload.liquidInputs=inputs
    j.payload.assets[#j.payload.assets+1]={id=row.id,fullType=row.item:getFullType(),role='TOOL',custody=held and 'HELD' or 'SOURCE'}
    j.payload.claims[#j.payload.claims+1]='item:'..row.id
    if not Context.publish(c,j) then return nil,c.reason end
    c.items[row.id]=row.item if not held then c.sources[row.id]=row.endpoint end
    return true
end
return P
