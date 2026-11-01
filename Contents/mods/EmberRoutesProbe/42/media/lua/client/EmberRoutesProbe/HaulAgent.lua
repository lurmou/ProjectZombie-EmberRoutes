-- Autonomous hauling adapter. The existing TaskRuntime remains the sole body owner.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Manifest=require 'EmberRoutesProbe/HaulManifest'
local Store=require 'EmberRoutesProbe/LaborStore'
local View=require 'EmberRoutesProbe/InventoryView'
local Transfer=require 'EmberRoutesProbe/WorkTransfer'
local Producers=require 'EmberRoutesProbe/LaborProducers'
local Driver=require 'EmberRoutesProbe/Driver'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Routing=require 'EmberRoutesProbe/HaulRouting'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Probe=require 'EmberRoutesProbe/Boot'
local Log=require 'EmberRoutesProbe/Log'
local Delivery=require 'EmberRoutesProbe/DeliveryTarget'
local A={}
local JobExecution=require 'EmberRoutesProbe/HaulJobs'
function A.new(npcId)
    local api={} local current,pending
    local function record() return Store.record(npcId) end
    local function changed(r)
	if r.format==3 then
	    local ok=JobExecution.commit(r)
	    if not ok and current and current.job==r then current.stopping=true current.commitFailure=true end
	    if not ok then return false end
	end
	Signals.changed(npcId)
	return true
    end
    local function binding(actor) return Driver.bindId(actor,npcId) end
    local function awaitingGrant()
        if pending then
            local rt=Runtime.current()
            if rt and rt:status(npcId,pending) then return true end
            pending=nil -- A cancelled/rejected queued grant never started the business closure.
        end
        return false
    end
    local function valid(c)
        return current==c and not c.stopping and not isClient() and not isServer() and Probe.ready
            and Store.valid(c.job,c.generation,c.token) and (not c.body or c.body.current())
            and (c.job.producer=='DELIVERY' or not c.actor:isDead()) and EmberRoutesProbeJava.carrierPresent(c.npc)
            and c.npc:getBodyDamage():getOverallBodyHealth()>=95
    end
    local function knownTransfer(c,s)
        local r=c.job local a=s.attempt
        if r.activeAttempt~=a then return true end -- Repeated notifications never release a newer claim.
        local fromAllowed=s.from==c.npc:getInventory() or Registry.revalidate(s.fromEndpoint,'take',r.scopeId)
        local toAllowed=s.to==c.npc:getInventory() or s.toEndpoint and s.toEndpoint.playerId
            and Delivery.endpointValid(c,s.toEndpoint) or Registry.revalidate(s.toEndpoint,'put',r.scopeId)
        local inFrom=fromAllowed and s.item:getContainer()==s.from and s.from:getItems():contains(s.item)
        local inTo=toAllowed and s.item:getContainer()==s.to and s.to:getItems():contains(s.item)
        if inTo and fromAllowed and not s.from:getItems():contains(s.item) then
            local line=Manifest.line(r,a.itemId)
            if a.kind=='TAKE' then line.custodyState='CARRIED'
            else
                local ok=Store.settleHaulLines(r,c.token,c.generation,{{itemId=a.itemId,state='DELIVERED',
                    receipt={destinationId=a.toId,attemptId=a.attemptId}}})
                if not ok then return false end
            end
            r.activeAttempt=nil c.attempt=nil changed(r) return true
        end
        -- Exact original still at its pre-effect location. Never read revoked private inventory.
        if inFrom and (not toAllowed or not s.to:getItems():contains(s.item)) then
            local line=Manifest.line(r,a.itemId)
            line.custodyState=a.kind=='PUT' and 'CARRIED' or 'UNCOLLECTED'
	    r.activeAttempt=nil c.attempt=nil changed(r) return true
        end
        return false
    end
    local function effects(c)
	if c.job.controlUncertain or c.commitFailure then return 'UNKNOWN' end
        if c.attempt and not knownTransfer(c,c.attempt) then return 'UNKNOWN' end
        return c.job.activeAttempt and 'UNKNOWN' or 'KNOWN'
    end
    function api.busy() return current~=nil end
    function api.pause(reason,owned)
        local c=owned or current
        if not c then
            if pending then local rt=Runtime.current() if rt then rt:stopJob(npcId,pending,reason or 'USER') end pending=nil end
            local r=record()
            if r and (reason=='USER' or reason=='MOVE' or reason=='STOP' or reason=='COMPANION_ORDER') then
                r.manualPaused=true r.reason=reason changed(r)
            end
            return true
        end
        if c.body and not owned then return c.body.requestStop(reason or 'USER') end
        c.stopping=true -- Fence perform before clearing potentially reentrant native queues.
        if c.body then
            if not c.body.clear() or not c.body.stop() then return false end
            if c.job.producer=='DELIVERY' and not c.body.sneak(false) then return false end
        else ISTimedActionQueue.clear(c.npc) EmberRoutesProbeJava.stopCarrier(c.npc) end
        if not c.stopped then
            local known=effects(c)=='KNOWN'
            if not known then c.job.controlUncertain=true end
            if known and #Manifest.claimItemIds(c.job)==0 and not c.job.returnForNextBatch then
                c.job.state='DONE' c.job.settlementOutcome=(c.job.withdrawn or 0)>0 and 'PARTIAL_WITHDRAWN' or 'DELIVERED'
		local settled=Store.finish(c.job)
		if not settled then c.commitFailure=true c.job.controlUncertain=true return false end
		c.completed=true c.closedGeneration=c.job.generation
                if current==c then current=nil end changed(c.job) return true
            end
            c.pauseToken=Store.pause(c.job)
            c.job.state='PAUSED' c.job.reason=known and (reason or 'USER') or 'RECONCILE_REQUIRED'
            if reason=='USER' or reason=='MOVE' or reason=='STOP' or reason=='COMPANION_ORDER' then c.job.manualPaused=true end
            c.stopped=true c.stoppedGeneration=c.job.generation
            if known then Store.releaseCapacity(c.pauseToken) end
            changed(c.job)
        end
        if current==c then current=nil end
        return true
    end
    function api.stopAdapter(controller,ticket)
        local c=current if not c then return nil,'NO_ACTIVE_TRANSFER' end
        local r,world,generation=c.job,Registry.data(),c.job.generation
        return require('EmberRoutesProbe/TaskBusinessStop').new({controller=controller,ticket=ticket,npc=c.npc,npcId=npcId,jobId=r.id,
            same=function(paused)
		if world~=Registry.data() then return false end
		if c.completed then
		    local saved=require('EmberRoutesProbe/TaskJobs').current():peek(r.id)
		    return saved and saved.state=='DONE' and r.generation==c.closedGeneration
		end
		if record()~=r then return false end
                if c.stopped then return r.generation==c.stoppedGeneration and r.state=='PAUSED' end
                return not paused and current==c and r.generation==generation
            end,
            pause=function(reason)
                if c.completed then return r.producer~='DELIVERY' or c.body.sneak(false) end
                return api.pause(reason,c)
            end,
            effects=function() return effects(c) end,
            persist=function(fact)
                if fact.effects=='UNKNOWN' then r.controlUncertain=true r.reason='RECONCILE_REQUIRED' changed(r) end
                return c.completed or c.stopped
            end})
    end
    local function upgrade(r,npc)
	if (r.format==2 or r.format==3) then return Manifest.valid(r),'TASK_RECORD_INVALID' end
        if r.format~=1 or r.producer~='LOGISTICS' or r.controlUncertain or r.state~='PAUSED'
            or not npc:getCharacterActions():isEmpty() then return false,'CURRENT_HAUL_UPGRADE_REQUIRED' end
        local rt=Runtime.current() if rt and rt:owns(npcId) then return false,'WAIT_BODY_STOP' end
        local source=Registry.resolve(r.source,'take',r.scopeId)
        local target=Registry.resolve(r.destination,'put',r.scopeId)
        if not source or not target then return false,'CURRENT_HAUL_UPGRADE_REQUIRED' end
        local index,why=View.index({source.container,npc:getInventory(),target.container})
        if not index then return false,why end
        local locations={}
        for _,id in ipairs(r.items) do
            local item,where,reason=View.find(index,id)
            if not item then return false,reason end locations[id]=where
        end
        local ok,reason=Store.upgradeHaul(r,Manifest.create(r,locations))
        if ok and (r.phase=='DELIVER' or string.find(r.reason or '','^FILTER_REJECTED') or r.reason=='NATIVE_TRANSFER_STOPPED') then r.deliveryOnly=true end
        return ok,reason
    end
    local launch
    launch=function(actor,r,body,nonPreemptive)
        if r.producer=='DELIVERY' and not Probe.controlledExecution then return 'CONTROL_REQUIRED' end
        if r.controlUncertain or r.activeAttempt then
            r.controlUncertain=true r.reason='RECONCILE_REQUIRED' changed(r) return 'RECONCILE_REQUIRED'
        end
        local b=binding(actor) if not b then return 'CARRIER_UNAVAILABLE' end
        local npc=b.handle
        local ok,why=upgrade(r,npc) if not ok then return why end
        if not npc:getCharacterActions():isEmpty() then return 'NATIVE_ACTION_BUSY' end
        if #Manifest.claimItemIds(r)==0 and not r.returnForNextBatch and not body then
            r.state='DONE' Store.finish(r) changed(r) return 'DONE'
        end
        if Probe.controlledExecution and not body then
            local rt=Runtime.current() if not rt then return 'ADMISSION_CLOSED' end
            local world,previous,generation=Registry.data(),record(),r.generation
            local c
            local h,reason=rt:submit({npcId=npcId,jobId=r.id,kind='TRANSFER',binding=b,nonPreemptive=nonPreemptive==true,
                captureStop=true,reconcileErrors=true,
                validate=function()
                    return Probe.ready and Registry.data()==world and record()==previous and r.generation==generation
                        and not r.controlUncertain and not current
                        and (r.producer=='DELIVERY' and Delivery.allowed(r) or r.producer~='DELIVERY' and not actor:isDead()
                            and require('EmberRoutesProbe/MembershipService').check(npcId,'WORK',
                                {x=npc:getX(),y=npc:getY(),z=npc:getZ(),scopeId=r.settlementId}).allowed)
                end,
                start=function(granted)
                    pending=nil local result=launch(actor,r,granted) c=current
                    return c~=nil,result,'UNCHANGED'
                end,
                tick=function() api.tick() end,finished=function() return c and current~=c end,
                stopAdapter=api.stopAdapter,
                persistFailure=function(fact,reason)
                    if Registry.data()~=world or record()~=r then return false end
                    if fact.effects=='UNKNOWN' then r.controlUncertain=true r.reason=reason or 'RECONCILE_REQUIRED' changed(r) end
                    return true
                end})
            if h then pending=r.id end return h and 'QUEUED' or reason
        end
        if not npc:getCharacterActions():isEmpty() then return 'NATIVE_ACTION_BUSY' end
        local token,reason=Store.claim(r) if not token then return reason end
        local c={actor=actor,npc=npc,job=r,body=body,token=token,generation=r.generation,backoff={},nextTick=0}
        for id,deadline in pairs(r.pathBackoff or {}) do
            if getTimestampMs()<deadline then c.backoff[id]=deadline end
        end
        r.pathBackoff=c.backoff
        c.valid=function() return valid(c) end
        current=c r.state='RUNNING' r.reason='EXECUTING'
        r.workerName=require('EmberRoutesProbe/DisplayNames').name(npcId,npc)
        local published,err=Store.publish(r) if not published then current=nil Store.finish(r) return err end
        changed(r) return 'STARTED'
    end
    function api.assign(actor,intent)
        if api.busy() or awaitingGrant() then return 'BUSY' end
        local old=record() if old and old.state~='DONE' then return 'TASK_EXISTS_RESUME_OR_CLEAR' end
	local r={id=intent.jobId or Registry.id(),npcId=npcId,format=3,kind='EXPLICIT_TRANSFER',scopeId='local-world',executor='ENTITY',
            producer=intent.producer,settlementId=intent.settlementId,source=intent.source,destination=intent.destination,
            sourceMode=intent.sourceMode,items={},state='PAUSED',reason='CREATED',phase='COLLECT',generation=0,
            routeRevision=0,attemptSequence=0,delivered=0}
        if intent.producer=='DELIVERY' then
            r.orderId,r.orderRevision,r.requesterId,r.itemTypes=intent.orderId,intent.orderRevision,intent.requesterId,intent.itemTypes
            r.returnForNextBatch=true
        end
        for _,id in ipairs(intent.items) do r.items[#r.items+1]=id end
        r.plannedCount=#r.items r.manifest=Manifest.create(r)
        if r.producer=='DELIVERY' then
            -- Queued admission must already own a durable Job and its originals.
            -- Saving before the body grant can then safely recover the same segment.
            if not Probe.controlledExecution or not Manifest.valid(r) then return 'CONTROL_REQUIRED' end
            local token,why=Store.claim(r) if not token then return why end
            local ok,reason=Store.publish(r)
            if not ok then Store.finish(r) return reason end
            local result=launch(actor,r,nil,true)
            if result~='QUEUED' and result~='STARTED' then r.reason=result changed(r) return 'QUEUED' end
            return result
        end
        return launch(actor,r,nil,true)
    end
    function api.resume(actor,nonPreemptive)
        if api.busy() or awaitingGrant() then return 'BUSY' end
        local r=record() if not r then return 'NO_TASK' end if r.state=='DONE' then return 'DONE' end
        if nonPreemptive==false then r.manualPaused=nil end
        return launch(actor,r,nil,nonPreemptive)
    end
    function api.hasCargo(actor)
        local r=record() if not r then return false end
        if r.controlUncertain or r.activeAttempt then return true end
	if r.format~=2 and r.format~=3 then return true end
        for _,l in ipairs(r.manifest) do if l.custodyState=='CARRIED' or l.custodyState=='RECONCILE' then return true end end
        local b=binding(actor) if not b then return #Manifest.claimItemIds(r)>0 end
        local index=View.index({b.handle:getInventory()}) if not index then return true end
        for _,id in ipairs(Manifest.claimItemIds(r)) do if View.find(index,id) then return true end end
        return false
    end
    local function withdraw(c)
        local changes={}
        for _,l in ipairs(c.job.manifest) do
            if l.custodyState=='UNCOLLECTED' then changes[#changes+1]={itemId=l.itemId,state='WITHDRAWN'} end
        end
        if #changes>0 then assert(Store.settleHaulLines(c.job,c.token,c.generation,changes)) end
        c.job.deliveryOnly=true c.job.phase='DELIVER'
    end
    local function snapshotStep(c,line,item,endpoint,kind)
        local r=c.job local own=c.npc:getInventory()
        local from,to=kind=='TAKE' and endpoint.container or own,kind=='TAKE' and own or endpoint.container
        r.attemptSequence=r.attemptSequence+1
        local a={attemptId=r.id..':'..r.attemptSequence,itemId=line.itemId,kind=kind,
            fromId=kind=='TAKE' and endpoint.id or npcId,toId=kind=='TAKE' and npcId or endpoint.id,
            routeRevision=r.routeRevision,sessionGeneration=c.generation}
        local s={attempt=a,item=item,from=from,to=to,fromEndpoint=kind=='TAKE' and endpoint or nil,toEndpoint=kind=='PUT' and endpoint or nil}
        line.plannedDestinationId=kind=='PUT' and endpoint.id or c.destination and c.destination.id
        local frozen={actor=c.actor,npc=c.npc,job=r,body=c.body,source=kind=='TAKE' and endpoint or nil,destination=kind=='PUT' and endpoint or nil,
            deliveryContext=r.producer=='DELIVERY' and c or nil}
        frozen.valid=function() return valid(c) and r.activeAttempt==a and r.routeRevision==a.routeRevision
            and (endpoint.playerId and Delivery.endpointValid(c,endpoint)
                or not endpoint.playerId and Registry.revalidate(endpoint,kind=='TAKE' and 'take' or 'put',r.scopeId)~=nil) end
        frozen.eligible=function(value)
            return Producers.eligible(value) and (r.producer=='DELIVERY' or kind=='PUT' and Routing.accept(c,endpoint,value)
                or kind=='TAKE' and Routing.accept(c,c.destination,value))
        end
        frozen.transferred=function() knownTransfer(c,s) end
        r.itemTypes=r.itemTypes or {} r.itemTypes[tostring(line.itemId)]=item:getFullType()
        r.activeAttempt=a c.attempt=s
	if r.format==3 then
	    local committed,why=JobExecution.commit(r)
	    if not committed then c.commitFailure=true return nil,why end
	end
        return Transfer.item(frozen,item,from,to,endpoint)
    end
    local function nextStep(c)
        if c.job.producer=='DELIVERY' then return require('EmberRoutesProbe/DeliveryFlow').next(c,snapshotStep,withdraw) end
        local r=c.job
        local source=not r.deliveryOnly and Registry.resolve(r.source,'take',r.scopeId) or nil
        if not c.scan then
            local containers={c.npc:getInventory()} if source then containers[2]=source.container end
            c.scan=View.scan(containers)
        end
        local index,why=c.scan:step(32)
        if not index then if why=='INVENTORY_CHANGED' then c.scan=nil end return nil,'SCAN_PENDING' end
        c.scan=nil
        local held,uncollected={},nil
        for _,l in ipairs(r.manifest) do
            if Manifest.pending(l) then
                local item,where,reason=View.find(index,l.itemId)
                if item and where==1 then l.custodyState='CARRIED' held[#held+1]=item
                elseif l.custodyState=='CARRIED' then return nil,'RECONCILE_REQUIRED'
                elseif item and where==2 then uncollected=uncollected or {line=l,item=item}
                elseif reason~='ITEM_MISSING' then return nil,'RECONCILE_REQUIRED' end
            end
        end
        if r.deliveryOnly then withdraw(c) end
        if not r.deliveryOnly and uncollected then
            local target=Registry.resolve(r.destination,'put',r.scopeId)
            c.source,c.destination=source,target
            if source and target and Routing.accept(c,target,uncollected.item)
                and Producers.transfer(c,uncollected.item,source.container,c.npc:getInventory())
                and Producers.freeCarry(c.npc)>=uncollected.item:getUnequippedWeight()
                and c.npc:getInventory():hasRoomFor(c.npc,uncollected.item) then
                local reserved=Store.capacity(c.token,uncollected.item:getID(),target.id,
                    uncollected.item:getUnequippedWeight(),target.container:getFreeCapacity(c.npc))
                if not reserved then withdraw(c) return nil,'SCAN_PENDING' end
                if not Transfer.reachable(c.npc,source) then
                    c.moveEndpoint=source c.moveRule={target=target,item=uncollected.item}
                    return Transfer.move(c,source)
                end
                return snapshotStep(c,uncollected.line,uncollected.item,source,'TAKE')
            end
            withdraw(c)
        elseif not r.deliveryOnly then
            if not source then withdraw(c) end r.phase='DELIVER'
        end
        if #held==0 then
            if #Manifest.claimItemIds(r)==0 then return nil,'DONE' end
            withdraw(c) return nil,'DONE'
        end
        local selected,target
        local old=c.destination or Registry.resolve(r.destination,'put',r.scopeId)
        for _,item in ipairs(held) do if Routing.accept(c,old,item) and getTimestampMs()>=(c.backoff[old.id] or 0) then selected,target=item,old break end end
        if not target then
            if not r.deliveryOnly then withdraw(c) end
            if not c.search then c.search=Routing.new(c,held) end
            if not c.search then return nil,'ROUTING_WAIT' end
            local candidate,status=c.search:step(Routing.allowance())
            if not candidate then
                if status=='SCAN_PENDING' then return nil,status end
                r.routingWait={reason=status} c.search=nil return nil,'ROUTING_WAIT'
            end
            selected,target=candidate.item,candidate.endpoint c.search=nil
        end
        if not c.destination or c.destination.id~=target.id then
            Store.releaseCapacity(c.token) r.routeRevision=r.routeRevision+1
            c.destination=target r.destination=target.id r.activeStop={destinationId=target.id}
            Log.write('HAUL_ROUTE','SELECT job='..r.id..' target='..target.id..' revision='..r.routeRevision)
        end
        if not Routing.accept(c,target,selected) then return nil,'SCAN_PENDING' end
        r.activeStop={destinationId=target.id,itemIds={selected:getID()}}
        local ok=Store.capacity(c.token,selected:getID(),target.id,selected:getUnequippedWeight(),target.container:getFreeCapacity(c.npc))
        if not ok then c.destination=nil return nil,'SCAN_PENDING' end
        if not Transfer.reachable(c.npc,target) then c.moveEndpoint=target c.moveRule={target=target,item=selected} return Transfer.move(c,target) end
        return snapshotStep(c,Manifest.line(r,selected:getID()),selected,target,'PUT')
    end
    local function tick()
        local c=current if not c then return end
        local now=getTimestampMs() if now<c.nextTick then return end c.nextTick=now+100
        if not valid(c) then api.pause('DRIVER_UNAVAILABLE') return end
        if c.job.producer=='DELIVERY' then
            local ok,why=Delivery.observe(c)
            if not ok then api.pause(why) return end
        end
        if c.moveEndpoint and (not Registry.revalidate(c.moveEndpoint,'take',c.job.scopeId)
            or c.moveRule and not Routing.accept(c,c.moveRule.target,c.moveRule.item)) then api.pause('ROUTING_WAIT') return end
        if not c.step then
            local step,why=nextStep(c)
            if not step then
                if why=='DONE' then
                    c.job.state='DONE' c.job.settlementOutcome=(c.job.withdrawn or 0)>0 and 'PARTIAL_WITHDRAWN' or 'DELIVERED'
		    local settled=Store.finish(c.job)
		    if not settled then c.commitFailure=true api.pause('RECONCILE_REQUIRED') return end
		    c.completed=true c.closedGeneration=c.job.generation current=nil changed(c.job)
                elseif why~='SCAN_PENDING' then
                    if why=='RECONCILE_REQUIRED' then c.job.controlUncertain=true end
                    api.pause(why)
                end return
            end
            c.step,c.started=step,now
            local state,reason=step.start()
            if state=='FAILED' then api.pause('ROUTING_WAIT') return end
        end
        local state,why=c.step.poll()
        if state=='PASSED' then c.step=nil c.moveEndpoint=nil c.moveRule=nil
        elseif state=='FAILED' or now-c.started>=(c.step.timeout or 60000) then
            if c.moveEndpoint then
                local count,oldest,earliest=0,nil,math.huge
                for id,deadline in pairs(c.backoff) do
                    if deadline<=now then c.backoff[id]=nil
                    else count=count+1 if deadline<earliest then oldest,earliest=id,deadline end end
                end
                if count>=90 and oldest then c.backoff[oldest]=nil end
                c.backoff[c.moveEndpoint.id]=now+15000
            end
            api.pause('ROUTING_WAIT')
        end
    end
    function api.tick()
        local ok,err=pcall(tick)
        if not ok then Log.write('HAUL_ROUTE','ERROR '..tostring(err)) if current then current.job.controlUncertain=true end api.pause('ERROR') end
    end
    function api.reset() api.pause('WORLD_RESET') current,pending=nil,nil end
    return api
end
return A
