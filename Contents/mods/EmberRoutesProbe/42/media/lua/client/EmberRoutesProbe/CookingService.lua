-- Public offers and recovery coordination only. Bodies run in TaskRuntime.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Store=require 'EmberRoutesProbe/LaborStore'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Policy=require 'EmberRoutesProbe/CookingPolicy'
local Supply=require 'EmberRoutesProbe/CookingSupplyService'
local Menu=require 'EmberRoutesProbe/CookingMenu'
local Evolved=require 'EmberRoutesProbe/CookingEvolved'
local Profiles=require 'EmberRoutesProbe/CookingProfiles'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local Driver=require 'EmberRoutesProbe/Driver'
local Members=require 'EmberRoutesProbe/MembershipService'
local Observer=require 'EmberRoutesProbe/NeedsObserver'
local Work=require 'EmberRoutesProbe/Work'
local Signals=require 'EmberRoutesProbe/LaborSignals'
local Orders=require 'EmberRoutesProbe/CookingOrders'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local S={}
local world,plans,order,cursor,retained,jobCursor,offers,samples,nextPump,budget,frame,retryJobs,sites
local crewScan,nextCrew=nil,0
local failedAuto={}
local function load()
    local root=Registry.data()
    if root~=world then
        world,plans,order,cursor,retained,jobCursor,offers,samples,nextPump=root,{},{},0,{},0,{},{},0
        for id,j in pairs(root.taskJobs and root.taskJobs.byId or {}) do
            if j.providerType=='COOKING' and j.state~='DONE' and j.state~='CANCELLED' then retained[#retained+1]=id end
        end
        table.sort(retained) frame=nil retryJobs={} sites={} crewScan=nil nextCrew=0 failedAuto={}
    end
    return root
end
-- One shared backoff per settlement: another cook must not immediately repeat
-- a known failed batch. Capture AFTER returns so our own inventory events do
-- not immediately wake it; configuration/stock changes can wake it early.
local function autoBlocked(entry,now)
    local failed=failedAuto[entry.id]
    if not failed then return false end
    if now>=failed.untilWall or Wake.changed(failed.watch) then failedAuto[entry.id]=nil return false end
    return true,failed.reason
end
local function budgets()
    load() local now=math.floor(getTimestampMs()/50)
    if now~=frame then frame=now budget={nodes=96,scan=64,paths=2} end
    return budget
end
local function safe(binding,now)
    local npc=binding.handle local row=samples[binding.id]
    if not row or now<row.at or now-row.at>=250 then
        local value,why=Observer.sample(npc,binding.id,now)
        row={at=now,value=value,reason=why} samples[binding.id]=row
    end
    return row.value and row.value.safe==true and not npc:isOnFire()
        and npc:getSurroundingAttackingZombies(false)==0 or false
end
local function idle(actor,id,careId)
    local runtime=Runtime.current() local binding=Driver.bindId(actor,id)
    if not runtime or not binding or not Driver.valid(binding) or runtime:owns(id) or binding.handle:isDead()
        or Work.busy(id) or Work.hasCargo(actor,id,'COOKING') then return end
    if require('EmberRoutesProbe/SelfCare').blocksWork(id) then
        local care=careId and Jobs.current():peek(careId)
        if not care or care.npcId~=id or care.providerType~='SELF_CARE' or care.effects~='KNOWN'
            or #care.payload.claims>0 then return end
        for _ in pairs(care.obligations) do return end
    end
    if safe(binding,getTimestampMs()) then return binding end
end
local function submit(actor,binding,job,settle)
    local object
    if job.payload.fixed and not settle then
        local fixed=job.payload.fixed local made=false
        for _,r in ipairs(job.payload.bindings or {}) do if r.sequence==fixed.craftSequence then made=true end end
        if not made then
            local facts,why=require('EmberRoutesProbe/CookingCraft').profile(fixed.recipeId)
            if not facts then return nil,why end
            if facts.facts.workstation or facts.facts.surface then
            local entry=Members.entry(binding.id,job.scopeId) if not entry then return nil,'NO_MEMBERSHIP' end
            local search=sites[job.id]
            if not search then search=require('EmberRoutesProbe/CraftStations').search(entry,facts.facts,function(object) return require('EmberRoutesProbe/CookingDirectives').kitchen(entry.id,object) end) sites[job.id]=search end
            local b=budgets() local n=math.min(16,b.scan) if n<1 then return nil,'SITE_OBSERVING' end b.scan=b.scan-n
            local candidate,reason=search:step(n) if not candidate then return nil,reason end
            object=candidate.object
            end
        end
    end
    local spec,why=require('EmberRoutesProbe/CookingAgent').new(actor,binding,job,object,budgets,
        function() return safe(binding,getTimestampMs()) end,{settleOnly=settle})
    if not spec then return nil,why end
    return Runtime.current():submit(spec)
end
function S.retained(id)
    load() local found=false
    Jobs.current():visitNpc(id,function(j)
        if j.providerType=='COOKING' and j.state~='DONE' and j.state~='CANCELLED' then found=true end
    end)
    return found
end
function S.wake(actor,id,jobId,careId)
    load() local job=Jobs.current():get(jobId)
    if not job or job.npcId~=id or job.effects~='KNOWN' or job.state~='SUSPENDED' then return false end
    local binding=idle(actor,id,careId) if not binding then return false end
    return submit(actor,binding,job,job.payload.duty~=nil)~=nil
end
local function recover(actor,job)
    if not job or job.effects~='KNOWN' or job.state~='SUSPENDED' and job.state~='SETTLING' and job.state~='PREPARING'
        or not (job.payload.evolved or job.payload.fixed or job.payload.raw) then return end
    local runtime=Runtime.current()
    if runtime:status(job.npcId,job.id) then return end
    local now=getTimestampMs()
    if now<(retryJobs[job.id] or 0) then return end
    retryJobs[job.id]=now+(job.payload.duty and 250 or 2000)
    local binding=idle(actor,job.npcId)
    local work=binding and Members.check(binding.id,'WORK',{x=binding.handle:getX(),y=binding.handle:getY(),
        z=binding.handle:getZ(),scopeId=job.scopeId})
    local priority=binding and require('EmberRoutesProbe/PublicWork').priorities(binding.id).cooking or 0
    local request=job.payload.source=='REQUEST' and Orders.get(job.payload.sourceId)
    local cancelled=job.payload.cancelRequested or request and (request.cancelRequested or request.stopBatchRequested)
    local paused=job.payload.pauseRequested or request and request.pauseRequested
    local reason=job.payload.reason or ''
    local userHold=paused or string.find(reason,'USER',1,true) or string.find(reason,'CANCEL',1,true)
    if binding then
        if userHold and not job.payload.duty and not cancelled then return end
        local settle=cancelled or job.payload.duty~=nil or priority==0 or not work.allowed
        submit(actor,binding,job,settle) return
    end
    if not job.payload.duty or not job.payload.stopProof then return end
    -- Reservations of potential rescuers are ordinary non-preemptive body grants.
    -- At most four roster probes here; no full per-Duty roster search per frame.
    local count=EmberRoutesProbeJava.workerCount()
    if count<1 or count>256 then return end
    S.rescueCursor=(S.rescueCursor or 0)%count
    for _=1,math.min(4,count) do
        local id=EmberRoutesProbeJava.workerIdAt(S.rescueCursor) S.rescueCursor=(S.rescueCursor+1)%count
        local nextBinding=id~=job.npcId and idle(actor,id)
        if nextBinding then
            local nextJob=require('EmberRoutesProbe/CookingHandoff').transfer(actor,job,nextBinding)
            if nextJob then submit(actor,nextBinding,nextJob,true) Signals.changed(id) return end
        end
    end
end
local function requestPlan(row,o,entry,binding,b,actor)
    if not row.gate then
        row.cold={entry=entry,npc=binding.handle}
        row.gate=require('EmberRoutesProbe/CookingCargo').coldGate(row.cold,.001)
    end
    row.cold.budget=b
    local cold=row.gate.run()
    if cold=='Failure' then row.reason=row.cold.reason row.retry=getTimestampMs()+2000 row.gate=nil return end
    if cold~='Success' then return end
    local spec=Orders.describe(o.recipeId)
    if not spec then row.reason='RECIPE_MECHANISM_UNSUPPORTED' row.retry=getTimestampMs()+2000 return end
    row.descriptor=spec row.studyTarget=nil
    if spec.kind=='CRAFT' then
        if not binding.handle:isRecipeKnown(spec.recipe,true) then
            row.reason='NPC_RECIPE_UNKNOWN' row.studyTarget=Orders.study(o,spec) return
        end
        if not require('EmberRoutesProbe/CookingCraft').known(binding.handle,spec.recipe) then row.reason='NPC_SKILL_TOO_LOW' return end
        if spec.profile.facts.workstation or spec.profile.facts.surface then
            if not row.stationScan then row.stationScan=require('EmberRoutesProbe/CraftStations').search(entry,spec.profile.facts,function(object) return require('EmberRoutesProbe/CookingDirectives').kitchen(entry.id,object) end) end
            local allowance=math.min(16,b.scan) if allowance<1 then return end b.scan=b.scan-allowance
            local site,why=row.stationScan:step(allowance)
            if not site then row.reason=why return end
            row.station=site.object
        end
        if row.bomScan then
            local allowance=math.min(32,b.scan) if allowance<1 then return end b.scan=b.scan-allowance
            local plan,err=row.bomScan:step(allowance)
            if plan then
                row.bomScan=nil row.fixedScan=nil row.retry=getTimestampMs()+2000
                if #plan.nodes>1 then
                    local result=require('EmberRoutesProbe/PublicWork').createPrerequisite(actor,o.id,plan.nodes[1])
                    row.reason=result=='ORDER_CREATED' and 'COOKING_PREREQUISITE_WAIT' or result
                else row.reason='INPUT_CHANGED' end
            elseif err then row.bomScan=nil row.reason=err row.retry=getTimestampMs()+2000 end
            return
        end
        if not row.fixedScan then
            row.fixedScan,row.reason=require('EmberRoutesProbe/CookingSupply').new(entry,binding.handle,spec.recipeId,'offer:'..o.id)
        end
        if not row.fixedScan then return end
        local allowance=math.min(32,b.scan) if allowance<1 then return end b.scan=b.scan-allowance
        local selection,err=row.fixedScan:step(allowance)
        if selection then row.selection=selection row.ready=true row.reason=nil
        elseif err then
            row.reason=err row.fixedScan=nil row.retry=getTimestampMs()+2000
            if err=='MATERIALS_UNAVAILABLE' or err=='TOOLS_UNAVAILABLE' then
                row.bomScan,row.reason=require('EmberRoutesProbe/CookingSupply').chain(actor,entry,binding.handle,
                    spec.recipeId,row.station,o.id,o.preferences)
                if row.bomScan then row.reason='COOKING_PREREQUISITE_CHECK' row.retry=0 end
            end
        end
    else
        if not row.menu then row.menu,row.reason=Menu.new(entry,binding.handle,.3,spec.recipeId,Profiles.accept,{actor=actor}) end
        if not row.menu then return end
        local allowance=math.min(32,b.scan) if allowance<1 then return end b.scan=b.scan-allowance
        local done,why=row.menu:step(allowance)
        if done then row.selection,row.reason=row.menu:result() row.ready=row.selection~=nil
            if not row.ready then row.menu=nil row.retry=getTimestampMs()+2000 end
        elseif done==nil then row.menu=nil row.reason=why row.retry=getTimestampMs()+500 end
    end
end
function S.advance(env)
    load() local now=env.now
    if now<nextPump then return end nextPump=now+50
    if not Runtime.current() or not Runtime.current():accepting() or world.executionSave and world.executionSave.state=='BLOCKED' then return end
    local b=budgets()
    if not crewScan and now>=nextCrew then
        local scopes={} local requests={}
        for _,o in pairs(world.publicWork and world.publicWork.orders or {}) do
            if o.parentOrderId and not o.jobId and o.state=='WAITING' and not Orders.parentAllows(o) then
                local parent=world.publicWork.orders[o.parentOrderId]
                if not parent or parent.state=='DONE' or parent.state=='CANCELLED' or parent.cancelRequested then
                    o.state='CANCELLED' o.reason='CANCELLED' o.revision=o.revision+1 Signals.changed()
                end
            end
            if o.category=='cooking' and o.state=='WAITING' and not o.jobId then
                requests[#requests+1]=o
                if not scopes[o.settlementId] then scopes[o.settlementId]={ids=Members.members(o.settlementId),index=1} end
            end
        end
        crewScan={scopes=scopes,requests=requests} nextCrew=now+2000
    end
    if crewScan then
        local remaining=16 local done=true
        for _,scope in pairs(crewScan.scopes) do
            while not scope.enabled and scope.index<=#scope.ids and remaining>0 do
                local id=scope.ids[scope.index] scope.index=scope.index+1 remaining=remaining-1
                local member=Members.view(id)
                if member and not member.retired and member.context=='SETTLEMENT'
                    and (require('EmberRoutesProbe/PublicWork').priorities(id).cooking or 0)>0 then scope.enabled=true end
            end
            if not scope.enabled and scope.index<=#scope.ids then done=false end
        end
        if done then
            for _,o in ipairs(crewScan.requests) do
                local scope=crewScan.scopes[o.settlementId]
                if not scope.enabled then Orders.wait(o,'NO_COOK_AVAILABLE')
                elseif o.reason=='NO_COOK_AVAILABLE' then Orders.wait(o,'WAITING_CLAIM') end
            end
            crewScan=nil
        end
    end
    for _=1,math.min(8,#retained) do
        jobCursor=jobCursor%#retained+1 local j=Jobs.current():get(retained[jobCursor])
        if j then Orders.settle(j) end
        recover(env.actor,j)
    end
    for _=1,math.min(2,#order) do
        cursor=cursor%#order+1 local id=order[cursor] local row=plans[id]
        if row and now>=row.retry then
            local binding=idle(env.actor,id)
            local entry=binding and Members.entry(id,row.entry.id)
            local priority=require('EmberRoutesProbe/PublicWork').priorities(id).cooking or 0
            if not binding or not entry or priority==0 then plans[id]=nil
            else
                if row.revision~=entry.revision or row.watch and Wake.changed(row.watch)
                    or row.readyAt and now-row.readyAt>=2000 then
                    row.menu=nil row.fixedScan=nil row.bomScan=nil row.stationScan=nil row.ready=nil
                    row.readyAt=nil row.selection=nil row.gate=nil row.revision=entry.revision row.watch=nil
                end
                row.entry=entry
                local request=Orders.first(entry.id)
                -- Before accepting another non-preemptive batch, preserve daily
                -- food priority. Unknown shared supply cannot be treated as zero.
                local snapshot,observing
                if request then
                    snapshot,observing=Supply.observe(entry,now,getGameTime():getWorldAgeHours(),b)
                    if snapshot and (not row.autoUnavailableUntil or now>=row.autoUnavailableUntil)
                        and not row.orderId and snapshot.demand.ready+Policy.epsilon<snapshot.demand.low
                        and snapshot.demand.gap>Policy.epsilon then request=nil end
                end
                local requestId=request and request.id
                if row.orderId~=requestId then
                    row.menu=nil row.fixedScan=nil row.bomScan=nil row.stationScan=nil row.ready=nil row.readyAt=nil row.selection=nil row.gate=nil row.studyTarget=nil
                    row.orderId=requestId
                end
                if request then
                    if snapshot then requestPlan(row,request,entry,binding,b,env.actor)
                    else row.reason=observing end
                    Orders.wait(request,row.ready and 'WAITING_CLAIM' or row.reason)
                    if row.ready then Signals.changed(id) end
                else
                local supply,why=Supply.observe(entry,now,getGameTime():getWorldAgeHours(),b)
                row.reason=why
                if supply then
                    if not supply.demand.active then
                        row.reason='MEALS_SUFFICIENT'
                        row.menu=nil row.ready=nil row.retry=now+2000
                    elseif autoBlocked(entry,now) then
                        local _,reason=autoBlocked(entry,now)
                        row.reason=reason row.menu=nil row.ready=nil row.gate=nil row.selection=nil
                    else
                        if not row.gate then
                            row.cold={entry=entry,npc=binding.handle}
                            row.gate=require('EmberRoutesProbe/CookingCargo').coldGate(row.cold,.001)
                        end
                        row.cold.budget=b
                        local state=row.gate.run()
                        if state=='Failure' then row.reason=row.cold.reason row.retry=now+2000 row.gate=nil
                        elseif state=='Success' then
                        if not row.menu then row.menu,row.reason=Menu.new(entry,binding.handle,supply.demand.gap,nil,Profiles.accept,{actor=env.actor}) end
                        if row.menu and not row.ready and b.scan>0 then
                            local allowance=math.min(32,b.scan) b.scan=b.scan-allowance
                            local done,err=row.menu:step(allowance)
                            if done then
                                row.selection,row.reason=row.menu:result() row.ready=row.selection~=nil
                                if not row.ready then row.menu=nil row.retry=now+2000 row.autoUnavailableUntil=now+30000 end
                            elseif done==nil then row.menu=nil row.selection=nil row.reason=err row.retry=now+500 end
                        end
                        if row.ready then Signals.changed(id) end
                        end
                    end
                end
                end
                if not row.watch then row.watch=Wake.capture(entry) end
                if row.ready and not row.readyAt then row.readyAt=now end
            end
        end
    end
end
function S.discover(env)
    load() local id=env.npcId local row=plans[id]
    if not row then
        if #order>=256 then return end
        row={entry=env.entry,revision=env.entry.revision,retry=0} plans[id]=row
        local exists=false for _,v in ipairs(order) do if v==id then exists=true end end
        if not exists then order[#order+1]=id end
    end
    if row.entry.id~=env.entry.id then plans[id]=nil return end
    if not row.orderId and autoBlocked(env.entry,env.now or getTimestampMs()) then return end
    if not row.ready then
        if row.studyTarget and env.setStudyTarget then env.setStudyTarget(row.studyTarget) end
        if not row.reason or row.reason=='SUPPLY_NOT_OBSERVED' or row.menu then env.pending=true end
        return
    end
    local o=row.orderId and Orders.get(row.orderId)
    if row.orderId and (not o or o.jobId or o.state~='WAITING') then plans[id]=nil return end
    local key=o and 'cook-order:'..o.id or 'cooking:'..env.entry.id
    local revision=o and o.sequence or 1
    local offer=env.upsertOffer(key,revision,'cooking',env.entry.id)
    if offer and not offer.jobId then env.candidates[#env.candidates+1]={key=key,revision=revision,category='cooking',
        allowed=true,score=o and 1+1/(o.sequence+1) or 0,npcId=id,scopeId=env.entry.id,orderId=o and o.id} end
end
local function rejectEmpty(job,token)
    if not token then
        if job.effects~='KNOWN' or #job.payload.claims>0 or #job.payload.assets>0 or Store.hasTaskClaims(job.id) then return end
        local ok,revision=Jobs.current():update(job.id,job.revision,{state='SETTLING'})
        if not ok then return end
        local j=Jobs.current():get(job.id) j.payload.phase='SETTLED'
        Jobs.current():update(job.id,revision,{state='CANCELLED',payload=j.payload}) return
    end
    local c={job=job,token=token} local j=Record.copy(job) j.state='SETTLING'
    local changed,saved,nextToken=Store.replaceCooking(c.job,c.token,j) if not changed then return end
    j=Record.copy(saved) j.state='CANCELLED' j.payload.phase='SETTLED'
    local ok,final,finalToken=Store.replaceCooking(saved,nextToken,j)
    if ok then Store.finishCooking(final,finalToken) end
end
function S.claim(selected,npcId,jobId,env)
    load() local row=plans[npcId] local binding=idle(env.actor,npcId)
    if not row or not binding or row.entry.id~=selected.scopeId or not row.ready then return 'COOKING_CANDIDATE_CHANGED' end
    -- A failed native revalidation must trigger fresh observation, rather than
    -- advertising the same stale originals forever.
    plans[npcId]=nil
    local job,prepared,ok,reason
    local o=selected.orderId and Orders.get(selected.orderId)
    if selected.orderId then
        if not o or o.jobId or o.state~='WAITING' or o.id~=row.orderId or not Orders.parentAllows(o)
            or Orders.prerequisite(o) then return 'COOKING_CANDIDATE_CHANGED' end
        local descriptor=Orders.describe(o.recipeId) if not descriptor then return 'RECIPE_MECHANISM_UNSUPPORTED' end
        local selection=row.selection
        if descriptor.kind=='EVOLVED' then
            selection,reason=row.menu:result() if not selection then return reason end
            selection,reason=Menu.fit(selection,.3) if not selection then return reason end
        else
            if not require('EmberRoutesProbe/CookingCraft').known(binding.handle,descriptor.recipe) then return 'NPC_RECIPE_UNKNOWN' end
            local bound,why=require('EmberRoutesProbe/CraftRecipeInputs').bind(descriptor.profile.facts,selection.entries,binding.handle)
            if not bound then return why end
            for _,r in ipairs(selection.entries) do
                if r.item:getContainer()~=(r.endpoint and r.endpoint.container or binding.handle:getInventory())
                    or Store.owner(r.id) or r.endpoint and not Registry.revalidate(r.endpoint,'take','local-world') then return 'INPUT_CHANGED' end
            end
        end
        local target=descriptor.kind=='EVOLVED' and selection.target or .075
        local quota=descriptor.kind=='EVOLVED' and math.max(target,selection.minimum) or .075
        job=Record.new(jobId,npcId,row.entry.id,descriptor.recipeId,'REQUEST',o.id,target,quota)
        if not job then return 'COOKING_ADMISSION_INVALID' end
        if descriptor.kind=='EVOLVED' then job.payload.mealBatch=true job.payload.expected=selection.estimated end
        if descriptor.kind=='EVOLVED' then prepared,reason=Evolved.prepare(job,descriptor.recipe,selection)
        else prepared,reason=require('EmberRoutesProbe/CookingBatch').prepare(job,selection) end
        if not prepared then return reason or 'COOKING_BATCH_INVALID' end
        local book=require('EmberRoutesProbe/CookingBudget').open(world,Jobs.current())
        local view=book and book:view(row.entry.id) if not view then return 'COOKING_SUPPLY_CHANGED' end
        ok,reason=book:reserve(job,{scopeId=row.entry.id,stamp=view.stamp,complete=true})
    else
        local selection,why=row.menu:result() if not selection then plans[npcId]=nil return why end
        local snapshot,err=Supply.observe(row.entry,env.now,getGameTime():getWorldAgeHours(),budgets()) if not snapshot then return err end
        if not snapshot.demand.active then return 'MEALS_SUFFICIENT' end
        local directives=require('EmberRoutesProbe/JobPolicyService').get(row.entry.id,'cooking')
        local gap=directives.batchMeals==false and math.min(snapshot.demand.gap,selection.minimum) or snapshot.demand.gap
        selection,why=Menu.fit(selection,gap) if not selection then return why end
        local batch,err2=Policy.batch(snapshot.demand,selection.minimum) if not batch then return err2 end
        local target=math.min(batch.target,selection.estimated) local quota=math.max(target,selection.minimum)
        local profileId=selection.kind=='HEAT' and 'heat:'..selection.base.item:getFullType() or selection.recipe:getOriginalname()
        job=Record.new(jobId,npcId,row.entry.id,profileId,'AUTO','policy:'..row.entry.id,target,quota)
        if not job then return 'COOKING_ADMISSION_INVALID' end
        job.payload.expected=selection.estimated
        if selection.kind=='HEAT' then
            local base=selection.base prepared=Record.copy(job)
            prepared.payload.raw={id=base.id,sourceId=base.endpoint.id,fullType=base.item:getFullType()}
            prepared.payload.assets={{id=base.id,fullType=base.item:getFullType(),custody='SOURCE',role='OUTPUT'}}
            prepared.payload.claims={'item:'..base.id}
        else prepared,reason=Evolved.prepare(job,selection.recipe,selection) end
        if not prepared then return reason end
        ok,reason=Supply.reserve(row.entry,job,snapshot,selection.minimum,env.now,getGameTime():getWorldAgeHours())
    end
    if not ok then return reason end
    if o then o.jobId=jobId o.npcId=npcId o.state='RUNNING' o.revision=o.revision+1 Signals.changed(npcId) end
    -- From here the directory offer stays retained until THIS Job proves closure.
    offers[selected.key]={jobId=jobId,directory=env.directory,ticket=jobId}
    retained[#retained+1]=jobId plans[npcId]=nil
    local token=Store.claimCooking(Jobs.current():get(jobId))
    if not token then rejectEmpty(Jobs.current():get(jobId)) return 'QUEUED' end
    local changed,saved=Store.replaceCooking(Jobs.current():get(jobId),token,prepared)
    if not changed then rejectEmpty(Jobs.current():get(jobId),token) return 'QUEUED' end
    submit(env.actor,binding,saved,false)
    return 'QUEUED'
end
function S.reconcile()
    load()
    for key,offer in pairs(offers) do
        local j=Jobs.current():peek(offer.jobId)
        if j then Orders.settle(j) end
        if j and (j.state=='DONE' or j.state=='CANCELLED') and j.effects=='KNOWN' and #j.payload.claims==0 then
            local empty=true for _ in pairs(j.obligations) do empty=false end
            if empty and offer.directory:release(key,offer.ticket,{effects='KNOWN',obligationsCleared=true}) then
                if j.state=='CANCELLED' and j.payload.source=='AUTO' and j.payload.heat and j.payload.heat.aborted
                    and not j.payload.cancelRequested and not j.payload.pauseRequested then
                    local entry=Members.entry(j.npcId,j.scopeId)
                    if entry then failedAuto[entry.id]={watch=Wake.capture(entry),untilWall=getTimestampMs()+30000,
                        reason=j.payload.reason or j.payload.heat.reason or 'HEAT_STOPPED_BEFORE_COOKED'} end
                end
                require('EmberRoutesProbe/Log').write('COOKING','SETTLED job='..j.id..' npc='..j.npcId
                    ..' state='..j.state..' profile='..j.payload.profileId..' reason='..tostring(j.payload.reason or j.payload.heat and j.payload.heat.reason))
                offers[key]=nil
            end
        end
    end
end
function S.hasWork() load() return #retained>0 or #order>0 end
function S.retire(limit)
    load() local runtime=Runtime.current() local count=0
    if not runtime or not runtime:accepting() or world.executionSave and world.executionSave.state=='BLOCKED' then return 0 end
    S.reconcile()
    local keep={}
    for _,id in ipairs(retained) do
        local j=Jobs.current():peek(id) local can=j and (j.state=='DONE' or j.state=='CANCELLED')
            and j.effects=='KNOWN' and #j.payload.claims==0 and not runtime:status(j.npcId,id) and not Store.hasTaskClaims(id)
        for _,offer in pairs(offers) do if offer.jobId==id then can=false end end
        if can and count<limit then
            for _,other in pairs(world.taskJobs.byId) do
                local ref=other.providerType=='SELF_CARE' and other.payload.resume
                if ref and ref.kind=='COOKING' and ref.jobId==id and ref.state~='RESTORED' and ref.state~='INVALIDATED' then
                    if other.effects~='KNOWN' then can=false
                    else
                        local p=Record.copy(other.payload)
                        p.resume.state=other.npcId==j.npcId and 'RESTORED' or 'INVALIDATED'
                        if not Jobs.current():update(other.id,other.revision,{payload=p}) then can=false end
                    end
                end
            end
            if can and Jobs.current():removeSettled(id,j.revision) then
                count=count+1 j=nil
                for npcId,r in pairs(world.executionSave and world.executionSave.byNpc or {}) do
                    if r.jobId==id then world.executionSave.byNpc[npcId]=nil end
                end
            end
        end
        if j then keep[#keep+1]=id end
    end
    retained=keep jobCursor=0
    if count>0 then Signals.changed() end
    return count
end
function S.status(id) load() local row=plans[id] return row and row.reason end
function S.stock(actor,rule)
    local entry=require('EmberRoutesProbe/SettlementLedger').view(actor,rule.settlementId)
    if not entry then return nil,'ACCESS_DENIED' end
    local snapshot,why=Supply.observe(entry,getTimestampMs(),getGameTime():getWorldAgeHours(),budgets())
    if not snapshot then return nil,why end
    return {state='READY',complete=true,knownCount=(snapshot.readyByType or {})[rule.product] or 0}
end
function S.command(actor,scopeId,jobId,action)
    local entry,reason=require('EmberRoutesProbe/SettlementLedger').view(actor,scopeId)
    if not entry then return reason or 'ACCESS_DENIED' end
    load()
    local job=Jobs.current():peek(jobId)
    if not job or job.providerType~='COOKING' or job.scopeId~=scopeId then return 'TASK_CHANGED' end
    if job.state=='DONE' or job.state=='CANCELLED' then return 'TASK_CHANGED' end
    if action=='resume' and job.effects~='KNOWN' then return 'COOKING_RECONCILE_REQUIRED' end
    local runtime=Runtime.current()
    local live=runtime and runtime:status(job.npcId,job.id)

    if action=='stop' then
        if live then runtime:stopJob(job.npcId,job.id,'USER_PAUSE') end
        local p=Record.copy(job.payload)
        p.pauseRequested=true
        p.reason='USER_PAUSE'
        local ok=Jobs.current():update(job.id,job.revision,{payload=p})
        Signals.changed(job.npcId)
        return ok and 'STOP_REQUESTED' or 'TASK_CHANGED'

    elseif action=='resume' then
        local p=Record.copy(job.payload)
        p.pauseRequested=nil
        p.cancelRequested=nil
        if p.reason=='USER_PAUSE' or p.reason=='EVOLVED_PROFILE_CHANGED' or p.reason=='COOKING_PROFILE_CHANGED' or p.reason=='USER_CANCEL' then
            p.reason=nil
        end
        local ok=Jobs.current():update(job.id,job.revision,{payload=p})
        if ok and job.state=='SUSPENDED' then
            retryJobs[job.id]=0
            S.wake(actor,job.npcId,job.id)
        end
        Signals.changed(job.npcId)
        return ok and 'ORDER_UPDATED' or 'TASK_CHANGED'

    elseif action=='return' then
        if live then
            local p=Record.copy(job.payload)
            p.cancelRequested=true
            p.reason='USER_CANCEL'
            Jobs.current():update(job.id,job.revision,{payload=p})
            runtime:stopJob(job.npcId,job.id,'USER_CANCEL')
            Signals.changed(job.npcId)
            return 'CANCEL_REQUESTED'
        end

        local hasHeld=false
        for _,asset in ipairs(job.payload.assets or {}) do
            if asset.custody=='HELD' then hasHeld=true break end
        end

        if hasHeld then
            local p=Record.copy(job.payload)
            p.cancelRequested=true
            p.reason='USER_CANCEL'
            Jobs.current():update(job.id,job.revision,{payload=p})
            retryJobs[job.id]=0
            recover(actor,job)
            Signals.changed(job.npcId)
            return 'CANCEL_REQUESTED'
        end

        local token=Store.claimCooking(job)
        if token then
            local c={job=job,token=token}
            local j=Record.copy(job)
            j.state='SETTLING'
            j.payload.claims={}
            local changed,saved,nextToken=Store.replaceCooking(c.job,c.token,j)
            if changed then
                j=Record.copy(saved)
                j.state='CANCELLED'
                j.payload.phase='SETTLED'
                j.payload.reason='USER_CANCEL'
                local ok,final,finalToken=Store.replaceCooking(saved,nextToken,j)
                if ok then
                    Store.finishCooking(final,finalToken)
                    Signals.changed(job.npcId)
                    return 'ORDER_UPDATED'
                end
            end
        else
            if #job.payload.claims==0 then
                local ok,revision=Jobs.current():update(job.id,job.revision,{state='SETTLING'})
                if ok then
                    local j=Jobs.current():get(job.id)
                    j.payload.phase='SETTLED'
                    j.payload.reason='USER_CANCEL'
                    Jobs.current():update(job.id,revision,{state='CANCELLED',payload=j.payload})
                    Signals.changed(job.npcId)
                    return 'ORDER_UPDATED'
                end
            end
        end
        return 'FAILED'
    end
    return 'INVALID_COMMAND'
end
-- Work owns command/removal lifecycle fan-out; Cooking keeps its original Job.
Work.registerExecutor('COOKING',{
    retains=S.retained,
    busy=function(id)
        local r=Runtime.current() local s=r and r:status(id)
        return s and s.kind=='COOKING' or false
    end,
    pause=function(reason,id)
        local r=Runtime.current() local s=r and r:status(id)
        if s and s.kind=='COOKING' then r:stopJob(id,s.jobId,reason) end
    end,
    pauseAll=function(reason)
        load() local r=Runtime.current() if not r then return end
        for _,id in ipairs(retained) do
            local j=Jobs.current():peek(id)
            if j and r:status(j.npcId,id) then r:stopJob(j.npcId,id,reason) end
        end
    end,
    reset=function() world=nil end})
S.provider={category='cooking',defaultPriority=3,discover=S.discover,claim=S.claim,
    advance=S.advance,reconcile=S.reconcile,hasWork=S.hasWork}
return S
