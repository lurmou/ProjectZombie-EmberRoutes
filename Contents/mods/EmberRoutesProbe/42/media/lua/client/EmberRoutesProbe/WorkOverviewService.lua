local Monitor=require 'EmberRoutesProbe/OrderMonitorService'
local P=require 'EmberRoutesProbe/WorkOverviewPresenter'
local S={}
function S.status(actor,scope)
    local craft=require('EmberRoutesProbe/CraftingService').status(actor,scope)
    local workers=craft.workers or {}
    workers=require('EmberRoutesProbe/PersonnelService').enrichWorkers(actor,scope,workers)
    local problems=require('EmberRoutesProbe/DemandMonitorService').status(actor,scope).rows
    local monitor=Monitor.status(actor,scope)
    local rows=monitor.rows or {}
    -- Cleaning handlers deliberately live in the demand read model, not the old monitor list.
    for _,problem in ipairs(problems or {}) do
        for _,child in ipairs(problem.children or {}) do
            if child.kind=='FIELD_WORK' then rows[#rows+1]=child end
        end
    end
    local snapshot=P.project(rows,workers,problems) snapshot.reason=monitor.reason or craft.reason return snapshot
end
function S.watch(actor,scope,callback)
    return Monitor.watch(actor,scope,callback,S.status)
end
return S
