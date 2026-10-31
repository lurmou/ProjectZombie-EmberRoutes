-- Per-instance native adapter, patterned after CookingActions. No private queue.
local A={}
function A.new(c,h)
    local action,stopped,performed,committing
    local a=c.job.payload.attempt
    if a and (a.state=='UNKNOWN' or a.state=='PREPARED' and a.dispatched) then return nil,'FIELD_ATTEMPT_RECONCILE_REQUIRED' end
    local sequence=c.job.payload.sequence+1
    if not c.change(function(j)
        j.payload.sequence=sequence
        j.payload.attempt={id=j.id..':'..sequence,kind=h.kind,state='PREPARED',dispatched=false}
    end) then return nil,'FIELD_JOB_CHANGED' end
    local id=c.job.payload.attempt.id
    local function same() return c.same() and c.job.payload.attempt and c.job.payload.attempt.id==id end
    local function active() return same() and not c.stopping and c.body.current() and c.valid() end
    local function state() return same() and c.job.payload.attempt.state end
    local function classify(ok,finished)
        if not same() then return false end
        local known,applied,continuing=h.observe(ok,finished)
        return c.change(function(j)
            j.effects=known and 'KNOWN' or 'UNKNOWN'
            j.payload.attempt.state=known and (applied and 'APPLIED' or continuing and 'PREPARED' or 'ABORTED') or 'UNKNOWN'
        end)
    end
    local function effect(self,native,...)
        if not active() or committing or state()=='APPLIED' or state()=='ABORTED' then return false end
        if h.valid and not h.valid() then return false end
        if h.before and not h.before() then c.unknown('FIELD_BEFORE_EFFECT_FAILED') return false end
        if not c.change(function(j) j.effects='UNKNOWN' end) then return false end
        committing=true
        local ok,result
        if h.invoke then ok,result=pcall(h.invoke,native,self,...)
        else ok,result=pcall(native,self,...) end
        local observed,why=pcall(classify,ok,not h.progressive)
        committing=false
        if not observed then c.unknown(why) end
        if not ok then c.reason=tostring(result) end
        return ok and result
    end
    local node={}
    function node.settle()
        if not same() or committing then return false end
        if state()=='PREPARED' or c.job.effects=='UNKNOWN' then
            if not classify(true,true) then return false end
        end
        -- Native complete may deposit originals before perform retires ecology.
        -- A stopped queue cannot turn that partial transaction into settled work.
        if state()=='APPLIED' and h.afterPerform and not h.afterPerform() then
            return c.unknown('FIELD_FINALIZE_UNCONFIRMED')
        end
        return true
    end
    function node.run()
        if not same() then return 'Failure' end
        if not action then
            if not active() then return 'Failure' end
            if not c.change(function(j) j.payload.attempt.dispatched=true end) then return 'Failure' end
            action=h.create()
            if not action then node.settle() return 'Failure' end
            local valid,start,update,perform,stop=action.isValid,action.start,action.update,action.perform,action.stop
            action.isValid=function(self) return active() and (not h.valid or h.valid()) and valid(self) end
            action.start=function(self)
                if not self:isValid() then return end
            if h.startEffect then
                    if not c.change(function(j) j.effects='UNKNOWN' end) then return end
                end
                start(self)
            end
            action.update=function(self)
                if not active() or h.valid and not h.valid() then return end
                if h.willUpdate and h.willUpdate(self) then return effect(self,update) end
                update(self)
            end
            if h.progressive then
                -- Updates/animation events may mutate water, axe, tree and stats.
                local anim=action.animEvent
                if anim then action.animEvent=function(self,...) if active() then return effect(self,anim,...) end end end
            end
            if h.transfer then
                local transfer=action.transferItem
                action.canMergeAction=function() return false end
                action.checkQueueList=function() end
                action.transferItem=function(self,item) if item==h.transfer then return effect(self,transfer,item) end return false end
                local anim=action.startActionAnim
                if anim then action.startActionAnim=function(self) if active() then anim(self) self.selectedContainer=nil end end end
            elseif action.complete then
                local complete=action.complete
                action.complete=function(self) return effect(self,complete) end
            end
            action.perform=function(self)
                if performed or stopped or not c.body.retained() or not same() then return end
                performed=true
                if h.performEffect then return effect(self,perform) end
                local ok,why
                if h.invoke then ok,why=pcall(h.invoke,perform,self)
                else ok,why=pcall(perform,self) end
                if not ok then c.unknown(why)
                elseif h.afterPerform and not h.afterPerform() then c.unknown('FIELD_FINALIZE_UNKNOWN') end
            end
            action.stop=function(self)
                if stopped or committing or not c.body.retained() or not same() then return end
                stopped=true stop(self)
            end
            action.useProgressBar,action.forceProgressBar=false,false
            if not c.body.add(action) then node.settle() return 'Failure' end
        end
        if committing or ISTimedActionQueue.hasAction(action) then return 'Running' end
        if not node.settle() then return 'Failure' end
        return state()=='APPLIED' and 'Success' or 'Failure'
    end
    return node
end
return A
