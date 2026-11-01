local Rules = require "EmberRoutesProbe/HaulRules"
local Policy = require "EmberRoutesProbe/InventoryPolicy"
local Filter = require "EmberRoutesProbe/StorageFilter"
local Log = require "EmberRoutesProbe/Log"
local Gate = require "EmberRoutesProbe/RuntimeGate"
local Jobs = require "EmberRoutesProbe/JobStore"
local Registry = {}
local admittedRoot, admittedJobs
Registry.tags = Policy.order
Registry.listeners = {}
Registry.inventoryListeners = {}
-- Primary metadata stays in its original slot for existing saves/tasks.
-- Secondary inventories own independent identities; never alias the fridge policy.
function Registry.containerIndex(object,container)
    if not object or not object.getContainer or not container then return nil end
    if object:getContainer()==container then return 0 end
    if object.getContainerCount and object.getContainerByIndex then
        for i=0,object:getContainerCount()-1 do
            if object:getContainerByIndex(i)==container then return i end
        end
    end
end
function Registry.metadata(object,container)
    if not object or not object.getContainer then return nil end
    local index=Registry.containerIndex(object,container or object:getContainer())
    if index==nil then return nil end
    local data=object:getModData()
    if index==0 then return data.EmberRoutesContainer end
    return data.EmberRoutesContainers and data.EmberRoutesContainers[tostring(index)]
end
-- Observers cannot veto already accepted configuration or verified physical effects.
local function notify(listeners,id)
    for _,fn in ipairs(listeners) do
        local ok,reason=pcall(fn,id)
        if not ok then Log.write("CONTAINER_EVENT","OBSERVER_ERROR "..tostring(reason)) end
    end
end
-- Verified inventory effects notify read models without depending on any UI service.
function Registry.inventoryChanged(container)
    for _,id in ipairs(Registry.affected(container) or {}) do notify(Registry.inventoryListeners,id) end
end
function Registry.filter(object,container)
    local tag=Registry.metadata(object,container)
    if not tag then return nil end
    return tag.filter or Filter.legacy(tag.tag)
end
function Registry.changed(id)
    notify(Registry.listeners,id)
end

function Registry.data(freshRoot)
    -- Native root-handle cache turns the per-call ModData bridge into one map
    -- lookup; the extension clears it on world lifecycle. Missing/noop bridge
    -- (tests) keeps the direct getOrCreate path.
    local bridge=EmberRoutesProbeJava
    -- OnInitGlobalModData supplies the engine root before the native cache resets.
    local data=freshRoot
    if data==nil and bridge and bridge.cachedModData then
        local ok,cached=pcall(bridge.cachedModData,"EmberRoutes/Work/v1")
        if ok then data=cached end
    end
    if not data then data=ModData.getOrCreate("EmberRoutes/Work/v1") end
    if type(data)~='table' then error('WORK_FORMAT_UNSUPPORTED') end
    if data.format==nil then
	-- Only an empty root is a new world. Missing version on existing facts
	-- is unsupported, never permission to label them as the current schema.
	for _ in pairs(data) do error('WORK_FORMAT_UNSUPPORTED') end
    elseif data.format~=1 then error('WORK_FORMAT_UNSUPPORTED') end
    if data.containers~=nil and type(data.containers)~='table' then error('CONTAINER_FORMAT_UNSUPPORTED') end
    if data~=admittedRoot or data.taskJobs~=admittedJobs then
	local ok,reason=Jobs.check(data)
	if not ok then error(reason) end
	-- No defaults, normalization or record publication before acceptance.
	data.format, data.containers = 1, data.containers or {}
	admittedRoot,admittedJobs=data,data.taskJobs
    end
    return data
end

function Registry.id()
    local create = _G.getRandomUUID
    if type(create) ~= "function" then error("UUID_API_UNAVAILABLE") end
    return create()
end

local function integer(value)
    return type(value)=="number" and value==value and math.abs(value)<=10000000 and value==math.floor(value)
