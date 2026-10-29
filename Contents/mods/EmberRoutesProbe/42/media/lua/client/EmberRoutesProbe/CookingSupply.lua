-- One fixed-recipe batch, read-only. Warehouse permissions/scanning/matching stay shared.
local Craft=require 'EmberRoutesProbe/CookingCraft'
local Inputs=require 'EmberRoutesProbe/CraftRecipeInputs'
local Fluids=require 'EmberRoutesProbe/CraftFluids'
local Food=require 'EmberRoutesProbe/CookingFood'
local Supply=require 'EmberRoutesProbe/ProductionSupply'
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Planner=require 'EmberRoutesProbe/ProductionChainPlan'
local Store=require 'EmberRoutesProbe/LaborStore'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local M={}
local function safe(item)
    if not instanceof(item,'Food') then return true end
    local food=Food.read(item)
    return food and food.safe and not food.frozen or false
end
function M.chain(actor,entry,npc,recipeId,object,orderId,preferences)
    local profile,why=Craft.profile(recipeId) if not profile then return nil,why end
    local spec,reason=Inputs.planning(profile,npc) if not spec then return nil,reason end
    for _,input in ipairs(spec.inputs) do
        local accept=input.accept
        input.accept=function(item) return safe(item) and accept(item) end
    end
    return require('EmberRoutesProbe/ProductionChain').new(actor,npc,entry,recipeId,spec.yield,
        object,'offer:'..orderId,true,preferences,{root=spec,acceptStock=safe})
end
function M.new(entry,npc,recipeId,jobId)
    local profile,why=Craft.profile(recipeId) if not profile then return nil,why end
    local spec,reason=Inputs.planning(profile,npc) if not spec then return nil,reason end
    for _,input in ipairs(spec.inputs) do
        local accept=input.accept
        input.accept=function(item)
            if instanceof(item,'Food') then
                local food=Food.read(item)
                if not food or not food.safe or food.frozen then return false end
            end
            return accept(item)
        end
    end
    local scan,err=Supply.new(entry,npc,spec,{id=jobId,materials={},tools={},outputs={}},true,1)
    if not scan then return nil,err end
    local self={scan=scan,root=Registry.data(),stock={},entries={},index=1}
    function self:cancel() self.cancelled=true self.planner=nil self.scan=nil self.stock={} self.entries={} end
    function self:step(budget)
        if self.cancelled or self.root~=Registry.data() then return nil,'WORLD_RESET' end
        if self.done then return self.result,self.reason end
        if not self.scanned then
            local ready,missing=self.scan:step(budget or 32)
            if missing then
                self.done=true self.reason=self.scan.partial and 'CHAIN_INVENTORY_UNKNOWN' or missing
                return nil,self.reason
            end
            if ready then self.scanned=true end
            return
        end
        if not self.planner then
            -- One original per operation. Selection may have gone stale since the scan.
            for _=1,budget or 32 do
                local demand=self.scan.demands[self.index]
                if not demand then
                    self.planner=Planner.new(spec,spec.yield,self.stock,{}) break
                end
                local candidate=demand.candidate local item=candidate.item local id=item:getID()
                local endpoint=candidate.endpoint
                if item:getContainer()~=(endpoint and endpoint.container or npc:getInventory())
                    or endpoint and not Registry.revalidate(endpoint,'take','local-world') then
                    self.done=true self.reason='ITEM_LOCATION_CHANGED' return nil,self.reason
                end
                local owner=Store.owner(id)
                if owner and owner.taskId~=jobId or not Producers.eligible(item) or item:getIsCraftingConsumed() then
                    self.done=true self.reason='INPUT_CHANGED' return nil,self.reason
                end
                if not demand.input.accept(item) then self.done=true self.reason='INPUT_CHANGED' return nil,self.reason end
                local amount
                if demand.input.fluid then
                    local snapshot,readWhy=Fluids.read(item:getFluidContainer())
                    if not snapshot then self.done=true self.reason=readWhy return nil,readWhy end
                    amount=snapshot.amount
                end
                self.stock[#self.stock+1]={id=id,fullType=item:getFullType(),item=item,fluidAmount=amount,npcOnly=candidate.npcOnly}
                self.entries[#self.entries+1]={id=id,slot=demand.input.slot,item=item,endpoint=endpoint}
                self.index=self.index+1
            end
            return
        end
        local plan,missing=self.planner:step(budget or 32)
        if plan or missing then
            self.done=true self.reason=missing
            if plan then self.result={plan=plan,entries=self.entries,profile=profile} end
            return self.result,self.reason
        end
    end
    return self
end
return M
