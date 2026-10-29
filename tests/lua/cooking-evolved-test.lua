-- Installed take-water and add-item Lua; actual native effects/world deliberately mocked.
local w=dofile('tests/lua/cooking-water-test.lua') local f=w.f
f.queue(nil)
local checks=0 local function check(v,m) checks=checks+1 assert(v,m) end
local Record=require 'EmberRoutesProbe/CookingRecord'
local Context=require 'EmberRoutesProbe/CookingContext'
local Food=require 'EmberRoutesProbe/CookingFood'
local Evolved=require 'EmberRoutesProbe/CookingEvolved'
local additions=0 local recipe={}
function recipe:getOriginalname() return 'Soup' end function recipe:getBaseItem() return 'Base.Pot' end
function recipe:getFullResultItem() return 'Base.PotOfSoupRecipe' end
function recipe:getMaxItems() return 6 end function recipe:getMinimumWater() return .9 end
function recipe:isCookable() return true end function recipe:getUntranslatedName() return 'Soup' end
function recipe:getAddIngredientSound() end
function recipe:isResultItem(item) return item.kind=='Base.PotOfSoupRecipe' end
function recipe:hasMinimumWater(item) return item.fluid and item.fluid.kind=='Water' and item.fluid.amount/item.fluid.capacity>=.9 or false end
function recipe:isItemUsableInRecipe(_,_,id) return type(id)=='number' end
function recipe:getItemsCanBeUse() return {contains=function() return true end} end
function recipe:isSpiceAdded(base,item) return base.spices and base.spices:contains(item.kind) or false end
function recipe:addItem(base,ingredient)
    additions=additions+1
    local output=base
    if not base.food then
        assert(self:hasMinimumWater(base),'native minimum-water gate before first ingredient')
        f.root:Remove(base) output=f.item('Base.PotOfSoupRecipe',true) output.raw=0
    end
    ingredient.raw=ingredient.raw-.05
    if ingredient.spice then
        output.spices=output.spices or f.list({}) output.spices[#output.spices+1]=ingredient.kind output.raw=output.raw+.02
    else
        output.extra=output.extra or f.list({}) output.extra[#output.extra+1]=ingredient.kind output.raw=output.raw+.08
    end
    return output
end
local function setup(kinds)
    local c,pot=w.setup()
    function pot.fluid:isFilledWithCleanWater() return self.kind=='Water' and self.amount>0 end
    w.row.slots={{object=w.source(1,10)}} w.row.version=w.row.version+1
    local inputs={} local j=Record.copy(c.job)
    for _,kind in ipairs(kinds) do
        local item=f.item(kind,true) item.spice=kind~='Base.Carrot' and kind~='Base.Potato'
        inputs[#inputs+1]=item
        j.payload.assets[#j.payload.assets+1]={id=item.id,fullType=kind,custody='HELD',role='INPUT'}
        j.payload.claims[#j.payload.claims+1]='item:'..item.id
    end
    assert(Context.publish(c,j))
    return c,pot,inputs
end
local function tick(c,node,perform)
    c.budget={nodes=16,scan=4,paths=1}
    local state=node.run()
    local action=f.queued()
    if action and perform~=false then action:start() action:complete() action:perform() end
    return state
end
local function finish(c,node)
    for _=1,200 do local state=tick(c,node) if state~='Running' then assert(state=='Success',tostring(c.reason)) return end end
    error('evolved chain did not finish')
end
local c,pot,inputs=setup({'Base.Salt','Base.Carrot','Base.Carrot','Base.Carrot','Base.Salt','Base.Pepper','Base.HotSauce'})
local start=additions local node=assert(Evolved.new(c,recipe,pot,inputs,.12))
finish(c,node)
check(c.job.payload.evolved.completed and c.job.payload.sequence==5,'same Job sequences one water fill, two main additions and two optional spices')
check(additions==start+4 and c.job.payload.spiceCount==2,'main target stops early, duplicate salt and third spice are skipped')
check(math.abs(c.job.payload.evolved.mainEffective-.16)<.000001,'spices never inflate the stored main-ingredient fullness target')
local ref=Record.outputReference(c.job,c.job.payload.evolved.baseSequence,1)
local actual=assert(Record.resolveOutput(c.job,ref))
check(actual.id~=pot.id and actual.fullType=='Base.PotOfSoupRecipe' and not pot:getContainer(),
    'subsequent additions follow the observed replacement original, not the consumed empty pot')
local output
for _,item in ipairs(f.root.items) do if item.id==actual.id then output=item end end
check(output and output.extra:size()==2 and output.spices:size()==2 and not Food.read(output).ready,
    'prepared raw soup stays owned and is not falsely declared cooked or delivered')
local calls=additions finish(c,assert(Evolved.new(c,recipe)))
check(additions==calls,'completed chain replay only observes saved original binding')
local forged=Record.copy(c.job) forged.payload.evolved.target=.9
check(not require('EmberRoutesProbe/TaskJobs').current():update(forged.id,forged.revision,{payload=forged.payload}),
    'saved mixture target and input plan cannot be rewritten between steps')
local resumed,base,ingredients=setup({'Base.Carrot','Base.Potato'})
local run=assert(Evolved.new(resumed,recipe,base,ingredients,.12)) start=additions
for _=1,100 do
    tick(resumed,run)
    local a=resumed.job.payload.attempt
    if a and a.kind=='ADD' and a.state=='APPLIED' then break end
end
check(resumed.job.payload.evolved.cursor==1 and resumed.job.payload.evolved.activeSequence~=nil,
    'receipt may persist before the next ingredient cursor is published')
finish(resumed,assert(Evolved.new(resumed,recipe)))
check(additions==start+2 and resumed.job.payload.evolved.completed,
    'resume acknowledges the completed ingredient once and does not add it again')
print('PASS '..checks..' evolved-mixture checks; installed water/add Lua, mocked engine; game NOT RUN')
return {w=w,recipe=recipe,setup=setup,finish=finish,Evolved=Evolved}
