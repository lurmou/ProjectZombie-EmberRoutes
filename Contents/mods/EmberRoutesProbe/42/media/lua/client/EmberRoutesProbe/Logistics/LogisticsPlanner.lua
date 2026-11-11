-- Ephemeral bounded candidate discovery. Candidates never constitute asset ownership.
local Registry=require "EmberRoutesProbe/Warehouse/ContainerRegistry"
local Membership=require "EmberRoutesProbe/Settlement/SettlementMembership"
local Sort=require "EmberRoutesProbe/Warehouse/SortPolicy"
local Producers=require "EmberRoutesProbe/Work/LaborProducers"
local Claims=require "EmberRoutesProbe/Work/LaborStore"
local Filter=require "EmberRoutesProbe/Warehouse/StorageFilter"
local Planner={}
function Planner.new(entry,settings,npc,compiled)
    local ids,reason
    if compiled and compiled.revision==entry.revision then ids=compiled.ids
    else ids,reason=Membership.query(entry) compiled=nil end
    if not ids then return nil,reason end
    local plan={ids=ids,settings=settings,npc=npc,index=compiled and compiled.index or Sort.index(),
        phase=compiled and "SOURCES" or "TARGETS",position=1,read=0,reason="NO_ROUTE",compiled=compiled,
        coords={},destWeights={},
        stats={accessible=0,inputs=0,storage=0,sources=0,protected=0,candidates=0,claimed=0}}
    function plan:waitingReason()
        local stats=self.stats
        if #self.ids==0 then return "NO_REGISTERED_CONTAINERS" end
        if stats.accessible==0 then return "NO_ACCESSIBLE_CONTAINERS" end
        if stats.storage==0 then return "NO_STORAGE_TARGET" end
        local hasTargets=false
        for _ in pairs(self.index.buckets) do hasTargets=true break end
        if not hasTargets then return "NO_TARGET_RULES" end
        if stats.inputs==0 and not self.settings.tidy then return "NO_INPUT_CONTAINER" end
        if stats.sources==0 then return "NO_INPUT_CONTAINER" end
        if self.read==0 then return "SOURCE_EMPTY" end
        if stats.candidates==0 then
            if stats.claimed>0 then return "ITEMS_ALREADY_ASSIGNED" end
            if stats.protected>0 then return "ONLY_PROTECTED_OR_SORTED" end
            return "NO_MISPLACED_ITEMS"
        end
        return self.reason=="NO_ROUTE" and "NO_MATCHING_DESTINATION" or self.reason
    end
    local function sourceValid(source)
        local current=Registry.revalidate(source,"take","local-world")
        return current and Registry.logistics(current)~="EXCLUDED" and source.container:getItems()==source.items
            and source.items:size()==source.size
    end
    function plan:step(budget)
        local spent=0
        while spent<budget do
            spent=spent+1
            if self.phase=="TARGETS" then
                local id=self.ids[self.position]
                if not id then
                    self.phase="SOURCES" self.position=1 self.compiled={ids=self.ids,index=self.index,revision=entry.revision}
                else
                    self.position=self.position+1
                    local target=Registry.resolve(id,"put","local-world")
                    if target and Registry.logistics(target)=="STORAGE" then
                        target.filter=Filter.copy(Registry.filter(target.object,target.container))
                        if target.filter then self.index:add(target) end
                    end
                end
            elseif self.phase=="SOURCES" then
                local id=self.ids[self.position]
                if not id then
                    if self.batch then return self.batch,"FOUND",spent end
                    return nil,"DONE",spent,self:waitingReason()
                end
                self.position=self.position+1
                local source=Registry.resolve(id,"take","local-world")
                if source then
                    local role=Registry.logistics(source)
                    self.stats.accessible=self.stats.accessible+1
                    if role=="INPUT" then self.stats.inputs=self.stats.inputs+1 end
                    if role=="STORAGE" then self.stats.storage=self.stats.storage+1 end
                    if (role=="INPUT" and self.settings.intake) or (role=="STORAGE" and self.settings.tidy) then
                        self.stats.sources=self.stats.sources+1
                        source.items=source.container:getItems() source.size=source.items:size() source.position=0
                        if source.size>2000 then return nil,"FAILED",spent,"SOURCE_SCAN_LIMIT" end
                        self.source=source self.phase="ITEMS"
                    end
                end
            elseif self.phase=="ITEMS" then
                local source=self.source
                if not sourceValid(source) then return nil,"CHANGED",spent,"INVENTORY_CHANGED" end
                if source.position>=source.size then
                    if self.batch and (#self.batch.items>=30 or (Producers.freeCarry(self.npc)-self.batchWeight)<1.0) then
                        return self.batch,"FOUND",spent
                    end
                    self.phase="SOURCES"
                else
                    self.read=self.read+1
                    if self.read>20000 then return nil,"FAILED",spent,"INVENTORY_SCAN_LIMIT" end
                    local item=source.items:get(source.position) source.position=source.position+1
                    if Claims.owner(item:getID()) then self.stats.claimed=self.stats.claimed+1
                    elseif not Producers.eligible(item) then self.stats.protected=self.stats.protected+1
                    elseif item:getContainer()==source.container then
                        local mode=Sort.source(Registry.logistics(source),self.settings,Registry.filter(source.object,source.container),item)
                        if mode then
                            self.stats.candidates=self.stats.candidates+1
                            self.item,self.mode,self.best=item,mode,nil self.targets=self.index:cursor(item) self.phase="ROUTE"
                        end
                    end
                end
            else
                local source,item=self.source,self.item
                if not sourceValid(source) or item:getContainer()~=source.container or not source.items:contains(item)
                    or Claims.owner(item:getID()) then return nil,"CHANGED",spent,"INVENTORY_CHANGED" end
                local target,done=self.targets:step()
                if done then
                    if self.best then
                        local weight=item:getUnequippedWeight()
                        if not self.batch or self.mode==self.batch.sourceMode then
                            local endpoint=Registry.resolve(self.best.id,"put","local-world")
                            local total=(self.batchWeight or 0)+weight
                            local destTotal=(self.destWeights[self.best.id] or 0)+weight
                            if endpoint and Registry.logistics(endpoint)=="STORAGE" and Registry.accepts(endpoint,item)
                                and Sort.source(Registry.logistics(source),self.settings,Registry.filter(source.object,source.container),item)==self.mode
                                and total<=Producers.freeCarry(self.npc)
                                and destTotal<=Claims.availableCapacity(endpoint.id,endpoint.container:getFreeCapacity(self.npc)) then
                                if not self.batch then
                                    self.batch={producer="LOGISTICS",settlementId=entry.id,sourceMode=self.mode,
                                        source=source.id,destination=self.best.id,items={},weights={},
                                        itemSources={},itemDestinations={}}
                                    self.batchWeight=0
                                    self.destWeights={}
                                end
                                self.batch.items[#self.batch.items+1]=item:getID()
                                self.batchWeight=total
                                self.destWeights[endpoint.id]=destTotal
                                self.batch.weights[item:getID()]=weight
                                self.batch.itemSources[tostring(item:getID())]=source.id
                                self.batch.itemDestinations[tostring(item:getID())]=endpoint.id
                                if #self.batch.items>=30 or (Producers.freeCarry(self.npc)-self.batchWeight)<0.1 then
                                    return self.batch,"FOUND",spent
                                end
                            end
                        end
                    end
                    self.phase="ITEMS"
                elseif target and target.id~=source.id then
                    local current=Registry.revalidate(target,"put","local-world")
                    if current and Registry.logistics(current)=="STORAGE" and Registry.accepts(current,item) then
                        local weight=item:getUnequippedWeight()
                        local hasRoom = Producers.hasCarryRoomFor and Producers.hasCarryRoomFor(self.npc,item) or (self.npc:getInventory() and self.npc:getInventory().hasRoomFor and self.npc:getInventory():hasRoomFor(self.npc,item))
                        if current.container:hasRoomFor(self.npc,item) and hasRoom
                            and Producers.freeCarry(self.npc)>=weight
                            and Claims.availableCapacity(current.id,current.container:getFreeCapacity(self.npc))>=weight then
                            local score=Sort.specificity(Registry.filter(current.object,current.container),self.targets.description,item)
                            if score then
                                local c1=self.coords[source.id]
                                if not c1 then
                                    local sq=source.object and source.object:getSquare()
                                    if sq then c1={x=sq:getX(),y=sq:getY(),z=sq:getZ()} self.coords[source.id]=c1 end
                                end
                                local c2=self.coords[current.id]
                                if not c2 then
                                    local sq=current.object and current.object:getSquare()
                                    if sq then c2={x=sq:getX(),y=sq:getY(),z=sq:getZ()} self.coords[current.id]=c2 end
                                end
                                local distance=c1 and c2 and ((c2.x-c1.x)^2+(c2.y-c1.y)^2+(c2.z-c1.z)^2) or 0
                                local pFilter=Registry.filter(current.object,current.container)
                                local candidate={id=current.id,priority=pFilter and pFilter.priority or 3,specificity=score,distance=distance}
                                if Sort.better(candidate,self.best) then
                                    self.best=candidate
                                end
                            end
                        elseif Producers.freeCarry(self.npc)<weight or not hasRoom then
                            self.reason="NPC_INVENTORY_FULL"
                        else self.reason="DESTINATION_FULL" end
                    end
                end
            end
        end
        return nil,"WAIT",spent
    end
    return plan
end
return Planner
