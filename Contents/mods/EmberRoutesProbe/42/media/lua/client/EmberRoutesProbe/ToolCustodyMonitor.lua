-- A retained tool duty is visible even when no ordinary Job or body session exists.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Members=require 'EmberRoutesProbe/MembershipService'
local Runtime=require 'EmberRoutesProbe/TaskRuntime'
local M={}
function M.rows(scopeId)
    local root=Registry.data() local rows={} local runtime=Runtime.current()
    for _,c in pairs(root.toolCustody and root.toolCustody.byId or {}) do
        local member=Members.view(tostring(c.npcId))
        local scope=c.returnIntent and c.returnIntent.scopeId or member and member.settlementId
        if scope==scopeId and not c.activeJobId then
            local attention=c.state=='RECONCILE_REQUIRED' or c.state=='DEAD_CARRIER'
            local control=c.returnJobId and runtime and runtime:status(tostring(c.npcId),c.returnJobId)
            local active=control and not control.pending and control.state=='ACTIVE'
            local steps={{key='return',labelKey='IGUI_EmberRoutesProbe_Monitor_toolReturn',
                status=attention and 'UNCERTAIN' or control and control.state=='STOPPING' and 'STOPPING'
                    or active and 'ACTIVE' or 'PLANNED'}}
            rows[#rows+1]={id='TOOL_CUSTODY:'..c.id,kind='TOOL_CUSTODY',npcId=tostring(c.npcId),
                generation=c.sequence,state=c.state,phase='TOOL_RETURN',reason='TOOL_'..c.state,
                stateText=getText('IGUI_EmberRoutesProbe_Monitor_'..(attention and 'RECONCILE_REQUIRED' or 'toolCustody')),
                title=getText('IGUI_EmberRoutesProbe_Monitor_toolReturn'),
                reasonText=getText('IGUI_EmberRoutesProbe_Monitor_TOOL_'..c.state),
                summaryText=getText('IGUI_EmberRoutesProbe_Monitor_role_'..c.role),
                bucket=attention and 'attention' or active and 'active' or 'waiting',closed=false,uncertain=attention,
                carrierAvailable=c.state~='DEAD_CARRIER',readOnly=true,canPause=false,canResume=false,canCancel=false,
                target=0,requested=0,delivered=0,nodes={},assets={{id=c.itemId,kind='tools',held=c.state=='HELD'}},
                stages=steps,stageIndex=1,workflow={viewRevision=c.sequence,steps=steps}}
        end
    end
    return rows
end
return M
