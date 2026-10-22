local Driver=require "EmberRoutesProbe/Driver"
local Registry=require "EmberRoutesProbe/ContainerRegistry"
local text=require("EmberRoutesProbe/LogisticsText").get
local Presentation={}
function Presentation.kind(row)
    if row.producer~="LOGISTICS" then return text("manualBatch") end
    return text(row.sourceMode=="INTAKE" and "automaticIntake" or row.sourceMode=="TIDY" and "automaticTidy" or "automaticBatch")
end
function Presentation.activity(row)
    if row.total==0 or row.state=="DONE" then return text(row.reason) end
    local phase=row.reason=="WORKING" and (row.phase=="COLLECT" or row.phase=="DELIVER") and text("phase_"..row.phase)
    if phase then return phase.." · "..Presentation.kind(row) end
    return Presentation.kind(row).." · "..text(row.reason)
end
function Presentation.batch(row)
    return text(row.state=="DONE" and "completedBatch" or "currentBatch")
end
function Presentation.completed(summary)
    return text("lastCompleted").." · "..summary.delivered.."/"..summary.total
end
local function sameCompleted(a,b)
    if not a or not b then return a==b end
    return a.id==b.id and a.total==b.total and a.delivered==b.delivered and a.sourceMode==b.sourceMode
end
function Presentation.new(actor)
    local names,rows={},{}
    local view={}
    function view:project(snapshot)
        local result={}
        for _,worker in ipairs(snapshot.workers) do
            local name=names[worker.id]
            if not name then
                local binding=Driver.bindId(actor,worker.id)
                if binding then name=binding.handle:getFullName() names[worker.id]=name end
            end
            name=name or string.sub(worker.id,1,8)
            local progress=worker.total>0 and (" · "..worker.delivered.."/"..worker.total) or ""
            local label=name..progress.."\n"..Presentation.activity(worker)
            local previous=rows[worker.id]
            if not previous or previous.label~=label or previous.taskId~=worker.taskId or previous.state~=worker.state
                or previous.phase~=worker.phase or previous.source~=worker.source or previous.destination~=worker.destination
                or previous.sourceMode~=worker.sourceMode or previous.producer~=worker.producer
                or not sameCompleted(previous.lastCompleted,worker.lastCompleted) then
                local copy={} for key,value in pairs(worker) do copy[key]=value end
                copy.name,copy.label=name,label rows[worker.id]=copy
            end
            result[#result+1]=rows[worker.id]
        end
        return result
    end
    return view
end
function Presentation.endpoint(id)
    local position=Registry.describe(id)
    if not position then return text("noEndpoint") end
    local kind=position.containerType
    local name=kind and (getTextOrNull("IGUI_ContainerTitle_"..kind) or kind) or text("container")
    return name.." ("..position.x..", "..position.y..", z="..position.z..")"
end
function Presentation.details(row)
    if not row then return text("selectWorker") end
    return row.name.."\n"..Presentation.activity(row).."\n\n"..text("delivered")..": "..row.delivered.." / "..row.total
        .."\n"..text("task")..": "..(row.taskId~="" and string.sub(row.taskId,1,8) or text("noTask"))
        .."\n"..text("source")..": "..Presentation.endpoint(row.source)
        .."\n"..text("destination")..": "..Presentation.endpoint(row.destination)
end
return Presentation
