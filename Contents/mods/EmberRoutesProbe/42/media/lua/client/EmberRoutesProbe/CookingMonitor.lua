-- Cooking's canonical Job projection and command routing. No independent ledger.
local M={providerType='COOKING'}
local custodyStates={SOURCE='UNCOLLECTED',HELD='WITHDRAWN',STATION='STATION',WORLD='UNCOLLECTED',
    UNKNOWN='RECONCILE',DELIVERED='STORED',RETURNED='RETURNED',CONSUMED='CONSUMED'}
function M.project(context,j)
    local runtime=context.runtime
    local p=j.payload
    local request=p.source=='REQUEST' and require('EmberRoutesProbe/CookingOrders').get(p.sourceId)
    local control=runtime and runtime:status(j.npcId,j.id)
    local attempt=p.attempt
    local pouring=control and control.state=='ACTIVE' and attempt and attempt.state=='COMMITTING'
        and (attempt.kind=='WATER' or attempt.kind=='FLUID')
    local binding=context.bind(j.npcId)
    local closed=(j.state=='DONE' or j.state=='CANCELLED') and j.effects=='KNOWN'
    local state=control and control.state=='STOPPING' and 'STOPPING' or j.state
    local row={id=request and 'ORDER:'..request.id or 'COOKING:'..j.id,jobId=j.id,
        orderId=request and request.id,kind=request and 'ORDER' or 'COOKING',npcId=j.npcId,
        generation=request and 'ORDER:'..request.revision or j.revision,
        name=require('EmberRoutesProbe/DisplayNames').name(j.npcId,binding and binding.handle),
        title=request and request.name or getText('IGUI_EmberRoutesProbe_Public_cooking'),
        product=request and request.product,state=state,phase=p.phase,reason=p.reason,
        closed=closed,uncertain=j.effects~='KNOWN' and not pouring,carrierAvailable=binding~=nil,
        bodyMode=control and 'COOKING' or 'HOLD',
        bucket=closed and 'closed' or j.effects~='KNOWN' and not pouring and 'attention' or control and 'active' or 'waiting',
        requested=request and request.quantity or 1,target=request and request.target or 1,
        delivered=request and request.delivered or 0,produced=0,nodes={},assets={},
        canPause=not closed and (request and not request.pauseRequested or not request and (state=='RUNNING' or state=='PREPARING' or control~=nil)),
        canResume=not closed and j.effects=='KNOWN' and binding~=nil and not (control and control.state=='STOPPING') and (request and request.pauseRequested==true or not request and (state=='PAUSED' or state=='SUSPENDED')),
        canCancel=not closed and (request and not request.cancelRequested or not request and not p.cancelRequested)}
    for _,asset in ipairs(p.assets) do
        row.assets[#row.assets+1]={id=asset.id,fullType=asset.fullType,
            kind=asset.role=='OUTPUT' and 'outputs' or asset.role=='TOOL' and 'tools' or 'materials',
            delivered=asset.custody=='DELIVERED',held=asset.custody=='HELD',
            custodyState=custodyStates[asset.custody]}
        if asset.role=='OUTPUT' then
            row.product=row.product or asset.fullType
            -- OUTPUT identifies the retained original, not completed food.
            if p.heat and p.heat.closed and not p.heat.aborted then row.produced=row.produced+1 end
        end
    end
    row.membership=require('EmberRoutesProbe/MembershipService').view(j.npcId)
    return row
end
function M.command(context,row,action)
    if row.orderId then
        return require('EmberRoutesProbe/PublicWork').command(context.actor,context.scopeId,row.orderId,
            tonumber(string.sub(row.generation,7)),action)
    end
    return require('EmberRoutesProbe/CookingService').command(context.actor,context.scopeId,row.jobId,action)
end
return M
