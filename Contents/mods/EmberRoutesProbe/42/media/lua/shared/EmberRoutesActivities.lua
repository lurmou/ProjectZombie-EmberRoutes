-- Load-time extension entry. Add-on definition files may explicitly require the
-- registry to avoid relying on cross-mod file order. Runtime registration closes.
local registry=require 'EmberRoutesProbe/ActivityRegistry'
if Events and Events.OnGameStart then Events.OnGameStart.Add(registry.freeze) end