end
-- Detached locator. Missing index/type in old saves remains compatible with primary slot 0.
function Registry.describe(id)
    local r=Registry.data().containers[id]
    if not r then return nil,"CONTAINER_NOT_REGISTERED" end
    if type(r)~="table" then return nil,"CONTAINER_RECORD_INVALID" end
    local index=r.containerIndex
    if index==nil then index=0 end
    if not integer(r.x) or not integer(r.y) or not integer(r.z) or not integer(index) or index<0
            or (r.containerType~=nil and type(r.containerType)~="string") then return nil,"CONTAINER_RECORD_INVALID" end
    return {format=1,id=id,x=r.x,y=r.y,z=r.z,containerIndex=index,containerType=r.containerType}
end
-- Exact inventory event -> one ID; object event -> its registered compartments.
-- nil means unknown source; {} means known but unregistered (no broad invalidation).
function Registry.affected(object)
    if type(object)~="table" and type(object)~="userdata" then return nil end
    local container=object.getParent and object or nil
    local parent=container and container:getParent() or object
    if not parent or not parent.getModData then return {} end
    local result,seen={},{}
    local function add(tag)
        if type(tag)~="table" or type(tag.id)~="string" or seen[tag.id] then return end
        -- Notification is not authorization. A removed/moved object must still
        -- invalidate its OLD locator; resolve() decides whether it remains usable.
        if Registry.data().containers[tag.id] then
            seen[tag.id]=true result[#result+1]=tag.id
        end
    end
    local exact=container and Registry.metadata(parent,container)
    if exact then add(exact)
    else
        local data=parent:getModData()
        add(data.EmberRoutesContainer)
        for _,tag in pairs(data.EmberRoutesContainers or {}) do add(tag) end
    end
    table.sort(result)
    return result
end

function Registry.resolve(id, intent, scopeId)
    local record,recordReason = Registry.describe(id)
    if not record then return nil,recordReason end
    local cell = getCell()
    local square = cell and cell:getGridSquare(record.x, record.y, record.z)
    if not square then return nil, "CONTAINER_UNLOADED" end
    local found
    local objects = square:getObjects()
    for i = 0, objects:size() - 1 do
        local object = objects:get(i)
        local index=record.containerIndex or 0
        local container
        if index==0 then container=object:getContainer()
        elseif object.getContainerByIndex and object.getContainerCount and index<object:getContainerCount() then
            container=object:getContainerByIndex(index)
        end
        local tag=container and Registry.metadata(object,container)
        if tag and tag.id == id then
            if found then return nil, "CONTAINER_ID_DUPLICATED" end
            if not container or (record.containerType and container:getType()~=record.containerType) then return nil, "CONTAINER_REMOVED" end
            found = { id = id, object = object, container = container, tag = tag.tag, scopeId=tag.scopeId,
                filter=Registry.filter(object,container) }
        end
    end
    if not found then return nil, "CONTAINER_REMOVED" end
    if not Filter.access(found.filter) then return nil, "CONTAINER_PRIVATE" end
    if intent and intent~="take" and intent~="put" then return nil,"INVALID_INTENT" end
    if scopeId and found.scopeId ~= scopeId then return nil, "CONTAINER_SCOPE_CHANGED" end
    return found
end

function Registry.revalidate(endpoint,intent,scopeId)
    if not endpoint then return nil,"CONTAINER_CHANGED" end
    local current,reason=Registry.resolve(endpoint.id,intent,scopeId)
    if not current then return nil,reason end
    if current.object~=endpoint.object or current.container~=endpoint.container then return nil,"CONTAINER_CHANGED" end
    return current
end

function Registry.tag(actor, object, name, deferNotification, container, bypassDistance)
    if not Policy.tags[name] and name ~= "untag" then return "INVALID_TAG" end
    container=container or (object and object:getContainer())
    local index=Registry.containerIndex(object,container)
    local square = object and object:getSquare()
    if index==nil or not square or not square:getObjects():contains(object) or not object:getContainer() then return "WORLD_CONTAINER_REQUIRED" end
    local cell = getCell()
    if not cell or cell:getGridSquare(square:getX(), square:getY(), square:getZ()) ~= square then return "CONTAINER_UNLOADED" end
    if actor and not bypassDistance and not Rules.near(actor:getX(), actor:getY(), actor:getZ(), square:getX()+0.5, square:getY()+0.5, square:getZ()) then
        return "TOO_FAR_TO_TAG"
    end
    local data = Registry.data()
    local tag = Registry.metadata(object,container)
    if not tag then
        if name == "untag" then return "UNTAGGED" end
        local count = 0
        for _ in pairs(data.containers) do count = count + 1 end
        if count >= 256 then return "CONTAINER_LIMIT" end
        tag = { id = Registry.id(), scopeId="local-world" }
        local metadata=object:getModData()
        if index==0 then metadata.EmberRoutesContainer=tag
        else
            metadata.EmberRoutesContainers=metadata.EmberRoutesContainers or {}
            metadata.EmberRoutesContainers[tostring(index)]=tag
        end
    end
    tag.tag = name == "untag" and "private" or name
    tag.filter = nil -- Legacy debug commands explicitly replace a prior configuration.
    data.containers[tag.id] = { x=square:getX(), y=square:getY(), z=square:getZ(), containerIndex=index, containerType=container:getType() }
    if not deferNotification then Registry.changed(tag.id) end
    return "TAGGED " .. name .. " id=" .. tag.id
end

function Registry.configure(actor,object,config,container,logisticsRole,bypassDistance)
    if not Gate.isSinglePlayer() or (actor and not Gate.isLiveActor(actor)) then return "DRIVER_UNAVAILABLE" end
    local copy,reason=Filter.copy(config)
    if not copy then return reason end
    if logisticsRole~=nil and logisticsRole~="INPUT" and logisticsRole~="STORAGE" and logisticsRole~="EXCLUDED" then return "INVALID_ROLE" end
    local result=Registry.tag(actor,object,"inbox",true,container,bypassDistance)
    if not string.find(result,"^TAGGED") then return result end
    local tag=Registry.metadata(object,container)
    if not tag then return "CONTAINER_CHANGED" end
    tag.filter=copy
    tag.tag=nil
    if logisticsRole then tag.logisticsRole=logisticsRole end
    Registry.changed(tag.id)
    return "FILTER_CONFIGURED"
end

function Registry.accepts(endpoint,item)
    return endpoint and Filter.matches(Registry.filter(endpoint.object,endpoint.container),item)
end

function Registry.logistics(endpoint)
    local tag=endpoint and Registry.metadata(endpoint.object,endpoint.container)
    local role=tag and tag.logisticsRole or "STORAGE"
    if role~="STORAGE" and role~="INPUT" and role~="EXCLUDED" then return "EXCLUDED" end
    return role
end

function Registry.configureLogistics(actor,object,container,role)
    if not Gate.canExecute(actor) or not actor then return "DRIVER_UNAVAILABLE" end
    if role~="STORAGE" and role~="INPUT" and role~="EXCLUDED" then return "INVALID_ROLE" end
    local tag=Registry.metadata(object,container)
    -- Explicitly assigning a logistics role registers a previously unconfigured
    -- container as shared. Existing private/disabled configurations stay guarded.
    if not tag then
        local result=Registry.configure(actor,object,Filter.new(),container)
        if result~="FILTER_CONFIGURED" then return result end
        tag=Registry.metadata(object,container)
        if not tag then return "CONTAINER_CHANGED" end
    end
    local endpoint,reason=Registry.resolve(tag.id,"take","local-world")
    if not endpoint or endpoint.object~=object or endpoint.container~=container then return reason or "CONTAINER_CHANGED" end
    local square=object:getSquare()
    if not Rules.near(actor:getX(),actor:getY(),actor:getZ(),square:getX()+0.5,square:getY()+0.5,square:getZ()) then return "TOO_FAR_TO_TAG" end
    tag.logisticsRole=role Registry.changed(tag.id)
    return "ROLE_CONFIGURED"
end

function Registry.select(actor, object, role, container)
    if role ~= "source" and role ~= "destination" then return "INVALID_ROLE" end
    local tag = Registry.metadata(object,container)
    if not tag then return "CONTAINER_PRIVATE" end
    local endpoint, reason = Registry.resolve(tag.id, role == "source" and "take" or "put")
    if not endpoint or endpoint.object ~= object or (container and endpoint.container~=container) then return reason or "CONTAINER_CHANGED" end
    local square = object:getSquare()
    if not Rules.near(actor:getX(), actor:getY(), actor:getZ(), square:getX()+0.5, square:getY()+0.5, square:getZ()) then
        return "TOO_FAR_TO_TAG"
    end
    Registry.data()[role] = tag.id
    return "SELECTED " .. role .. " id=" .. tag.id
end

return Registry
