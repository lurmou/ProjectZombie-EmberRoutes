-- Exercises the native BaseAction presentation/continuation, with inventory effects mocked.
local nativeStarted, nativeFinished, ends, receipts, allowed, active
local count=0
local function check(v,label) count=count+1 assert(v,label) end
function isClient() return false end function isServer() return false end
function instanceof() return false end
function getTimestampMs() return 100 end

local function container()
    local c={items={}}
    function c:getItems() return self end
    function c:contains(item) return self.items[item]==true end
    function c:hasRoomFor() return true end
    function c:getParent() return nil end
    function c:DoRemoveItem(item) self.items[item]=nil end
    function c:AddItem(item) self.items[item]=true item.container=self end
    return c
end

local function item(id,source)
    local value={id=id,container=source}
    source.items[value]=true
    function value:getContainer() return self.container end
    function value:getID() return self.id end
    function value:getFullType() return 'Base.Plank' end
    function value:getActualWeight() return 1.5 end
    return value
end

package.loaded['EmberRoutesProbe/Work/LaborProducers']={eligible=function() return true end,transfer=function() return true end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={inventoryChanged=function() end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}

EmberRoutesProbeJava={
    carrierActive=function() return true end,
    nativeActionStart=function(npc, anim, duration, block)
        nativeStarted=true nativeFinished=false
        return true
    end,
    nativeActionFinished=function(npc)
        return nativeFinished
    end,
    nativeActionStop=function(npc)
        nativeStarted=false nativeFinished=true ends=ends+1
    end
}

local Transfer=require 'EmberRoutesProbe/Work/WorkTransfer'
Transfer.reachable=function() return true end

local function run(interrupt)
    nativeStarted, nativeFinished, ends, receipts, allowed, active = false, false, 0, {}, true, 1
    local from,to=container(),container() local endpoint={}
    local one,two=item(1,from),item(2,from)
    local npc={
        getInventory=function() return to end,
        getCharacterActions=function() return {isEmpty=function() return not nativeStarted end} end,
        faceThisObject=function() end
    }
    local body={current=function() return true end,retained=function() return true end}
    local function context(id)
        return {
            npc=npc,body=body,job={id='job',npcId='npc'},valid=function() return allowed and active==id end,
            eligible=function() return true end,
            transferred=function(v)
                assert(v.id==active and v.container==to,'receipt follows actual original transfer')
                receipts[#receipts+1]=v.id active=nil return true
            end
        }
    end
    local first=context(1)
    first.nextTransfer=function()
        active=2 return {context=context(2),item=two,from=from,to=to,endpoint=endpoint}
    end

    local step=Transfer.item(first,one,from,to,endpoint)
    assert(step.start()~='FAILED')
    check(nativeStarted==true and ends==0 and #receipts==0, 'native action presentation started')
    check(step.poll()=='WAIT', 'action in progress returns WAIT')

    -- Finish first item presentation
    nativeFinished=true
    local res1 = step.poll()
    check(res1=='WAIT' and #receipts==1 and one.container==to, 'first transfer delivers original item and queues next')
    check(active==2 and two.container==from, 'second item remains in source before its presentation completes')

    if interrupt then
        allowed=false
        nativeFinished=true
        check(step.poll()=='FAILED', 'invalidation stops untransferred original')
        check(#receipts==1 and two.container==from, 'interrupted transfer preserves uncommitted item in source')
    else
        nativeFinished=true
        check(step.poll()=='PASSED' and #receipts==2, 'batch completes and delivers second original')
        check(one.container==to and two.container==to, 'both originals safely moved to destination')
        check(ends==1, 'action presentation cleanly stopped at the end of batch')
    end
end

run(false)
run(true)
print('PASS '..count..' native action continuation checks; inventory effects mocked, game NOT RUN')
