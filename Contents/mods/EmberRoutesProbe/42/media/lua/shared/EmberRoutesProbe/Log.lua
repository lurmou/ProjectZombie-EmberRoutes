local build = require "EmberRoutesProbe/Build"
local Log = {}

function Log.write(category, message)
    if DebugLog and DebugLog.log then
        DebugLog.log(build.prefix .. " " .. category .. " " .. tostring(message))
    end
end

return Log
