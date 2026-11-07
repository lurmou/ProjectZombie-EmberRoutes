-- Pure bounded search. Simulation never changes or claims a physical item.
local Chain={maxDepth=4,maxNodes=64,maxSteps=40000,maxClaims=256,maxQuantity=9999}
local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
local function fork(s)
    local r={used=copy(s.used),locked=copy(s.locked),selected=copy(s.selected),nodes={},pending={},stock=s.stock,extra={},
        fluidUsed=copy(s.fluidUsed),fluidLocks={},fluidBatches={},allocations={}}
    for i,v in ipairs(s.nodes) do r.nodes[i]=v end
    for i,v in ipairs(s.pending) do r.pending[i]=v end
    for i,v in ipairs(s.extra) do r.extra[i]=v end
    r.localUsed={} for k,v in pairs(s.localUsed) do r.localUsed[k]=copy(v) end
    for k,v in pairs(s.fluidLocks) do r.fluidLocks[k]=copy(v) end
    for k,v in pairs(s.fluidBatches) do r.fluidBatches[k]=copy(v) end
    for k,v in pairs(s.allocations) do r.allocations[k]={} for i,row in ipairs(v) do r.allocations[k][i]=row end end
    r.allocationAlternative=s.allocationAlternative
    return r
end
local function push(s,c) s.pending[#s.pending+1]=c end
local function accepts(input,item)
    if item.npcOnly and not input.keep then return false end
    if not input.any and not input.types[item.fullType] then return false end
    -- Simulated item outputs have no observed liquid. Never invent filled carriers.
    if input.fluid and (not item.id or not item.fluidAmount) then return false end
    return not item.item or not input.accept or input.accept(item.item)
end
local function allocate(s,c,key,item,n)
    if n<=0 then return end
    if c.input.fluid then
        s.fluidUsed[key]=(s.fluidUsed[key] or 0)+c.input.fluid.amount
        s.locked[key]=math.max(s.locked[key] or 0,1)
        s.fluidLocks[c.tag][key]=true
        s.fluidBatches[c.tag][c.batch..':'..key]=true
    elseif c.input.keep then
        local used=(s.localUsed[c.tag][key] or 0)+n
        s.localUsed[c.tag][key]=used s.locked[key]=math.max(s.locked[key] or 0,used)
    else s.used[key]=(s.used[key] or 0)+n end
    if item.id then s.selected[item.id]={id=item.id,fullType=item.fullType} end
    if c.input.fluid then
        local rows=s.allocations[c.tag]
        rows[#rows+1]={slot=c.input.slot,batch=c.batch,itemId=item.id,unit='FLUID_VOLUME',amount=c.input.fluid.amount}
    end
end
function Chain.new(recipe,quantity,stock,producers,resolve,preferences)
    local initial={used={},locked={},selected={},nodes={},pending={},stock=stock,extra={},localUsed={},
        fluidUsed={},fluidLocks={},fluidBatches={},allocations={}}
    push(initial,{kind="recipe",recipe=recipe,times=math.ceil(quantity/recipe.yield),depth=1,path={}})
    local self={frontier={initial},steps=0,serial=0,preferences=preferences}
    local function failure(reason,input,recipe)
        local priority=reason=="CHAIN_PLAN_LIMIT" and 5 or reason=="CHAIN_CYCLE" and 1
            or reason=="CHAIN_DEPTH_LIMIT" and 2 or (reason=="MATERIALS_UNAVAILABLE" or reason=="TOOLS_UNAVAILABLE") and 3 or 4
        if not self.failure or (not self.state.allocationAlternative and priority>self.failure.priority) then
            self.failure={reason=reason,missing=input and input.choices,priority=priority,
                recipeId=recipe and recipe.id,recipeName=recipe and recipe.name,surfaceId=recipe and recipe.benchId}
        end
        self.state=nil
    end
    local function complete()
        self.done=true self.result={nodes=self.state.nodes,assets={},claims=0}
        local intermediates=0
        for i,node in ipairs(self.result.nodes) do
            if i<#self.result.nodes then intermediates=intermediates+(node.totalOutput or node.requested) end
        end
        for _,asset in pairs(self.state.selected) do
            self.result.claims=self.result.claims+1 self.result.assets[#self.result.assets+1]=asset
        end
        if self.result.claims+intermediates>Chain.maxClaims then self.result=nil self.reason="CHAIN_PLAN_LIMIT" end
    end
    function self:step(budget)
        if self.done then return self.result,self.reason end
        for _=1,budget or 32 do
            self.steps=self.steps+1
            if self.steps>Chain.maxSteps then self.done=true self.reason="CHAIN_PLAN_LIMIT" return nil,self.reason end
            if not self.state then self.state=table.remove(self.frontier) end
            local s=self.state
            if not s then
                self.done=true self.reason=self.truncated and "CHAIN_PLAN_LIMIT" or self.failure and self.failure.reason or "MATERIALS_UNAVAILABLE"
                self.missing=self.failure and self.failure.missing return nil,self.reason
            end
            local c=table.remove(s.pending)
            if not c then complete() return self.result,self.reason end
            if c.kind=="recipe" then
                local r=resolve and resolve(c.recipe) or c.recipe
                if c.depth>Chain.maxDepth then failure("CHAIN_DEPTH_LIMIT")
                elseif c.path[r.id] then failure("CHAIN_CYCLE")
                elseif r.reason then failure(r.reason,nil,r)
                elseif #s.nodes+#s.pending>Chain.maxNodes*20 or c.times*r.yield>9999 then failure("CHAIN_PLAN_LIMIT")
                else
                    self.serial=self.serial+1 local tag=self.serial
                    local path=copy(c.path) path[r.id]=true s.localUsed[tag]={} s.fluidLocks[tag]={} s.fluidBatches[tag]={} s.allocations[tag]={}
                    push(s,{kind="emit",recipe=r,times=c.times,tag=tag})
                    local inputs={} for i,input in ipairs(r.inputs) do inputs[i]=input end
                    -- Constrained slots first; physical execution still rechecks native IO predicates.
                    table.sort(inputs,function(a,b)
                        if #a.choices~=#b.choices then return #a.choices<#b.choices end
                        if a.keep~=b.keep then return a.keep end return a.slot<b.slot
                    end)
                    for i=#inputs,1,-1 do
                        local input=inputs[i]
                        if input.fluid then
                            -- Each native call needs one whole carrier. Enumeration remains sliced.
                            push(s,{kind='fluid-batches',input=input,batch=c.times,depth=c.depth,path=path,tag=tag})
                        else
                            push(s,{kind="need",input=input,remaining=input.count*(input.keep and 1 or c.times),
                                index=1,depth=c.depth,path=path,tag=tag})
                        end
                    end
                end
            elseif c.kind=="emit" then
                if #s.nodes>=Chain.maxNodes then failure("CHAIN_PLAN_LIMIT")
                else
                    local r=c.recipe
                    local totalOutput=0 for _,n in pairs(r.outputs) do totalOutput=totalOutput+n*c.times end
                    s.nodes[#s.nodes+1]={recipeId=r.id,signature=r.signature,product=r.product,recipeName=r.name,
                        requested=c.times*r.yield,totalOutput=totalOutput,unitYield=r.yield,surface=r.surface,benchId=r.benchId,location=r.location,
                        fluidInputs=s.allocations[c.tag]}
                    for kind,n in pairs(r.outputs) do s.extra[#s.extra+1]={fullType=kind,count=n*c.times} end
                    s.localUsed[c.tag]=nil
                    s.fluidLocks[c.tag]=nil s.fluidBatches[c.tag]=nil s.allocations[c.tag]=nil
                end
            elseif c.kind=='fluid-batches' then
                if c.batch>Chain.maxClaims or #s.allocations[c.tag]>=Chain.maxClaims then failure('CHAIN_PLAN_LIMIT',c.input)
                else
                    local need=copy(c) need.kind='need' need.remaining=1 need.index=1
                    if c.batch>1 then local rest=copy(c) rest.batch=c.batch-1 push(s,rest) end
                    push(s,need)
                end
            elseif c.kind=="allocate" then
                -- One alternative fork per operation, including large stacks
                -- of simulated intermediate products. Never expand 128 at once.
                local command=c.command
                if c.amount<c.take and #self.frontier<128 then
                    local alternative=fork(s) alternative.allocationAlternative=true
                    allocate(alternative,command,command.index,c.item,c.amount)
                    local retry=copy(command) retry.index=command.index+1 retry.remaining=command.remaining-c.amount
                    push(alternative,retry) self.frontier[#self.frontier+1]=alternative
                    c.amount=c.amount+1 push(s,c)
                else
                    if c.amount<c.take then self.truncated=true end
                    allocate(s,command,command.index,c.item,c.take)
                    local retry=copy(command) retry.remaining=command.remaining-c.take retry.index=command.index+1
                    if retry.remaining>0 then push(s,retry) end
                end
            elseif c.kind=="discover" then
                -- Producer enumeration is also resumable, even when a mod adds
                -- many recipes yielding the same type.
                local input=c.command.input local kind=input.choices[c.choice]
                if not kind then
                    if #c.candidates==0 then failure(input.keep and "TOOLS_UNAVAILABLE" or "MATERIALS_UNAVAILABLE",input)
                    else push(s,{kind="branches",command=c.command,candidates=c.candidates,index=#c.candidates}) end
                else
                    local r=(producers[kind] or {})[c.index]
                    if not r then c.choice=c.choice+1 c.index=1
                    else
                        c.index=c.index+1
                        if not c.seen[r.id] then
                            c.seen[r.id]=true
                            local times=math.ceil(c.command.remaining/r.outputs[kind])
                            local preferredId=self.preferences and self.preferences[kind]
                            local candidate={recipe=r,times=times}
                            if r.id==preferredId then table.insert(c.candidates,1,candidate) else c.candidates[#c.candidates+1]=candidate end
                            if times>1 then
                                local single={recipe=r,times=1}
                                if r.id==preferredId then table.insert(c.candidates,2,single) else c.candidates[#c.candidates+1]=single end
                            end
                        end
                    end
                    if #c.candidates>64 then failure("CHAIN_PLAN_LIMIT",input) else push(s,c) end
                end
            elseif c.kind=="branches" then
                local candidate=c.candidates[c.index] local command=c.command
                local child=fork(s) local retry=copy(command) retry.index=1 push(child,retry)
                push(child,{kind="recipe",recipe=candidate.recipe,times=candidate.times,depth=command.depth+1,path=command.path})
                if #self.frontier>=128 then table.remove(self.frontier,1) self.truncated=true end
                self.frontier[#self.frontier+1]=child c.index=c.index-1
                if c.index>0 then push(s,c) else self.state=nil end
            elseif c.kind=="need" then
                local input=c.input local item
                if c.index<=#s.stock then item=s.stock[c.index] else item=s.extra[c.index-#s.stock] end
                if item then
                    local available=(item.count or 1)-(s.used[c.index] or 0)
                    if input.fluid then
                        local inBatch=s.fluidBatches[c.tag][c.batch..':'..c.index]
                        available=math.min(available,1)-(s.localUsed[c.tag][c.index] or 0)-(inBatch and 1 or 0)
                        if not item.fluidAmount or item.fluidAmount-(s.fluidUsed[c.index] or 0)<input.fluid.amount then available=0 end
                    elseif input.keep then available=available-(s.localUsed[c.tag][c.index] or 0)-(s.fluidLocks[c.tag][c.index] and 1 or 0)
                    else available=available-(s.locked[c.index] or 0) end
                    local take=math.min(c.remaining,math.max(0,available))
                    if take>0 and accepts(input,item) then
                        -- Defer other allocations as well as other recipes. A flexible slot must
                        -- not permanently consume the only original a later branch can use.
                        push(s,{kind="allocate",command=c,item=item,take=take,amount=0})
                    elseif c.remaining>0 then c=copy(c) c.index=c.index+1 push(s,c) end
                else
                    if input.fluid then failure('MATERIALS_UNAVAILABLE',input)
                    else push(s,{kind="discover",command=c,choice=1,index=1,candidates={},seen={}}) end
                end
            end
        end
    end
    return self
end
return Chain
