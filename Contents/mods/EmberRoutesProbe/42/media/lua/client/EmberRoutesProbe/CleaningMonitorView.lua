-- Detached read-only overview. Never used to execute, settle or release a Job.
local M={}
function M.project(rows,scopeId)
    local output,children={},{}
    local demand
    for _,row in ipairs(rows) do
        if row.kind=='FIELD_DEMAND' then demand=row
        elseif row.kind=='FIELD_WORK' and row.workCategory=='cleaning' and not row.closed then children[#children+1]=row
        else output[#output+1]=row end
    end
    if not demand and #children==0 then return output end
    table.sort(children,function(a,b) return a.id<b.id end)
    local active,attention=0,false
    for _,child in ipairs(children) do
        if child.bucket=='active' then active=active+1 end
        if child.uncertain or child.bucket=='attention' then attention=true end
    end
    local bucket=attention and 'attention' or active>0 and 'active' or 'waiting'
    local overview={id='CLEANING:'..scopeId,kind='CLEANING_OVERVIEW',compact=true,readOnly=true,
        title=getText('IGUI_EmberRoutesProbe_Public_cleaning'),closed=false,bucket=bucket,uncertain=attention,
        state=bucket,stateText=getText('IGUI_EmberRoutesProbe_Monitor_filter_'..bucket),
        summaryText=getText('IGUI_EmberRoutesProbe_Monitor_cleaningOverview',active,#children-active),
        demandSummary=demand and demand.demandSummary,children=children,assets={},
        canPause=false,canResume=false,canCancel=false,carrierAvailable=true}
    if demand then
        overview.demandReason=demand.reasonText or demand.summaryText
        overview.blockerLabels=demand.blockerLabels
        if #children==0 then overview.summaryText=overview.demandReason end
    end
    output[#output+1]=overview
    return output
end
return M
