-- Bounded selector uses actual shared warehouse access and original identity.
local f=dofile('tests/lua/cooking-collection-test.lua') local h=f.h local e=h.e local host=h.f
local Menu=require 'EmberRoutesProbe/CookingMenu'
local Evolved=require 'EmberRoutesProbe/CookingEvolved'
local Record=require 'EmberRoutesProbe/CookingRecord'
local Store=require 'EmberRoutesProbe/LaborStore'
local Jobs=require('EmberRoutesProbe/TaskJobs').current()
local recipe=e.recipe
function recipe:getItemRecipe(item)
    if item.food then return {getUse=function() return item.spice and 1 or 10 end} end
end
function recipe:needToBeCooked() return true end
local manager={getAllEvolvedRecipes=function() return host.list({recipe}) end,
    getItem=function(_,id) if id=='Base.PotOfSoupRecipe' then return {getActualWeight=function() return 3 end} end end}
function getScriptManager() return manager end
assert(Evolved.recipe('Soup')==recipe)
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local pot=host.item('Base.Pot',false,f.source.container)
pot.fluid={amount=10,capacity=10,kind='Water',getAmount=function(self) return self.amount end,
    getCapacity=function(self) return self.capacity end,isPureFluid=function() return true end}
function pot:getFluidContainer() return self.fluid end
local urgent=host.item('Base.Potato',true,f.source.container)
function urgent:getAge() return .99 end function urgent:getOffAgeMax() return 1 end
local later=host.item('Base.Carrot',true,f.source.container)
function later:getAge() return .1 end function later:getOffAgeMax() return 2 end
local salt=host.item('Base.Salt',true,f.source.container) salt.spice=true
f.source.object.filter.types['Base.Salt']=true
local remote=h.endpoint('seasoning-only',9,{'Base.Pepper'})
local pepper=host.item('Base.Pepper',true,remote.container) pepper.spice=true
f.stove.object.powered=true
h.setCandidates({f.source.id,f.cold.id,f.stove.id,remote.id})
local function finish(q)
    for _=1,5000 do local done,why=q:step(1) assert(done~=nil,why) if done then return q:result() end end
    error('menu cursor failed to finish')
end
local q=assert(Menu.new(h.entry,host.npc,.15))
check(q:result()==nil,'unfinished menu never publishes a usable selection')
local selection=assert(finish(q))
check(selection.base.id==pot.id and selection.entries[1].id==urgent.id,'native base and nearest-to-spoil safe ingredient are selected by original ID')
local selected,spices={},0
for _,row in ipairs(selection.entries) do selected[row.id]=true if row.item:isSpice() then spices=spices+1 end end
check(spices<=2 and selected[salt.id] and not selected[pepper.id],'optional seasoning stays on already-required pantry stops')
check(not Store.owner(urgent.id) and urgent:getContainer()==f.source.container,'planning does not consume, move or claim an ingredient')
local job=assert(Record.new('menu-prepare',host.npc.id,'kitchen','Soup','AUTO','policy:kitchen',.15,.2))
check(Evolved.prepare(job,selection.recipe,selection)~=nil,'native-derived selection plugs into existing exact-original preparation contract')
local held=assert(Record.new('menu-claim','other-menu-chef','kitchen','Soup','REQUEST','request:menu',.1,.1))
held.payload.assets={{id=urgent.id,fullType=urgent.kind,custody='SOURCE',role='INPUT'}} held.payload.claims={'item:'..urgent.id}
assert(Jobs:create(held)) assert(Store.claimCooking(Jobs:get(held.id)))
check(q:result()==nil,'a later physical claim fences even an already-completed menu')
local unknown=assert(Menu.new(h.entry,host.npc,.15,'MissingModRecipe'))
local value,why=finish(unknown)
check(not value and why=='COOKING_MATERIALS_UNAVAILABLE','missing recipe never silently substitutes another dish')
print('PASS native-fact menu selection boundaries; native recipe/world mocked, game NOT RUN')
