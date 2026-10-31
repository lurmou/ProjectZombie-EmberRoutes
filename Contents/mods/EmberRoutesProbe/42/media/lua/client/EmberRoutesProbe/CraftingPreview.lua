-- Read-only demand matching. Never acquires claims, moves actors, or changes orders.
local Recipe=require "EmberRoutesProbe/ProductionRecipe"
local Plan=require "EmberRoutesProbe/ProductionSupply"
local Supply=require "EmberRoutesProbe/CraftSupply"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local Ledger=require "EmberRoutesProbe/SettlementLedger"
local Driver=require "EmberRoutesProbe/Driver"
local Work=require "EmberRoutesProbe/Work"
local Craft=require "EmberRoutesProbe/CraftProbe"
local Surfaces=require "EmberRoutesProbe/CraftSurfaces"
local Preview={}
function Preview.new(actor,id,npcId,recipeId,quantity,surfaceId,preferences)
    local request={root=Registry.data(),actor=actor,entryId=id,npcId=npcId,recipeId=recipeId,quantity=quantity,surfaceId=surfaceId,preferences=preferences,
        result={state="CHECKING",conditions={},counts={},skills={}}}
    function request:cancel() self.cancelled=true self.plan=nil if self.chain then self.chain:cancel() end end
    function request:step()
        if self.cancelled then return end
        if self.root~=Registry.data() or not Ledger.view(actor,id) then self:cancel() return end
        if self.finished then return self.result end
        local r=self.result
        if self.chain then
            if not self.isSettlementPreview and not Driver.valid(self.binding) then
                self.chain:cancel() self.chain=nil r.conditions[#r.conditions+1]="CARRIER_UNAVAILABLE"
                r.state="BLOCKED" self.finished=true return r
            end
            local plan,why=self.chain:step()
            if plan or why then
                if plan then
                    r.chain={nodes=plan.nodes} r.state=#r.conditions==0 and "READY" or "BLOCKED"
                else
                    r.blocker=self.chain.blocker
                    r.conditions[#r.conditions+1]=why r.state=(why=="CHAIN_INVENTORY_UNKNOWN" or why=="CHAIN_PLAN_LIMIT") and "UNKNOWN" or "BLOCKED"
                end
                self.finished=true self.chain=nil return r
            end
            return
        end
        if not self.started then
            self.started=true
            local function condition(code) r.conditions[#r.conditions+1]=code end
            local spec,why=Recipe.read(recipeId)
            if not spec then condition(why) r.state="BLOCKED" self.finished=true return r end
            if type(quantity)~="number" or quantity~=math.floor(quantity) or quantity<1 or quantity>9999 then
                condition("INVALID_QUANTITY") r.state="BLOCKED" self.finished=true return r
            end
            r.units=math.ceil(quantity/spec.yield) r.target=r.units*spec.yield
            local isSettlementPreview = (npcId==nil or npcId==false)
            local binding=not isSettlementPreview and type(npcId)=="string" and Driver.bindId(actor,npcId) or nil
            if not isSettlementPreview and not binding then condition("NO_WORKER") r.state="BLOCKED" self.finished=true return r end
            local npc=binding and binding.handle or actor
            self.binding=binding
            self.isSettlementPreview=isSettlementPreview
            if not isSettlementPreview then
                if npc:isDead() or npc:getBodyDamage():getOverallBodyHealth()<95 then condition("INJURED") end
                if not npc:isRecipeKnown(spec.recipe,true) then condition("NPC_RECIPE_UNKNOWN") end
            end
            if not actor:isRecipeKnown(spec.recipe,true) then condition("PLAYER_RECIPE_UNKNOWN") end
            for i=0,spec.recipe:getRequiredSkillCount()-1 do
                local skill=spec.recipe:getRequiredSkill(i)
                local perk=skill:getPerk()
                local level=npc and npc.getPerkLevel and npc:getPerkLevel(perk) or 0
                r.skills[#r.skills+1]={name=perk:getName(),current=level,required=skill:getLevel()}
                if not isSettlementPreview and level<skill:getLevel() then condition("NPC_SKILL_TOO_LOW") end
            end
            if not isSettlementPreview then
                local order=Craft.status(npcId)
                if Work.busy(npcId) or order and not order.released then condition("OTHER_TASK_RETAINED") end
            end
            local object
            if spec.surface then
                object,why=Surfaces.resolve((self.root.craftSurfaces or {})[surfaceId],surfaceId)
                if not object then condition(why or "CRAFT_SURFACE_REQUIRED")
                elseif not isSettlementPreview and object:getUsingPlayer() and object:getUsingPlayer()~=npc then condition("BENCH_OCCUPIED") end
            end
            local entry,reason=Supply.entry(actor,npc,object,id)
            if not entry then condition(reason) r.state="BLOCKED" self.finished=true return r end
            self.plan,reason=Plan.new(entry,npc,spec,{id="preview",materials={},tools={},outputs={}},true,r.units)
            self.entry=entry self.object=object
            if not self.plan then condition(reason) r.state="UNKNOWN" self.finished=true return r end
        end
        if not self.isSettlementPreview and not Driver.valid(self.binding) then
            r.conditions[#r.conditions+1]="CARRIER_UNAVAILABLE" r.state="BLOCKED" self.finished=true self.plan=nil return r
        end
        local ready,reason=self.plan:step(32)
        if ready or reason then
            r.counts=self.plan:counts()
            r.partial=self.plan.partial==true
            if reason=="MATERIALS_UNAVAILABLE" or reason=="TOOLS_UNAVAILABLE" then
                if r.partial then
                    r.conditions[#r.conditions+1]=reason r.state="UNKNOWN" self.finished=true self.plan=nil return r
                end
                self.chain=require("EmberRoutesProbe/ProductionChain").new(actor,self.binding and self.binding.handle or actor,self.entry,recipeId,quantity,self.object,"preview",true,self.preferences)
                self.plan=nil return
            end
            if reason then r.conditions[#r.conditions+1]=reason end
            r.state=#r.conditions==0 and "READY" or r.partial and "UNKNOWN" or "BLOCKED"
            self.finished=true self.plan=nil return r
        end
    end
    return request
end
return Preview
