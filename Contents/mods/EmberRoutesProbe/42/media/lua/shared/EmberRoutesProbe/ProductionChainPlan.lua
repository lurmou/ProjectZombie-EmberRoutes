-- Pure bounded search. Simulation never changes or claims a physical item.
local Chain={maxDepth=4,maxNodes=64,maxSteps=40000,maxClaims=256,maxQuantity=9999}
local function copy(t) local r={} for k,v in pairs(t) do r[k]=v end return r end
local function fork(s)
    local r={used=copy(s.used),locked=copy(s.locked),selected=copy(s.selected),nodes={},pending={},stock=s.stock,extra={}}
    for i,v in ipairs(s.nodes) do r.nodes[i]=v end
    for i,v in ipairs(s.pending) do r.pending[i]=v end
    for i,v in ipairs(s.extra) do r.extra[i]=v end
    r.localUsed={} for k,v in pairs(s.localUsed) do r.localUsed[k]=copy(v) end
    r.allocationAlternative=s.allocationAlternative
    return r
end
local function push(s,c) s.pending[#s.pending+1]=c end
local function accepts(input,item)
    if item.npcOnly and not input.keep then return false end
    if not input.types[item.fullType] then return false end
    return not item.item or not input.accept or input.accept(item.item)
end
local function allocate(s,c,key,item,n)
    if n<=0 then return end
    if c.input.keep then
        local used=(s.localUsed[c.tag][key] or 0)+n
        s.localUsed[c.tag][key]=used s.locked[key]=math.max(s.locked[key] or 0,used)
    else s.used[key]=(s.used[key] or 0)+n end
    if item.id then s.selected[item.id]={id=item.id,fullType=item.fullType} end
end
function Chain.new(recipe,quantity,stock,producers,resolve)
    local initial={used={},locked={},selected={},nodes={},pending={},stock=stock,extra={},localUsed={}}
    push(initial,{kind="recipe",recipe=recipe,times=math.ceil(quantity/recipe.yield),depth=1,path={}})
    local self={frontier={initial},steps=0,serial=0}
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
                    local path=copy(c.path) path[r.id]=true s.localUsed[tag]={}
                    push(s,{kind="emit",recipe=r,times=c.times,tag=tag})
                    local inputs={} for i,input in ipairs(r.inputs) do inputs[i]=input end
                    -- Constrained slots first; physical execution still rechecks native IO predicates.
                    table.sort(inputs,function(a,b)
                        if #a.choices~=#b.choices then return #a.choices<#b.choices end
                        if a.keep~=b.keep then return a.keep end return a.slot<b.slot
                    end)
                    for i=#inputs,1,-1 do
                        local input=inputs[i]
                        push(s,{kind="need",input=input,remaining=input.count*(input.keep and 1 or c.times),
                            index=1,depth=c.depth,path=path,tag=tag})
                    end
                end
            elseif c.kind=="emit" then
                if #s.nodes>=Chain.maxNodes then failure("CHAIN_PLAN_LIMIT")
                else
                    local r=c.recipe
                    local totalOutput=0 for _,n in pairs(r.outputs) do totalOutput=totalOutput+n*c.times end
                    s.nodes[#s.nodes+1]={recipeId=r.id,signature=r.signature,product=r.product,recipeName=r.name,
                        requested=c.times*r.yield,totalOutput=totalOutput,unitYield=r.yield,surface=r.surface,benchId=r.benchId,location=r.location}
                    for kind,n in pairs(r.outputs) do s.extra[#s.extra+1]={fullType=kind,count=n*c.times} end
                    s.localUsed[c.tag]=nil
                end
            elseif c.kind=="need" then
                local input=c.input local item
                if c.index<=#s.stock then item=s.stock[c.index] else item=s.extra[c.index-#s.stock] end
                if item then
                    local available=(item.count or 1)-(s.used[c.index] or 0)
                    if input.keep then available=available-(s.localUsed[c.tag][c.index] or 0)
                    else available=available-(s.locked[c.index] or 0) end
                    local take=math.min(c.remaining,math.max(0,available))
                    if take>0 and accepts(input,item) then
                        -- Defer other allocations as well as other recipes. A flexible slot must
                        -- not permanently consume the only original a later branch can use.
                        for amount=0,take-1 do
                            if #self.frontier>=128 then self.truncated=true break end
                            local alternative=fork(s) alternative.allocationAlternative=true allocate(alternative,c,c.index,item,amount)
                            local retry=copy(c) retry.index=c.index+1 retry.remaining=c.remaining-amount
                            push(alternative,retry) self.frontier[#self.frontier+1]=alternative
                        end
                        allocate(s,c,c.index,item,take)
                        c=copy(c) c.remaining=c.remaining-take
                    end
                    if c.remaining>0 then c=copy(c) c.index=c.index+1 push(s,c) end
                else
                    local candidates,seen={},{}
                    for _,kind in ipairs(input.choices) do
                        for _,r in ipairs(producers[kind] or {}) do
                            if not seen[r.id] then
                                local times=math.ceil(c.remaining/r.outputs[kind])
                                candidates[#candidates+1]={recipe=r,times=times}
                                if times>1 then candidates[#candidates+1]={recipe=r,times=1} end
                                seen[r.id]=true
                            end
                        end
                    end
                    if #candidates==0 then failure(input.keep and "TOOLS_UNAVAILABLE" or "MATERIALS_UNAVAILABLE",input)
                    elseif #candidates>64 then failure("CHAIN_PLAN_LIMIT",input)
                    else
                        -- Each alternative owns its simulation changes. Failed branches cannot leak consumption.
                        for i=#candidates,1,-1 do
                            local candidate=candidates[i] local child=fork(s)
                            local retry=copy(c) retry.index=1 push(child,retry)
                            push(child,{kind="recipe",recipe=candidate.recipe,
                                times=candidate.times,depth=c.depth+1,path=c.path})
                            if #self.frontier>=128 then table.remove(self.frontier,1) self.truncated=true end
                            self.frontier[#self.frontier+1]=child
                        end
                        self.state=nil
                    end
                end
            end
        end
    end
    return self
end
return Chain
