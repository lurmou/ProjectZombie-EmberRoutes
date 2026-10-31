local R=require 'EmberRoutesProbe/ActivityRegistry'
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end
local function definition(id)
    return {id=id,schemaVersion=1,definitionVersion=1,mode='FREE',nameKey='IGUI_Test_Name',descriptionKey='IGUI_Test_Description',
        behaviors={'OBSERVE'},defaultRules={OBSERVE=1},maxParticipants=3,defaultQuorum=1,defaultDurationHours=.5,defaultGatherHours=.1}
end
local a=definition('qa:quiet')
check(EmberRoutes.registerActivity(a),'controlled public registration accepts existing FREE capabilities')
a.behaviors[1]='SOCIAL' a.defaultRules.OBSERVE=0
check(R.get('qa:quiet').behaviors[1]=='OBSERVE' and R.get('qa:quiet').defaultRules.OBSERVE==1,'caller mutation cannot modify the definition')
local detached=R.get('qa:quiet') detached.maxParticipants=200
check(R.get('qa:quiet').maxParticipants==3,'published definitions are detached')
check(not R.register(definition('qa:quiet')),'duplicate IDs never replace definitions')
local bad=definition('qa:scripted') bad.mode='SCRIPTED'
check(not R.register(bad),'unsupported execution modes are not advertised as runnable')
bad=definition('qa:callback') bad.apply=function() end
check(not R.register(bad),'raw callbacks cannot bypass original-item and body authority')
bad=definition('qa:music') bad.behaviors={'MUSIC'}
check(not R.register(bad),'unknown native capabilities are rejected')
local rules=assert(R.resolve('qa:quiet',{}))
check(rules.OBSERVE==nil and rules.SOCIAL==0,'inheritance and the supported capability boundary are distinct')
check(R.resolve('qa:quiet').OBSERVE==1,'omitted rule object uses definition defaults')
check(not R.resolve('qa:quiet',{SOCIAL=2}),'an override cannot enable a capability absent from the definition')
for i=1,R.LIMIT-#R.list() do assert(R.register(definition('qa:fill'..i))) end
check(not R.register(definition('qa:overflow')),'definition storage is bounded')
R.freeze()
local ok,why=R.register(definition('qa:late'))
check(not ok and why=='ACTIVITY_REGISTRY_FROZEN','runtime registration cannot change running semantics')
print('activity-registry: '..checks..' PASS (pure scalar definitions; no game run)')
