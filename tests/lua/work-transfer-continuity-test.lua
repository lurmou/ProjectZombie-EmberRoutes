-- Exercises the INSTALLED vanilla perform/queue continuation, with inventory effects mocked.
local queued,ends,receipts,allowed,active
local count=0
local function check(v,label) count=count+1 assert(v,label) end
function isClient() return false end function isServer() return false end
function instanceof() return false end
function getTimestampMs() return 100 end
ISInventoryPage={}
ISBaseTimedAction={derive=function() return {} end,perform=function() queued=nil end}
package.loaded['TimedActions/ISBaseTimedAction']=true
ISTimedActionQueue={hasAction=function(a) return queued==a end,
    getTimedActionQueue=function() return {queue={queued},indexOf=function(_,a) return queued==a and 1 or -1 end} end}
dofile('D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/media/lua/client/TimedActions/ISInventoryTransferAction.lua')
package.loaded['TimedActions/ISInventoryTransferAction']=true
local nativePerform=ISInventoryTransferAction.perform
local function container()
    local c={items={}}
    function c:getItems() return self end
    function c:contains(item) return self.items[item]==true end
    function c:hasRoomFor() return true end
    function c:getParent() return nil end
    return c
end
local function item(id,source)
    local value={id=id,container=source}
    source.items[value]=true
    function value:getContainer() return self.container end
    function value:getID() return self.id end
    function value:getFullType() return 'Base.Plank' end
    function value:setJobDelta() end
    return value
end
ISInventoryTransferAction.new=function(_,npc,value,from,to,time)
    local a={character=npc,item=value,srcContainer=from,destContainer=to,maxTime=time,
	queueList={{items={value},time=time,type=value:getFullType()}},perform=nativePerform}
    setmetatable(a,{__index=ISInventoryTransferAction})
    function a:isValid() return true end
    function a:startActionAnim() end function a:update() end
    function a:transferItem(v) from.items[v]=nil to.items[v]=true v.container=to end
    function a:stop() queued=nil end
    function a:resetJobDelta() end
    function a:isAlreadyTransferred(v) return v.container==to end
    function a:playTransferCompleteSound() end
    function a:playSourceContainerCloseSound() end function a:playDestContainerCloseSound() end
    function a:stopLoopingSound() end
    return a
end
package.loaded['EmberRoutesProbe/Work/LaborProducers']={eligible=function() return true end,transfer=function() return true end}
package.loaded['EmberRoutesProbe/Warehouse/ContainerRegistry']={inventoryChanged=function() end}
package.loaded['EmberRoutesProbe/Kernel/Log']={write=function() end}
EmberRoutesProbeJava={carrierActive=function() return true end}
local Transfer=require 'EmberRoutesProbe/Work/WorkTransfer'
Transfer.reachable=function() return true end
local function run(interrupt)
    queued=nil ends=0 receipts={} allowed=true active=1
    local from,to=container(),container() local endpoint={}
    local one,two=item(1,from),item(2,from)
    local npc={getInventory=function() return to end,getCharacterActions=function() return {isEmpty=function() return not queued end} end}
    local body={current=function() return true end,retained=function() return true end,
	add=function(a)
	    queued=a
	    a.action={setTime=function() end,stopTimedActionAnim=function() ends=ends+1 end,setLoopedAction=function() end}
	    return true
	end}
    local function context(id)
	return {npc=npc,body=body,job={id='job',npcId='npc'},valid=function() return allowed and active==id end,
	    eligible=function() return true end,
	    transferred=function(v)
		assert(v.id==active and v.container==to,'receipt follows actual original transfer')
		receipts[#receipts+1]=v.id active=nil return true
	    end}
    end
    local first=context(1)
    first.nextTransfer=function()
	active=2 return {context=context(2),item=two,from=from,to=to,endpoint=endpoint}
    end
    local step=Transfer.item(first,one,from,to,endpoint)
    assert(step.start()~='FAILED')
    local same=queued same:perform()
    check(queued==same and ends==0 and #receipts==1,'first transfer keeps the same native action and animation')
    check(active==2 and two.container==from,'only next intent exists before its physical effect')
    if interrupt then allowed=false end
    same:perform()
    if interrupt then
	check(#receipts==1 and two.container==from and queued==nil,'invalidation stops the untransferred original')
	check(step.poll()=='FAILED','partial batch reports stop rather than all delivered')
    else
	check(queued==nil and ends==1 and #receipts==2,'last original ends the native animation exactly once')
	check(step.poll()=='PASSED' and one.container==to and two.container==to,'both originals have individual receipts')
    end
end
run(false) run(true)
print('PASS '..count..' installed vanilla continuation checks; inventory effects mocked, game NOT RUN')
