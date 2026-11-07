-- Field water filling. The world-source path is the same one vanilla builds
-- behind ISFluidTransferUI: wrap the source's FluidContainer, wrap the carried
-- container, then hand both to ISFluidTransferAction.
-- Source discovery reuses CookingWaterSources (same settlement facilities scan,
-- same NATIVE_WATER/PLUMBED/FINITE classification); no second water model.
local A=require 'EmberRoutesProbe/Field/FieldActions'
local Sources=require 'EmberRoutesProbe/Cooking/CookingWaterSources'
local ToolReq=require 'EmberRoutesProbe/Field/ToolRequirements'
local W={}

local function wrapper(object)
    if not object or not object.getFluidContainer then return nil end
    local component=object:getFluidContainer()
    if not component then return nil end
    local ok,value=pcall(ISFluidContainer.new,ISFluidContainer,component)
    return ok and value or nil
end

-- Backing object first: a plumbed tap stores its water in the connected barrel.
local function sourceObject(source)
    if source and source.backing and source.backing.object then return source.backing.object end
    return source and source.object or nil
end

function W.begin(c)
    if c.water then return c.water end
    local ok,request=pcall(Sources.search,c)
    if not ok or not request then return nil,'FIELD_WATER_SOURCE_UNAVAILABLE' end
    c.water={request=request,source=nil}
    return c.water
end

local function findSource(c)
    local state=W.begin(c)
    if not state then return nil,'FIELD_WATER_SOURCE_UNAVAILABLE' end
    if state.source then return state.source end
    local found,why=state.request:step(16)
    if not found then return nil,why or 'FIELD_WATER_SOURCE_UNAVAILABLE' end
    state.source=found
    return found
end

-- One transfer action sized to what the target still needs. Amounts come from
-- the engine wrappers, never from our own accounting.
function W.node(c,item,needUses)
    require 'Fluids/ISFluidContainer'
    require 'Fluids/ISFluidUtil'
    require 'Fluids/ISFluidTransferAction'
    local source,why=findSource(c)
    if not source then return nil,why end
    local object=sourceObject(source)
    local sourceWrapper=wrapper(object)
    local targetWrapper=wrapper(item)
    if not sourceWrapper or not targetWrapper then return nil,'FIELD_WATER_API_UNAVAILABLE' end
    if not ISFluidUtil.validateContainer(sourceWrapper) or not ISFluidUtil.validateContainer(targetWrapper) then
        return nil,'FIELD_WATER_API_UNAVAILABLE'
    end
    local sourceComponent=sourceWrapper:getFluidContainer()
    local targetComponent=targetWrapper:getFluidContainer()
    if not sourceComponent or not targetComponent then return nil,'FIELD_WATER_API_UNAVAILABLE' end
    local free=(targetComponent:getCapacity() or 0)-(targetComponent:getAmount() or 0)
    local perUse=ISFarmingMenu and ISFarmingMenu.getFluidContainerMillilitresPerUse
        and ISFarmingMenu.getFluidContainerMillilitresPerUse() or 0
    local want=perUse>0 and (needUses-ToolReq.uses(item))*perUse or free
    local amount=math.min(want,sourceComponent:getAmount() or 0,free)
    if amount<=0 then return nil,'FIELD_WATER_SOURCE_EMPTY' end
    local before=targetComponent:getAmount() or 0
    local maximum=amount
    return A.new(c,{kind='FILL_WATER',
        valid=function()
            return item:getContainer()==c.npc:getInventory() and targetWrapper:isValid()
                and sourceWrapper:isValid()
        end,
        before=function() before=targetComponent:getAmount() or 0 return true end,
        create=function()
            local action=ISFluidTransferAction:new(c.npc,sourceWrapper,sourceWrapper:getFluidObject(),
                targetWrapper,targetWrapper:getFluidObject(),maximum)
            action.maxTime=math.max(ISFluidUtil.getMinTransferActionTime(),
                maximum*ISFluidUtil.getTransferActionTimePerLiter())
            return action
        end,
        observe=function(ok,finished)
            local now=targetComponent:getAmount() or 0
            local changed=now>before
            return true,changed,not finished
        end})
end

return W
