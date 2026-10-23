local Chain=require 'EmberRoutesProbe/ProductionChainPlan'
local checks=0
local function check(v,m) checks=checks+1 assert(v,m) end
local function input(kind,count,keep,slot)
    return {types={[kind]=true},choices={kind},count=count or 1,keep=keep==true,slot=slot or 0}
end
local function recipe(id,kind,yield,inputs)
    return {id=id,name=id,signature=id,product=kind,yield=yield,outputs={[kind]=yield},inputs=inputs}
end
local saw=recipe('saw','plank',3,{input('log'),input('saw',1,true,1)})
local mould=recipe('mould','mould',1,{input('plank',2)})
local function run(r,n,stock,index)
    local p=Chain.new(r,n,stock,index or {plank={saw}})
    local slices=0
    while not p.done do p:step(8) slices=slices+1 assert(slices<10000) end
    return p.result,p.reason,p,slices
end
local stock={{id=1,fullType='log'},{id=2,fullType='saw'}}
local p,why,_,slices=run(mould,1,stock)
check(p and #p.nodes==2 and p.nodes[1].recipeId=='saw' and p.nodes[2].recipeId=='mould','log creates missing planks before mould')
check(p.nodes[1].requested==3 and p.claims==2 and slices>1,'round batch up; bounded slices and only original IDs claimed')
p=run(mould,1,{{id=3,fullType='plank'},{id=4,fullType='plank'}})
check(p and #p.nodes==1,'existing materials avoid unnecessary dependencies')
p=run(mould,1,{{id=1,fullType='log'},{id=2,fullType='saw'},{id=3,fullType='plank'}})
check(p and p.nodes[1].requested==3,'only missing amount is requested and rounded')
p,why=run(mould,2,stock)
check(not p and why=='MATERIALS_UNAVAILABLE','one log is not counted twice for four planks')
p=run(mould,3,{{id=1,fullType='log'},{id=2,fullType='saw'},{id=3,fullType='log'}})
check(p and p.nodes[1].requested==6 and p.claims==3,'one saw supports two batches')
local other=recipe('other','plank',3,{input('stone')})
p=run(mould,1,stock,{plank={other,saw}})
check(p and p.nodes[1].recipeId=='saw' and p.claims==2,'failed alternate rolls back its simulated inventory')
local tool=recipe('makeSaw','saw',1,{input('metal')})
p=run(mould,1,{{id=1,fullType='log'},{id=3,fullType='metal'}},{plank={saw},saw={tool}})
check(p and #p.nodes==3 and p.nodes[1].recipeId=='makeSaw','missing tool gets a single precursor')
local cycle=recipe('cycle','log',1,{input('plank')})
p,why=run(mould,1,{{id=2,fullType='saw'}},{plank={saw},log={cycle}})
check(not p and why=='CHAIN_CYCLE','DFS current path rejects cycles')
local a=recipe('a','a',1,{input('b')}) local b=recipe('b','b',1,{input('c')})
local c=recipe('c','c',1,{input('d')}) local d=recipe('d','d',1,{input('e')})
local e=recipe('e','e',1,{input('raw')})
p,why=run(a,1,{{id=1,fullType='raw'}},{b={b},c={c},d={d},e={e}})
check(not p and why=='CHAIN_DEPTH_LIMIT','fifth recipe level is forbidden')
p=run(a,1,{{id=1,fullType='e'}},{b={b},c={c},d={d}})
check(p and #p.nodes==4,'four levels including root allowed')
local pair=recipe('pair','pair',1,{input('plank',1,false,0),input('plank',1,false,1)})
p=run(pair,1,stock)
check(p and #p.nodes==2,'surplus outputs satisfy sibling demand without another log')
p,why=run(mould,1,{{id=1,fullType='log',npcOnly=true},{id=2,fullType='saw'}})
check(not p,'NPC-only inventory is never a new material source')
local denied=recipe('denied','plank',3,{input('log')}) denied.reason='NPC_SKILL_TOO_LOW'
p,why=run(mould,1,stock,{plank={denied}})
check(not p and why=='NPC_SKILL_TOO_LOW','child skill failure is not advertised as craftable')
local woodRod=recipe('woodRod','woodRod',1,{input('wood')})
local metalRod=recipe('metalRod','metalRod',1,{input('metal')})
local either=input('woodRod',2) either.types.metalRod=true either.choices[2]='metalRod'
local frame=recipe('frame','frame',1,{either})
p=run(frame,1,{{id=1,fullType='wood'},{id=2,fullType='metal'}},{woodRod={woodRod},metalRod={metalRod}})
check(p and #p.nodes==3 and p.claims==2,'mixed producible alternatives can split across recipes')
local loop=recipe('loop','plank',1,{input('mould')})
p,why=run(mould,1,{{id=2,fullType='saw'}},{plank={loop,saw}})
check(not p and why=='MATERIALS_UNAVAILABLE','a rejected cyclic alternative does not hide a noncyclic raw shortage')
local dual=recipe('dual','dual',1,{input('tool',1,true,0),input('tool',1,false,1)})
p,why=run(dual,1,{{id=1,fullType='tool'}},{})
check(not p,'one original cannot serve simultaneously as a tool and consumed input')
local flexible=input('x',1,false,0) flexible.types.y=true flexible.choices[2]='y'
local later=input('z',1,false,1) later.types.z2=true later.types.z3=true later.choices={'z','z2','z3'}
local z=recipe('makeZ','z',1,{input('x')})
local needsBoth=recipe('both','both',1,{flexible,later})
p=run(needsBoth,1,{{id=1,fullType='x'},{id=2,fullType='y'}},{z={z}})
check(p and #p.nodes==2,'raw alternative selection backtracks when a later precursor needs the scarce original')
print('PASS production chain plan: '..checks..' checks; pure simulation, no game run')
