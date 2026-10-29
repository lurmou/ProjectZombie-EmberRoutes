package.path="Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;"..package.path
local Filter=require "EmberRoutesProbe/StorageFilter"
local Editor=require "EmberRoutesProbe/FilterEditor"
local count=0
local function check(value,why) count=count+1 assert(value,why) end
local function desc(fullType,display,category,food,perishable,ranged)
    return {fullType=fullType,display=display or "",category=category or "normal",food=food,perishable=perishable,ranged=ranged}
end
local fresh=desc("OtherMod.Apple","food","food",true,true)
local canned=desc("OtherMod.Tin","food","food",true,false)
local gun=desc("GunsMod.Rifle","weapon","weapon",false,false,true)
local ammo=desc("AmmoMod.Rounds","ammo")
local unknown=desc("UnknownMod.Mystery","unrecognized")
local config=Filter.new()
check(not Filter.matchesDescription(config,fresh),"unselected groups do not accept items")
Filter.setGroup(config,"food",true)
check(Filter.matchesDescription(config,fresh) and Filter.matchesDescription(config,canned),"group includes child classes for third-party items")
config.groups["food.perishable"]=false
check(not Filter.matchesDescription(config,fresh) and Filter.matchesDescription(config,canned),"child exclusion overrides parent")
config.types[fresh.fullType]=true
check(Filter.matchesDescription(config,fresh),"specific type inclusion overrides child")
config.types[canned.fullType]=false
check(not Filter.matchesDescription(config,canned),"specific type exclusion overrides parent")
config.private=true
check(not Filter.access(config) and not Filter.matchesDescription(config,fresh),"private guard overrides exact allowed type")
config.private=false config.enabled=false
check(not Filter.access(config),"disabled config forbids inspection and transfer")
config.enabled=true
local clone=Filter.copy(config) clone.types[fresh.fullType]=false
check(config.types[fresh.fullType]==true,"editing a clone cannot mutate live config")
check(not Filter.copy({format=2}),"future unsupported format rejected")
config.groups.extra="bad"
check(not Filter.copy(config),"nonboolean rule rejected") config.groups.extra=nil
local excessive=Filter.new()
for i=1,257 do excessive.types["Mod.Item"..i]=true end
check(not Filter.copy(excessive),"unbounded per-item rules rejected")
Filter.setGroup(config,"weapons",true)
check(Filter.matchesDescription(config,gun) and Filter.matchesDescription(config,ammo),"guns and ammunition share a configurable parent")
check(not Filter.matchesDescription(config,unknown),"unrecognized mod category not admitted accidentally")
Filter.setGroup(config,"other",true)
check(Filter.matchesDescription(config,unknown),"unknown category can be explicitly included")
Filter.registerCategory("chemicals",nil,{0.4,0.8,0.6})
Filter.registerClassifier("chemicals-adapter",function(d) if d.display=="chemistry" then return "chemicals" end end)
config.groups.chemicals=true
check(Filter.matchesDescription(config,desc("ChemMod.Acid","chemistry")),"registered mod classifier extends without changing executor")
check(not pcall(Filter.registerCategory,"chemicals"),"duplicate category registration rejected")
check(not Filter.access(Filter.legacy(nil)) and not Filter.access(Filter.legacy("private")),"legacy unconfigured/private stay private")
check(Filter.matchesDescription(Filter.legacy("food"),canned) and not Filter.matchesDescription(Filter.legacy("food"),gun),"legacy tag maps conservatively")
check(Filter.matchesDescription(Filter.legacy("outbox"),unknown),"legacy explicit outbound remains broad")
local model=Editor.new(config,{{fullType=fresh.fullType,node="food.perishable"}})
local group={kind="group",id="food"}
check(Editor.mark(model,group)=="[-]","partial subtree shown mixed")
Editor.toggle(model,group)
check(model.draft.groups.food and model.draft.groups["food.perishable"]==nil,"parent select resets child category exclusions")
check(model.draft.types[canned.fullType]==false,"parent select preserves explicit item exceptions")
local typeRow={kind="type",id="Mod.Type"}
Editor.toggle(model,typeRow) check(model.draft.types["Mod.Type"]==true,"type cycle allows")
Editor.toggle(model,typeRow) check(model.draft.types["Mod.Type"]==false,"type cycle denies")
Editor.toggle(model,typeRow) check(model.draft.types["Mod.Type"]==nil,"type cycle returns to inherited")
Editor.all(model,false)
check(next(model.draft.types)==nil and not Editor.value(model.draft,"food"),"clear removes stale exceptions")
Editor.all(model,true)
check(Editor.value(model.draft,"weapons.ammo"),"select all covers descendants")
check(config.groups["food.perishable"]==false,"editor still holds only a draft")
local rows=Editor.rows(model)
local found=false for _,row in ipairs(rows) do if row.kind=="type" and row.id==fresh.fullType then found=true end end
check(found,"visible container item offers fullType override")
Filter.registerCategory("food.stable.modsub","food.stable")
local ordered=Filter.treeOrder()
local parentPosition,childPosition
for i,id in ipairs(ordered) do
    if id=="food.stable" then parentPosition=i end
    if id=="food.stable.modsub" then childPosition=i end
end
check(childPosition==parentPosition+1,"registered descendants appear in tree order rather than at end")
local denied=Filter.new() denied.groups.food=true denied.groups["food.stable"]=false denied.groups["food.perishable"]=false denied.groups["food.meals"]=false
check(#Filter.badges(denied)==0,"fully excluded subtree does not show an allowed storage badge")
denied.types[fresh.fullType]="invalid"
check(not Filter.matchesDescription(denied,fresh),"malformed stored rule cannot grant access by truthiness")
print("PASS "..count.." storage filter/editor policy checks; engine UI NOT RUN")
