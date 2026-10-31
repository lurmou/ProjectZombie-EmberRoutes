-- Pure continuation facts. Never owns items or releases a body/claim.
local Y={}
local function integer(n,max) return type(n)=='number' and n==n and n>=0 and n<=max and n==math.floor(n) end
local function id(s) return type(s)=='string' and #s>0 and #s<=256 end
local function emptyAssets(r)
    for _,name in ipairs({'materials','tools','outputs','held'}) do
        for _ in pairs(r[name] or {}) do return false end
    end
    return true
end
local function goalValid(g)
    if type(g)~='table' then return false end
    for _,key in ipairs({'recipeId','recipeName','product','signature'}) do if type(g[key])~='string' then return false end end
    return integer(g.requested,9999) and g.requested>0 and integer(g.target,10030) and g.target>=g.requested
        and integer(g.unitYield,32) and g.unitYield>0
end
function Y.continuation(r)
    local c=r.activityContinuation
    return c==nil or type(c)=='table' and c.format==1 and goalValid(c.goal)
        and integer(c.delivered,c.goal.target) and integer(c.resumeEpoch,9007199254740000)
        and integer(c.membershipRevision,9007199254740000) and c.membershipRevision>0
end
function Y.assetFree(r)
    local y=r.activityYield
    return (r.format==3 or r.format==4) and not r.uncertain and type(y)=='table' and y.kind=='MANUAL' and y.cleared==true
        and r.unitMade~=true and emptyAssets(r) and r.activityContinuation~=nil and Y.continuation(r) or false
end
function Y.goal(r)
    if r.chain==nil then return r end
    return type(r.chain)=='table' and type(r.chain.goal)=='table' and r.chain.goal or nil
end
function Y.final(r)
    return not r.chain or type(r.chain)=='table' and type(r.chain.nodes)=='table'
        and #r.chain.nodes>0 and r.chain.index==#r.chain.nodes
end
function Y.valid(r)
    if not Y.continuation(r) then return false end
    local y=r.activityYield if y==nil then return true end
    local g=Y.goal(r)
    local kind=type(y)=='table' and (y.kind or 'PUBLIC')
    return g~=nil and type(y)=='table' and y.format==1 and id(y.eventId)
        and (kind=='PUBLIC' and id(r.orderId) or kind=='MANUAL' and r.orderId==nil
            and integer(y.ownerEpoch,9007199254740000) and integer(y.membershipRevision,9007199254740000)
            and y.membershipRevision>0 and (y.cleared==nil or y.cleared==false or Y.assetFree(r)))
        and y.recipeId==g.recipeId and y.product==g.product
        and (y.cancelled==nil or type(y.cancelled)=='boolean')
end
function Y.request(r,ref)
    if r.activityYield or r.uncertain or not r.orderId and r.origin or not ref or ref.settlementId~=r.settlementId
        or not id(ref.eventId) or Y.final(r) and r.produced>=r.target then return false end
    local g=Y.goal(r) if not g then return false end
    if not r.orderId and (not integer(ref.commandEpoch,9007199254740000)
        or not integer(ref.membershipRevision,9007199254740000) or ref.membershipRevision<1) then return false end
    r.activityYield={format=1,eventId=ref.eventId,recipeId=g.recipeId,product=g.product,
        kind=r.orderId and 'PUBLIC' or 'MANUAL',ownerEpoch=ref.commandEpoch,membershipRevision=ref.membershipRevision}
    return true
end
function Y.delivered(r)
    if not Y.final(r) then return 0 end -- BOM intermediates are stock, not final-demand credit.
    local g=Y.goal(r)
    if not g or r.recipeId~=g.recipeId or r.product~=g.product then return nil end
    return integer(r.delivered,r.target) and r.delivered or nil
end
function Y.progress(value,target)
    return value==nil or type(value)=='table' and value.format==1
        and integer(value.delivered,target) and id(value.settledJobId)
