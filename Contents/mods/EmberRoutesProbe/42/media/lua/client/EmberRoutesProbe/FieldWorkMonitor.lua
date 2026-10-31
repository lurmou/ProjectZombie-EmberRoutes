-- Detached facts only. Known failures are retried by FieldWork, never by a UI command.
local M={providerType='FIELD_WORK'}
local stageKeys={'IGUI_EmberRoutesProbe_Monitor_fieldWork','IGUI_EmberRoutesProbe_Monitor_fieldCollect',
    'IGUI_EmberRoutesProbe_Monitor_fieldDeliver'}
local phaseIndex={WORK=1,COLLECT=2,DELIVER=3,SETTLED=4}
local reasons={FIELD_STORAGE_UNAVAILABLE='fieldStorage',FIELD_CAPACITY_UNAVAILABLE='fieldStorage',
    FIELD_CARRY_FULL='fieldCarry',FIELD_ITEM_TOO_HEAVY='fieldCarry',
    FIELD_TOOL_MISSING='fieldTools',FIELD_TOOLS_UNAVAILABLE='fieldTools',
    FIELD_CONTEXT_CHANGED='fieldContext',MEMBERSHIP_COMMAND='fieldContext',REPLACED='fieldContext',
    FIELD_TARGET_UNLOADED='fieldUnloaded',FIELD_OUTPUT_UNLOADED='fieldUnloaded',
    FIELD_WASTE_SOURCE_UNAVAILABLE='fieldUnloaded',FIELD_NO_APPROACH='fieldPath',
    FIELD_CORPSE_ZONE_REQUIRED='fieldCorpseZone',FIELD_FINALIZE_UNCONFIRMED='fieldFinalize',
    FIELD_GROUND_ORIGINAL_MISSING='fieldOriginal',FIELD_HELD_ORIGINAL_MISSING='fieldOriginal'}
local function reasonText(reason,uncertain)
    if not reason then return end
    local exact=type(getTextOrNull)=='function' and getTextOrNull('IGUI_EmberRoutesProbe_Monitor_'..reason)
    if exact then return exact end
    local key=reasons[reason]
    if not key and string.find(reason,'^FIELD_PATH_') then key='fieldPath' end
    return getText('IGUI_EmberRoutesProbe_Monitor_'..(key or (uncertain and 'fieldUncertain' or 'fieldWaiting')))
end
function M.project(context,job)
    local p=job.payload
    local control=context.runtime and context.runtime:status(job.npcId,job.id)
    local binding=context.bind(job.npcId)
    local closed=(job.state=='DONE' or job.state=='CANCELLED') and job.effects=='KNOWN'
    local uncertain=job.effects~='KNOWN'
    local stopping=control and control.state=='STOPPING'
    local active=control and not control.pending and control.state=='ACTIVE'
    local assets,collected,delivered={},0,0
    for _,asset in ipairs(p.assets) do
        assets[#assets+1]={id=asset.id,fullType=asset.fullType,kind='cargo',custody=asset.custody,
            delivered=asset.custody=='DELIVERED',held=asset.custody=='HELD',
            custodyState=asset.custody=='GROUND' and 'UNCOLLECTED'
                or asset.custody=='HELD' and 'WITHDRAWN' or 'STORED'}
        if asset.custody~='GROUND' then collected=collected+1 end
        if asset.custody=='DELIVERED' then delivered=delivered+1 end
    end
    local stages={}
    for i,key in ipairs(stageKeys) do stages[i]={labelKey=key} end
    if #assets>0 then
        stages[2].progress=collected..'/'..#assets
        stages[3].progress=delivered..'/'..#assets
    end
    return {id='FIELD_WORK:'..job.id,jobId=job.id,kind='FIELD_WORK',npcId=job.npcId,generation=job.revision,
        title=getText('IGUI_EmberRoutesProbe_Public_'..p.category),
        name=require('EmberRoutesProbe/DisplayNames').name(job.npcId,binding and binding.handle),
        state=stopping and 'STOPPING' or job.state,phase=p.phase,reason=p.reason,reasonText=reasonText(p.reason,uncertain),
        closed=closed,uncertain=uncertain,carrierAvailable=binding~=nil,
        bucket=closed and 'closed' or uncertain and 'attention' or (stopping or active) and 'active' or 'waiting',
        bodyMode=control and control.kind or 'HOLD',membership=require('EmberRoutesProbe/MembershipService').view(job.npcId),
        requested=#assets,target=#assets,delivered=delivered,nodes={},assets=assets,
        stages=stages,stageIndex=phaseIndex[p.phase],targetLocation={x=p.target.x,y=p.target.y,z=p.target.z},
        noteKey=uncertain and 'IGUI_EmberRoutesProbe_Monitor_fieldUncertain'
            or p.holding and 'IGUI_EmberRoutesProbe_Monitor_fieldCorpseHeld'
            or 'IGUI_EmberRoutesProbe_Monitor_fieldAutomatic',
        readOnly=true,canPause=false,canResume=false,canCancel=false}
end
return M
