-- A retained book must not lock out survival care while its return route is
-- unavailable. This leaf uses only the borrower's own supplies and the same
-- Session/claims; it never releases or substitutes the borrowed original.
local Policy=require 'EmberRoutesProbe/NeedsPolicy'
local Observer=require 'EmberRoutesProbe/NeedsObserver'
local Resources=require 'EmberRoutesProbe/SelfCareResources'
local Store=require 'EmberRoutesProbe/LaborStore'
local Relief={}
function Relief.new(c)
    local child,context,request,requestKind,floorScan
    local leaf={kind='Action'}
    local function persist()
        local r=c.payload.relief
        r.fact=context.payload.consumption r.repose=context.payload.repose
        if context.effects=='UNKNOWN' then c.effects='UNKNOWN' end
        return c.persist()
    end
    function leaf.run()
        if child then
            context.budget=c.budget
            local state=child.run()
            if context.effects=='UNKNOWN' then c.effects='UNKNOWN' end
            if state~='Running' then
                c.payload.relief.finished=true
                if state=='Success' and c.payload.relief.floorSite then
                    local key=require('EmberRoutesProbe/FloorSleep').key(c.payload.relief.floorSite)
                    local kept={} for _,held in ipairs(c.payload.claims) do if held~=key then kept[#kept+1]=held end end
                    c.payload.claims=kept
                    if not persist() or not Store.releasePersonalSeats(c.job,c.token) then return 'Failure' end
                else persist() end
            end
            return state
        end
        local previous=c.payload.relief
        if previous and not previous.finished and (previous.fact and previous.fact.started
            and not (previous.fact.completed or previous.fact.stopped)
            or previous.repose and previous.repose.started and not previous.repose.finished) then
            c.effects='UNKNOWN' c.persist() return 'Failure'
        end
        local sample=Observer.sample(c.npc,c.job.npcId,getTimestampMs())
        if not sample or not sample.safe then return 'Failure' end
        local kind=Policy.choose(sample,nil,{safe=true},{EAT=true,DRINK=true,
            REST=EmberRoutesProbeJava.reposeWithControl~=nil,
            SLEEP=not c.payload.reliefOnly and EmberRoutesProbeJava.reposeWithControl~=nil})
        if not kind then return 'Success' end
        local candidate,floorSite
        if kind=='SLEEP' then
            local floor=require 'EmberRoutesProbe/FloorSleep'
            if not EmberRoutesProbeJava.floorSleepSafe then return 'Success' end
            floorScan=floorScan or floor.scan(c.npc,c.job.npcId)
            local slice=math.min(8,c.budget.scan) if slice<1 then return 'Running' end
            local done
            floorSite,done=floorScan:step(slice) c.budget.scan=c.budget.scan-slice
            if not done then return 'Running' end
            floorScan=nil
            if not floorSite then return 'Success' end
            if #c.payload.claims>=16 then return 'Success' end
            c.payload.claims[#c.payload.claims+1]=floor.key(floorSite)
            if not c.persist() or not Store.extendPersonal(c.job,c.token) then return 'Failure' end
        end
        if kind=='EAT' or kind=='DRINK' then
            if not request or requestKind~=kind then request=Resources.new(c.actor,c.npc,kind,true) requestKind=kind end
            if c.budget.scan<1 then return 'Running' end
            local slice=math.min(8,c.budget.scan) local done
            candidate,done=request:step(slice) c.budget.scan=c.budget.scan-slice
            if not done then return 'Running' end
            if not candidate or candidate.container~=c.npc:getInventory() then return 'Success' end
            local key='item:'..candidate.id local found=false
            for _,held in ipairs(c.payload.claims) do if held==key then found=true break end end
            if not found then
                if #c.payload.claims>=16 then c.reason='PERSONAL_CLAIM_LIMIT' return 'Success' end
                c.payload.claims[#c.payload.claims+1]=key
                if not c.persist() or not Store.extendPersonal(c.job,c.token) then return 'Failure' end
            end
            c.items[candidate.id]=candidate.item
        end
        local sequence=(previous and previous.sequence or 0)+1
        c.payload.relief={sequence=sequence,kind=kind,itemId=candidate and candidate.id,finished=false,floorSite=floorSite}
        context={npc=c.npc,actor=c.actor,job=c.job,effects='KNOWN',body=c.body,
            sameAttempt=c.sameAttempt,valid=c.valid,canConsume=c.canConsume,claimOutputs=c.claimOutputs,
            payload={kind=kind,attemptId=c.payload.attemptId..':relief:'..sequence,floorSite=floorSite}}
        context.persist=persist
        if not persist() then return 'Failure' end
        if candidate then
            local fraction=kind=='EAT' and math.min(1,math.max(0.05,(sample.hunger-0.08)/-candidate.item:getHungChange())) or 0.5
            child=require('EmberRoutesProbe/SelfCareActions').consumption(context,kind,candidate.item,fraction)
        elseif floorSite then
            local tree=require 'EmberRoutesProbe/BehaviorTree'
            local program=assert(tree.new({kind='Sequence',children={require('EmberRoutesProbe/FloorSleep').move(context),
                require('EmberRoutesProbe/SelfCareRepose').new(context)}}))
            child={run=function() return tree.tick(program,context,c.budget) end,halt=function() return tree.halt(program,context) end}
        else child=require('EmberRoutesProbe/SelfCareRepose').new(context) end
        return 'Running'
    end
    function leaf.halt()
        if child then
            local stopped=child.halt()
            if context.effects=='UNKNOWN' then c.effects='UNKNOWN' end
            c.payload.relief.finished=stopped==true persist()
            return stopped
        end
        return true
    end
    return leaf
end
return Relief
