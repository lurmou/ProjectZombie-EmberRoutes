local build = require "EmberRoutesProbe/Build"
local Log = {}

function Log.write(category, message)
    DebugLog.log(build.prefix .. " " .. category .. " " .. tostring(message))
end

return Log
