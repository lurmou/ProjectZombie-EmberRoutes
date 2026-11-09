-- Pure bounded target discovery for already claimed cargo; no body/asset writes.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/Settlement/SettlementMembership'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Sort=require 'EmberRoutesProbe/Warehouse/SortPolicy'
local Filter=require 'EmberRoutesProbe/Warehouse/StorageFilter'
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local R={}
local window,left=-1,0
function R.allowance()
    local now=getTimestampMs()
    if now-window>=50 or now<window then window,left=now,32 end
    local n=math.min(8,left) left=left-n return n
end
function R.accept(c,endpoint,item)
    if not endpoint or endpoint.id==c.job.source then return false end
    local current=Registry.revalidate(endpoint,'put',c.job.scopeId)
    local entry=Ledger.get(c.job.settlementId)
    local p=current and Registry.describe(current.id)
    if not current or not entry or not p or not require('EmberRoutesProbe/Settlement/SettlementGeometry').inside(entry,p.x,p.y)
        or Registry.logistics(current)~='STORAGE' or not Registry.accepts(current,item) then return false end
    local weight=item:getUnequippedWeight()
    return current.container:hasRoomFor(c.npc,item)
        and Store.availableFor(c.token,current.id,item:getID(),current.container:getFreeCapacity(c.npc))>=weight
end
function R.new(c,items)
    local entry=Ledger.get(c.job.settlementId)
    local ids,why
    if entry then ids,why=Membership.query(entry) end
    if not ids then return nil,why or 'SETTLEMENT_CHANGED' end
    local index=Sort.index()
    local unknown=false
    for _,id in ipairs(ids) do
        local target,reason=Registry.resolve(id,'put',c.job.scopeId)
        if reason=='CONTAINER_UNLOADED' then unknown=true end
        if target and id~=c.job.source and Registry.logistics(target)=='STORAGE' then
            target.filter=Filter.copy(Registry.filter(target.object,target.container))
            if target.filter then index:add(target) end
        end
    end
    local search={items=items,index=index,i=1,cursor=nil,best=nil,unknown=unknown}
    function search:step(budget)
        for _=1,budget do
            local item=self.items[self.i]
            if not item then
                return nil,self.unknown and 'TARGET_UNOBSERVED' or self.capacity and 'NO_CAPACITY'
                    or self.blocked and 'PATH_BACKOFF' or 'NO_ACCEPTING_TARGET'
            end
            if not self.cursor then self.cursor=self.index:cursor(item) end
            local target,done=self.cursor:step()
            if done then
                if self.best then return self.best,'READY' end
                self.i=self.i+1 self.cursor=nil
            elseif target then
                local id=target.id
                local deadline=c.backoff[id] or 0
                if Registry.accepts(target,item) then
                    if getTimestampMs()<deadline then self.blocked=true
                    elseif not target.container:hasRoomFor(c.npc,item)
                        or Store.availableFor(c.token,id,item:getID(),target.container:getFreeCapacity(c.npc))<item:getUnequippedWeight() then
                        self.capacity=true
                    end
                end
                if getTimestampMs()>=deadline and R.accept(c,target,item) then
                    local s=target.object:getSquare()
                    local pFilter=Registry.filter(target.object,target.container)
                    local score=Sort.specificity(pFilter,self.cursor.description,item)
                    if score then
                        local candidate={id=id,endpoint=target,item=item,specificity=score,
                            priority=pFilter and pFilter.priority or 3,
                            distance=(s:getX()-c.npc:getX())^2+(s:getY()-c.npc:getY())^2+(s:getZ()-c.npc:getZ())^2}
                        if Sort.better(candidate,self.best) then self.best=candidate end
                    end
                end
            end
        end
        return nil,'SCAN_PENDING'
    end
    return search
end
return R