end
function Y.remaining(order)
    return math.max(0,order.quantity-(order.craftProgress and order.craftProgress.delivered or 0))
end
function Y.copy(value)
    return value and {format=1,delivered=value.delivered,settledJobId=value.settledJobId} or nil
end
-- Caller applies this patch to its unique order before publishing a signal.
-- The current jobId plus one last-settled ID bounds receipts without a history ledger.
function Y.settle(order,r)
    if not r.activityYield and not order.craftProgress then return nil end
    if order.jobId~=r.id or r.orderId~=order.id or r.settlementId~=order.settlementId or not r.released or r.uncertain
        or r.state~='DONE' and r.state~='CANCELLED' or not Y.valid(r)
        or not Y.progress(order.craftProgress,order.target) then return nil,'RECONCILE_REQUIRED' end
    local g=Y.goal(r)
    if not g or g.recipeId~=order.recipeId or g.product~=order.product then return nil,'RECONCILE_REQUIRED' end
    local old=order.craftProgress
    if old and old.settledJobId==r.id then return nil,'RECONCILE_REQUIRED' end
    local credit=Y.delivered(r) if credit==nil then return nil,'RECONCILE_REQUIRED' end
    local total=math.min(order.target,(old and old.delivered or 0)+credit)
    local cancelled=order.state=='CANCELLED' or order.cancelRequested
        or r.activityYield and r.activityYield.cancelled or r.state=='CANCELLED' and not r.activityYield
    local state=cancelled and 'CANCELLED' or total>=order.quantity and 'DONE'
        or r.activityYield and 'WAITING' or 'CANCELLED'
    return {state=state,progress={format=1,delivered=total,settledJobId=r.id}}
end
local function copyGoal(g)
    local o={}
    for _,key in ipairs({'recipeId','recipeName','product','signature','requested','target','unitYield'}) do o[key]=g[key] end
    o.produced=0 o.delivered=0 o.benchId=g.benchId
    if g.surface then o.surface={x=g.surface.x,y=g.surface.y,z=g.surface.z} end
    return o
end
-- Called only after the existing return-only executor proved every original returned.
function Y.manualPlan(r)
    local y=r.activityYield
    if not y or y.kind~='MANUAL' or y.cancelled or r.uncertain then return nil end
    local credit=Y.delivered(r) if credit==nil then return nil,'RECONCILE_REQUIRED' end
    local old=r.activityContinuation
    local goal=copyGoal(old and old.goal or Y.goal(r))
    if not old then
        local node=r.chain and r.chain.nodes[#r.chain.nodes]
        goal.benchId=node and node.benchId or r.benchId
        local site=node and node.location or r.surface
        goal.surface=site and {x=site.x,y=site.y,z=site.z} or nil
    end
    local total=math.min(goal.target,(old and old.delivered or 0)+credit)
    local remaining=goal.requested-total
    if remaining<=0 then return {complete=true} end
    local nextGoal=copyGoal(goal) nextGoal.requested=remaining nextGoal.target=math.ceil(remaining/goal.unitYield)*goal.unitYield
    local marker={} for k,v in pairs(y) do marker[k]=v end marker.cleared=true
    return {complete=false,goal=nextGoal,marker=marker,
        continuation={format=1,goal=goal,delivered=total,resumeEpoch=y.ownerEpoch,membershipRevision=y.membershipRevision}}
end
function Y.applyManual(r,plan)
    local g=plan.goal
    for _,key in ipairs({'recipeId','recipeName','product','signature','requested','target','unitYield','benchId','surface'}) do r[key]=g[key] end
    r.produced=0 r.delivered=0 r.unitMade=false r.materials={} r.tools={} r.outputs={}
    if r.chain then
        r.chain={format=1,index=0,nodes={},goal=copyGoal(g)} r.held={}
    end
    r.state='PAUSED' r.phase='PLANNING' r.reason='ACTIVITY_YIELD' r.released=false
    r.activityContinuation=plan.continuation r.activityYield=plan.marker
end
return Y
