-- Production reading leaf; native action is a contract-shaped double.
package.loaded['TimedActions/ISReadABook']=true
package.loaded['EmberRoutesProbe/Leisure/LibraryIndex']={useful=function() return true end}
package.loaded['EmberRoutesProbe/Kernel/RuntimeMetrics']={active=function() return false end}
package.loaded['EmberRoutesProbe/Leisure/StudyService']={completed=function() end}
local queued local learned=0
local root={}
local item={getContainer=function() return root end,getID=function() return 7 end,getFullType=function() return 'Base.Magazine' end,
 getNumberOfPages=function() return 0 end,getAlreadyReadPages=function() return 0 end}
local npc={getInventory=function() return root end,tooDarkToRead=function() return false end,getAlreadyReadPages=function() return 0 end}
ISReadABook={new=function()
 return {isValid=function() return true end,start=function() end,update=function() end,
 displayPrintMedia=function() error('NPC opened player media UI') end,
 revealPrintMediaLocationsOnMap=function() error('NPC changed player world map') end,
 complete=function(self) learned=learned+1 self:revealPrintMediaLocationsOnMap() return true end,
 perform=function(self) self:displayPrintMedia() queued=nil end,stop=function() queued=nil end}
end}
ISTimedActionQueue={hasAction=function(a) return a==queued end}
local c={npc=npc,job={npcId='n'},effects='KNOWN',payload={attemptId='a',itemId=7,study={orderId='assigned-study'}},
 persist=function() return true end,valid=function() return true end,sameAttempt=function() return true end,
 body={current=function() return true end,retained=function() return true end,add=function(a) queued=a return true end}}
local leaf=require('EmberRoutesProbe/Leisure/StudyActions').read(c,item)
assert(leaf.run()=='Running') local action=queued action:start() action:complete() action:perform()
assert(learned==1 and leaf.run()=='Success' and c.effects=='KNOWN','assigned study preserves character effects without player UI/map side effects')
print('PASS assigned NPC study UI boundary; native reading engine NOT RUN')
