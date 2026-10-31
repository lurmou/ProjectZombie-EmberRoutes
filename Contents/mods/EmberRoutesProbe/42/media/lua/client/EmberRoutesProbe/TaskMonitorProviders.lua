-- Read models for canonical Jobs. No persistence, body control or asset writes.
local M={}
local definitions={}
function M.register(def)
    if type(def)~='table' or type(def.providerType)~='string' or #def.providerType<1
        or #def.providerType>32 or type(def.project)~='function'
        or def.command~=nil and type(def.command)~='function' then return false,'MONITOR_PROVIDER_INVALID' end
    local old=definitions[def.providerType]
    if old and old~=def then return false,'MONITOR_PROVIDER_EXISTS' end
    definitions[def.providerType]=def
    return true
end
function M.has(providerType) return definitions[providerType]~=nil end
function M.project(context,job)
    local def=definitions[job.providerType]
    if not def then return end
    local row=def.project(context,job)
    if row then row.providerType=job.providerType end
    return row
end
function M.command(context,row,action)
    local def=definitions[row.providerType]
    if not def or not def.command then return 'TASK_READ_ONLY' end
    return def.command(context,row,action)
end
return M
