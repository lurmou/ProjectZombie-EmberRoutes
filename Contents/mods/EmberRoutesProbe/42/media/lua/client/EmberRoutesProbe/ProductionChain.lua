-- Native metadata and physical inventory adapter for the pure dependency planner.
local Recipe=require "EmberRoutesProbe/ProductionRecipe"
local Planner=require "EmberRoutesProbe/ProductionChainPlan"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Membership=require "EmberRoutesProbe/SettlementMembership"
local Supply=require "EmberRoutesProbe/CraftSupply"
local Store=require "EmberRoutesProbe/LaborStore"
local Producers=require "EmberRoutesProbe/LaborProducers"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Catalog=require "EmberRoutesProbe/CraftingCatalog"
local Direct=require "EmberRoutesProbe/ProductionSupply"
local Chain={}
function Chain.new(actor,npc,entry,recipeId,quantity,object,taskId,knownMissing,preferences,options)
    local typedRoot=options and options.root
    local self={root=Registry.data(),stock={},actor=actor,npc=npc,entry=entry,offset=0,read=0,seen={},cache={},needsChain=knownMissing==true or typedRoot~=nil,preferences=preferences}
    function self:cancel() self.cancelled=true self.planner=nil self.stock={} self.source=nil end
    local function resolve(spec)
        -- A capability-checked cooking root supplies typed composite slots.
        -- Child producers still pass the unchanged ordinary execution gate.
        if typedRoot and spec.id==typedRoot.id then return typedRoot end
        if self.cache[spec.id] then return self.cache[spec.id] end
        local surface=spec.surface and object or nil
        if spec.surface and not surface then
            for _,location in ipairs(Surfaces.list(entry)) do
                local candidate=Surfaces.resolve(location,location.id)
                if candidate and (not candidate:getUsingPlayer() or candidate:getUsingPlayer()==npc) then surface=candidate break end
            end
        end
        local checked,why=Recipe.inspect(actor,npc,surface,spec.id,true,false)
        if checked then local valid,reason=Supply.entry(actor,npc,surface,entry.id) if not valid then checked=nil why=reason end end
        local r={id=spec.id,name=spec.name,signature=spec.signature,product=spec.product,yield=spec.yield,
            outputs=spec.outputs,surface=spec.surface,inputs={},reason=not checked and why or nil}
        if surface then
            local data=surface:getModData()
            -- Read-only planning never allocates a new surface identity.
            r.benchId=data.EmberRoutesCraftProbeBenchId r.location=Surfaces.location(surface)
        end
        for _,input in ipairs(spec.inputs) do
            local row={slot=input.slot,count=input.count,keep=input.keep,types={},choices={}}
            local io=input.io local possible=io:getPossibleInputItems()
            for i=0,possible:size()-1 do
                local kind=possible:get(i):getFullName()
                if not row.types[kind] then row.types[kind]=true row.choices[#row.choices+1]=kind end
            end
            row.accept=function(item) return io:canUseItem(item,npc) end
            r.inputs[#r.inputs+1]=row
        end
        self.cache[spec.id]=r return r
    end
    function self:step(budget)
        budget=budget or 32
        if self.cancelled then return nil,"WORLD_RESET" end
        if self.root~=Registry.data() then self:cancel() return nil,"WORLD_RESET" end
        if self.done then return self.result,self.reason end
        -- Common single-recipe orders need no complete catalogue or dependency inventory scan.
        if not self.needsChain then
            if not self.direct then
                local spec,why=Recipe.read(recipeId)
                if not spec then self.done=true self.reason=why return nil,why end
                self.directRecipe=spec
                self.directSpec=resolve(spec)
                if self.directSpec.reason then self.done=true self.reason=self.directSpec.reason return nil,self.reason end
                self.direct,why=Direct.new(entry,npc,spec,{id=taskId,materials={},tools={},outputs={}},true,math.ceil(quantity/spec.yield))
                if not self.direct then self.done=true self.reason=why return nil,why end
            end
            local ready,why=self.direct:step(budget)
            if ready then
                if not require('EmberRoutesProbe/ProductionCarry').plan(npc,self.directRecipe,self.direct) then
                    self.done=true self.reason='CAPACITY_UNAVAILABLE' return nil,self.reason
                end
                local r=self.directSpec local target=math.ceil(quantity/r.yield)*r.yield
                if target>9999 then self.done=true self.reason="CHAIN_PLAN_LIMIT" return nil,self.reason end
                local assets={}
                for _,name in ipairs({"materials","tools"}) do
                    for _,asset in ipairs(self.direct[name]) do
                        local item=self.direct.locations[asset.id].item
                        assets[#assets+1]={id=asset.id,fullType=item:getFullType()}
                    end
                end
                self.done=true self.result={assets=assets,nodes={{recipeId=r.id,signature=r.signature,product=r.product,
                    recipeName=r.name,requested=target,unitYield=r.yield,surface=r.surface,benchId=r.benchId,location=r.location}}}
                return self.result
            elseif why=="MATERIALS_UNAVAILABLE" or why=="TOOLS_UNAVAILABLE" then self.needsChain=true self.direct=nil return
            elseif why then self.done=true self.reason=why return nil,why
            else return end
        end
        Catalog.step()
        local byId,index,finished=Catalog.productionIndex()
        if not finished then return end
        if not self.ids then
            local ids,why=Membership.query(entry)
            if not ids then self.done=true self.reason=why return nil,why end
            self.ids=ids self.position=0 self.source={container=npc:getInventory(),npcOnly=true}
            self.size=self.source.container:getItems():size()
            if self.size>512 then self.done=true self.reason="INVENTORY_LIMIT" return nil,self.reason end
        end
        if not self.scanned then
            for _=1,budget do
                local container=self.source and self.source.container
                if container then
                    local items=container:getItems()
                    if items:size()~=self.size then self.done=true self.reason="INVENTORY_CHANGED" return nil,self.reason end
                    if self.source.endpoint and not Registry.revalidate(self.source.endpoint,"take","local-world") then
                        self.done=true self.reason="CONTAINER_CHANGED" return nil,self.reason
                    end
                    if self.offset>=self.size then self.source=nil
                    else
                        local item=items:get(self.offset) self.offset=self.offset+1 self.read=self.read+1
                        if self.read>20000 then self.done=true self.reason="INVENTORY_SCAN_LIMIT" return nil,self.reason end
                        local id=item:getID() local owner=Store.owner(id)
                        if item:getContainer()~=container or self.seen[id] then self.done=true self.reason="ITEM_ID_CONFLICT" return nil,self.reason end
                        self.seen[id]=true
                        if Producers.eligible(item) and not item:getIsCraftingConsumed() and (not owner or owner.taskId==taskId)
                            and (self.source.npcOnly or Registry.accepts(self.source.endpoint,item))
                            and (not options or not options.acceptStock or options.acceptStock(item)) then
                            local amount
                            if typedRoot and item.getFluidContainer and item:getFluidContainer() then
                                local snapshot,why=require('EmberRoutesProbe/CraftFluids').read(item:getFluidContainer())
                                if not snapshot then self.done=true self.reason=why return nil,why end
                                amount=snapshot.amount
                            end
                            self.stock[#self.stock+1]={id=id,item=item,fullType=item:getFullType(),npcOnly=self.source.npcOnly,fluidAmount=amount}
                        end
                    end
                else
                    self.position=self.position+1 local id=self.ids[self.position]
                    if not id then self.scanned=true break end
                    local endpoint,why=Supply.endpoint(entry,id,"take")
                    if why=="CONTAINER_UNLOADED" then self.partial=true end
                    if endpoint and Registry.logistics(endpoint)=="STORAGE" then
                        self.size=endpoint.container:getItems():size() self.offset=0
                        if self.size>2000 then self.done=true self.reason="SOURCE_SCAN_LIMIT" return nil,self.reason end
                        self.source={container=endpoint.container,endpoint=endpoint}
                    end
                end
            end
            return -- Inventory and dependency search never spend two slices together.
        end
        if not self.planner then
            local root=typedRoot or byId[recipeId]
            if not root then self.done=true self.reason="RECIPE_UNAVAILABLE" return nil,self.reason end
            self.planner=Planner.new(resolve(root),quantity,self.stock,index,resolve,self.preferences)
        end
        local result,reason=self.planner:step(budget)
        if result or reason then
            self.done=true self.result=result self.reason=self.partial and reason and "CHAIN_INVENTORY_UNKNOWN" or reason
            self.missing=self.planner.missing
            local failure=self.planner.failure
            if failure and failure.recipeId then self.blocker={recipeId=failure.recipeId,recipeName=failure.recipeName,surfaceId=failure.surfaceId} end
            return result,self.reason
        end
    end
    return self
end
return Chain
