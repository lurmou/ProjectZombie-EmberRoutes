-- Observers only mark presentation dirty. Their failures cannot undo assets.
local Signals={listeners={}}
function Signals.changed(npcId)
    for callback in pairs(Signals.listeners) do
        local ok=pcall(callback,npcId)
        if not ok then Signals.listeners[callback]=nil end
    end
end
function Signals.watch(callback)
    Signals.listeners[callback]=true
    return function() Signals.listeners[callback]=nil end
end
return Signals
