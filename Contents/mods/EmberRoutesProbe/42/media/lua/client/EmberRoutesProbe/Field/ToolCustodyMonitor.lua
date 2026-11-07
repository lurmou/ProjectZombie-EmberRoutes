-- Read-only custody display. Passive custody is personnel information, not a Job.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Members=require 'EmberRoutesProbe/Settlement/MembershipService'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local M={}
local function exceptional(c) return c.state=='RECONCILE_REQUIRED' or c.state=='DEAD_CARRIER' end
function M.assets(npcId,handle,budget)
    local records,items,assets={},{},{}
    for _,c in pairs(Registry.data().toolCustody and Registry.data().toolCustody.byId or {}) do
        if tostring(c.npcId)==tostring(npcId) then records[#records+1]=c items[#items+1]=c.itemId end
    end
    table.sort(records,function(a,b) return a.id<b.id end)
    local types=require('EmberRoutesProbe/Warehouse/ItemDisplay').types({id='TOOL_VIEW:'..npcId,items=items},handle,budget or {remaining=128})
    for _,c in ipairs(records) do
        assets[#assets+1]={id=c.itemId,custodyId=c.id,kind='tools',fullType=types[tostring(c.itemId)],
            displayName=getText('IGUI_EmberRoutesProbe_Monitor_role_'..c.role),
            custodyState=exceptional(c) and 'RECONCILE' or c.state=='HELD' and 'WITHDRAWN' or 'TRANSIT',
            statusText=getText('IGUI_EmberRoutesProbe_Monitor_custody_'..c.state),
            reasonText=getText('IGUI_EmberRoutesProbe_Monitor_TOOL_'..c.state),
            sequence=c.sequence,exceptional=exceptional(c),returning=c.returnIntent~=nil or c.returnJobId~=nil or c.state=='PENDING_RETURN'}
    end
    return assets
end
function M.rows(scopeId,context)
    local root=Registry.data() local groups={} local rows={} local runtime=Runtime.current()
    for _,c in pairs(root.toolCustody and root.toolCustody.byId or {}) do
        local npcId=tostring(c.npcId) local member=Members.view(npcId)
        local scope=c.returnIntent and c.returnIntent.scopeId or member and member.settlementId
        if scope==scopeId and (exceptional(c) or not c.activeJobId and (c.returnIntent or c.returnJobId or c.state=='PENDING_RETURN')) then
            local row=groups[npcId]
            if not row then
                local binding=context and context.bind(npcId)
                row={id='TOOL_CUSTODY:'..npcId,kind='TOOL_CUSTODY',npcId=npcId,compact=true,
                    name=require('EmberRoutesProbe/Warehouse/DisplayNames').name(npcId,binding and binding.handle),
                    title=getText('IGUI_EmberRoutesProbe_Monitor_toolReturn'),bucket='waiting',closed=false,
                    carrierAvailable=true,readOnly=true,canPause=false,canResume=false,canCancel=false,assets={}}
                row.allAssets=M.assets(npcId,binding and binding.handle,context and context.displayBudget)
                groups[npcId]=row rows[#rows+1]=row
            end
            for _,asset in ipairs(row.allAssets) do if asset.custodyId==c.id then row.assets[#row.assets+1]=asset break end end
            local control=c.returnJobId and runtime and runtime:status(npcId,c.returnJobId)
            if exceptional(c) then row.bucket='attention' row.uncertain=true
            elseif row.bucket~='attention' and control and not control.pending and control.state=='ACTIVE' then row.bucket='active' end
            if c.state=='DEAD_CARRIER' then row.carrierAvailable=false end
        end
    end
    for _,row in ipairs(rows) do
        table.sort(row.assets,function(a,b) return a.custodyId<b.custodyId end)
        row.allAssets=nil row.state=row.bucket
        row.stateText=getText('IGUI_EmberRoutesProbe_Monitor_filter_'..row.bucket)
        row.summaryText=getText('IGUI_EmberRoutesProbe_Monitor_toolOverview',row.name,#row.assets)
    end
    return rows
end
return M
