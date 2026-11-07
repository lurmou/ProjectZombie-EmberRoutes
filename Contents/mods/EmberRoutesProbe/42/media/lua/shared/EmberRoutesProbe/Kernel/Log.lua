local build = require "EmberRoutesProbe/Kernel/Build"
local Log = {}

function Log.write(category, message)
    if DebugLog and DebugLog.log then
        DebugLog.log(build.prefix .. " " .. category .. " " .. tostring(message))
    end
end

-- Structured one-liner for counting: sorted keys keep successive lines diffable.
function Log.event(domain, event, fields)
    local parts = {}
    if type(fields) == "table" then
        local keys = {}
        for key in pairs(fields) do keys[#keys + 1] = key end
        table.sort(keys)
        for _, key in ipairs(keys) do
            parts[#parts + 1] = key .. "=" .. tostring(fields[key])
        end
    end
    Log.write(domain, event .. (#parts > 0 and (" " .. table.concat(parts, " ")) or ""))
end

return Log
