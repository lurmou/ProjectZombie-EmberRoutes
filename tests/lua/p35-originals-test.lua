local queued,live,eaten=nil,true,0 local inv={}
local values={} inv.getItems=function() return {size=function() return #values end,get=function(_,i) return values[i+1] end} end
local required={contains=function(_,v) return v=='Base.Lighter' end}
local item={where=inv,getID=function() return 1 end,getFullType=function() return 'Base.CigaretteSingle' end,
    getRequireInHandOrInventory=function() return required end,getUses=function() return 1 end,
    getContainer=function(self) return self.where end}
local fire={uses=0.5,getID=function() return 2 end,getFullType=function() return 'Base.Lighter' end,
    getCurrentUsesFloat=function(self) return self.uses end,getUseDelta=function() return 0.1 end,getContainer=function() return inv end}
values={item,fire}
local npc={getInventory=function() return inv end}
package.loaded['EmberRoutesProbe/LaborStore']={owner=function() end,validPersonal=function(_,_,key) return key=='item:2' end}
package.loaded['TimedActions/ISEatFoodAction']=true
ISEatFoodAction={new=function(_,who,food)
    return {start=function(self) local f=self:getRequiredItem() f.uses=f.uses-0.1 end,update=function() end,
        complete=function() eaten=eaten+1 food.where=nil return true end,
        stop=function() queued=nil end,perform=function() queued=nil end}
end}
ISTimedActionQueue={hasAction=function(a) return queued==a end}
local function context()
    return {npc=npc,job={},payload={itemId=1,leisure={activity='SMOKE',fireId=2}},persist=function() return true end,
        valid=function() return live end,sameAttempt=function() return live end,
        body={retained=function() return live end,add=function(a) queued=a a:start() return true end,
            clear=function() if queued then queued:stop() end return true end}}
end
local Smoke=require 'EmberRoutesProbe/LeisureSmoke'
local chosen,done=Smoke.find(npc,{scan=8},{}) assert(done and chosen.item==item and chosen.fire==fire)
local c=context() local leaf=Smoke.new(c)
assert(leaf.run()=='Running' and fire.uses==0.4,'native start consumes the selected real ignition source')
local a=queued a:start() assert(fire.uses==0.4,'duplicate native start cannot consume ignition twice') a:complete() a:complete() a:perform()
assert(eaten==1 and leaf.run()=='Success','same native original consumed once')
live=false a:start() a:complete() assert(eaten==1 and fire.uses==0.4,'old callbacks cannot consume new supplies')
live=true item.where=inv local d=context() local partial=Smoke.new(d)
partial.run() local b=queued b:stop()
assert(eaten==1 and d.payload.leisure.after==1,'early stop retains cigarette, preserves actual ignition use')
item.where={} local e=context() local missing=Smoke.new(e)
assert(missing.run()=='Failure','foreign original is never substituted')
print('P3.5 smoking: claimed original/ignition, partial start, duplicate and stale callbacks')
