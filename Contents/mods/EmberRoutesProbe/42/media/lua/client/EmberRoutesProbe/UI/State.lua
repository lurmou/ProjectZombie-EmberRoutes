-- Shallow immutable snapshots. Consumers replace changed branches, never mutate them.
local State={}
---@class EmberRoutesUIStore
---@field value table
---@field listeners table
local Store={}
Store.__index=Store
function Store:subscribe(listener)
    self.listeners[listener]=true
    return function() self.listeners[listener]=nil end
end
function Store:setState(patch)
    local nextValue,changed,dirty={},{},false
    for key,value in pairs(self.value) do nextValue[key]=value end
    for key,value in pairs(patch) do
        if value~=self.value[key] then nextValue[key]=value changed[key]=true dirty=true end
    end
    if not dirty then return false end
    self.value=nextValue
    for listener in pairs(self.listeners) do listener(nextValue,changed) end
    return true
end
---@param initial table
---@return EmberRoutesUIStore
function State.new(initial)
    return setmetatable({value=initial,listeners={}},Store)
end
return State
