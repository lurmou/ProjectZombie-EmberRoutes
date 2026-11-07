-- Load-time FREE definitions and controlled existing-action profiles. No bodies/assets.
local R={LIMIT=64,SCHEMA_VERSION=1}
local definitions,frozen={},false
local behaviors={'SOCIAL','READING','SIT','SMOKE','FITNESS','STROLL','OBSERVE'}
local known={} for _,id in ipairs(behaviors) do known[id]=true end
function R.behaviors()
    local result={} for i,id in ipairs(behaviors) do result[i]=id end return result
end
function R.rules(value)
    if type(value)~='table' then return nil end
    local result,count={},0
    for id,rule in pairs(value) do
        if not known[id] or rule~=0 and rule~=1 and rule~=2 then return nil end
        result[id]=rule count=count+1
    end
    -- Sparse overrides inherit ordinary area rules; an empty override is valid.
    return result,count
end
local function copy(value)
    if type(value)~='table' then return value end
    local result={} for k,v in pairs(value) do result[k]=copy(v) end return result
end
local fields={id=true,schemaVersion=true,definitionVersion=true,mode=true,nameKey=true,descriptionKey=true,
    behaviors=true,defaultRules=true,maxParticipants=true,defaultQuorum=true,defaultDurationHours=true,defaultGatherHours=true,scriptProfile=true}
local function integer(n,min,max) return type(n)=='number' and n==n and n==math.floor(n) and n>=min and n<=max end
local function text(s) return type(s)=='string' and #s>0 and #s<=128 and not s:find('[%c]') end
local function duration(n) return type(n)=='number' and n==n and n>=1/60 and n<=24 end
local function register(def,builtin)
    if frozen then return false,'ACTIVITY_REGISTRY_FROZEN' end
    if type(def)~='table' then return false,'ACTIVITY_DEFINITION_INVALID' end
    for key in pairs(def) do if not fields[key] then return false,'ACTIVITY_DEFINITION_FIELD_UNSUPPORTED' end end
    if not text(def.id) or not builtin and not def.id:match('^[%w_%-]+:[%w_%.%-]+$')
        or def.schemaVersion~=R.SCHEMA_VERSION or not integer(def.definitionVersion,1,1000000)
        or not text(def.nameKey) or not text(def.descriptionKey) then return false,'ACTIVITY_DEFINITION_INVALID' end
    if def.mode~='FREE' and not (def.mode=='SCRIPTED' and def.scriptProfile=='SPEECH_V1')
        or def.mode=='FREE' and def.scriptProfile~=nil then return false,'ACTIVITY_MODE_UNSUPPORTED' end
    if definitions[def.id] then return false,'ACTIVITY_DEFINITION_DUPLICATE' end
    local count=0 for _ in pairs(definitions) do count=count+1 end
    if count>=R.LIMIT then return false,'ACTIVITY_DEFINITION_LIMIT' end
    if not integer(def.maxParticipants,1,256) or not integer(def.defaultQuorum,1,def.maxParticipants)
        or not duration(def.defaultDurationHours) or not duration(def.defaultGatherHours)
        or type(def.behaviors)~='table' then return false,'ACTIVITY_DEFINITION_INVALID' end
    local allowed,list={},{} local total=0
    for key,id in pairs(def.behaviors) do
        total=total+1
        if total>#behaviors or not integer(key,1,#behaviors) or not known[id] or allowed[id] then
            return false,'ACTIVITY_CAPABILITY_UNSUPPORTED'
        end
        allowed[id]=true list[key]=id
    end
    if total==0 or #list~=total then return false,'ACTIVITY_DEFINITION_INVALID' end
    for i=1,total do if list[i]==nil then return false,'ACTIVITY_DEFINITION_INVALID' end end
    local rules=R.rules(def.defaultRules)
    if not rules then return false,'ACTIVITY_DEFINITION_INVALID' end
    for id in pairs(rules) do if not allowed[id] then return false,'ACTIVITY_CAPABILITY_UNSUPPORTED' end end
    if def.mode=='SCRIPTED' and (def.maxParticipants>32 or def.maxParticipants<2 or def.defaultQuorum<2
        or total~=1 or not allowed.OBSERVE or rules.OBSERVE~=1) then return false,'ACTIVITY_DEFINITION_INVALID' end
    definitions[def.id]={id=def.id,schemaVersion=def.schemaVersion,definitionVersion=def.definitionVersion,
        version=def.definitionVersion,mode=def.mode,scriptProfile=def.scriptProfile,nameKey=def.nameKey,descriptionKey=def.descriptionKey,
        behaviors=list,defaultRules=rules,maxParticipants=def.maxParticipants,defaultQuorum=def.defaultQuorum,
        defaultDurationHours=def.defaultDurationHours,defaultGatherHours=def.defaultGatherHours}
    return true
end
function R.register(def) return register(def,false) end
function R.freeze() frozen=true return true end
function R.get(id) return definitions[id] and copy(definitions[id]) end
function R.list()
    local result={} for _,def in pairs(definitions) do result[#result+1]=copy(def) end
    table.sort(result,function(a,b) return a.id<b.id end) return result
end
function R.compatible(id,version)
    local def=definitions[id] return def~=nil and def.definitionVersion==version and (def.mode=='FREE' or def.scriptProfile=='SPEECH_V1')
end
function R.resolve(id,rules)
    local def=definitions[id] if not def then return nil,'ACTIVITY_DEFINITION_MISSING' end
    local values=rules==nil and copy(def.defaultRules) or R.rules(rules)
    if not values then return nil,'ACTIVITY_DATA_INVALID' end
    if def.scriptProfile and values.OBSERVE~=nil and values.OBSERVE~=1 then return nil,'ACTIVITY_CAPABILITY_UNSUPPORTED' end
    local allowed={} for _,key in ipairs(def.behaviors) do allowed[key]=true end
    local result={}
    for _,key in ipairs(behaviors) do
        if not allowed[key] then
            if values[key] and values[key]>0 then return nil,'ACTIVITY_CAPABILITY_UNSUPPORTED' end
            result[key]=0
        elseif values[key]~=nil then result[key]=values[key] end
    end
    if def.scriptProfile then result.OBSERVE=1 end
    return result
end
assert(register({id='FREE_GATHERING',schemaVersion=1,definitionVersion=1,mode='FREE',
    nameKey='IGUI_EmberRoutesProbe_Activity_freeGathering',descriptionKey='IGUI_EmberRoutesProbe_Activity_editorHint',
    behaviors=R.behaviors(),defaultRules={SOCIAL=2,OBSERVE=1},maxParticipants=256,defaultQuorum=2,
    defaultDurationHours=1,defaultGatherHours=1/6},true))
assert(register({id='emberroutes:group_discussion',schemaVersion=1,definitionVersion=1,mode='SCRIPTED',scriptProfile='SPEECH_V1',
    nameKey='IGUI_EmberRoutesProbe_Activity_groupDiscussion',descriptionKey='IGUI_EmberRoutesProbe_Activity_discussionHint',
    behaviors={'OBSERVE'},defaultRules={OBSERVE=1},maxParticipants=32,defaultQuorum=2,
    defaultDurationHours=1,defaultGatherHours=1/6},true))
EmberRoutes=EmberRoutes or {}
EmberRoutes.registerActivity=R.register
-- Canonical command identity, independent of current membership/command epochs.
-- Length prefixes avoid delimiter aliases; the original request remains immutable.
function R.commandKey(args)
    if type(args)~='table' or type(args.roster)~='table' then return nil end
    local definition=args.definitionId or 'FREE_GATHERING'
    local def=definitions[definition] if not def then return nil end
    local duration=args.durationHours or def.defaultDurationHours
    local rules=R.resolve(definition,args.rules)
    if not rules or type(duration)~='number' or duration~=duration then return nil end
    local ids={}
    for key,id in pairs(args.roster) do
        if type(key)~='number' or key<1 or key>256 or key~=math.floor(key) or type(id)~='string' or #id>128 then return nil end
        ids[#ids+1]=id if #ids>256 then return nil end
    end
    if #ids==0 then return nil end table.sort(ids)
    local parts={}
    local function put(v)
        local s=tostring(v) parts[#parts+1]=tostring(#s)..':'..s
    end
    put(type(args.name)=='string' and args.name:match('^%s*(.-)%s*$') or '')
    put(args.settlementId) put(args.zoneId) put(args.zoneRevision)
    put(definition) put(args.definitionVersion or (definitions[definition] and definitions[definition].definitionVersion) or 0)
    put(args.organizerId or args.roster[1]) put(args.quorum or math.min(def.defaultQuorum,#ids))
    if def.scriptProfile then put(def.scriptProfile) put(args.speakerId or args.organizerId or args.roster[1]) end
    put(duration) put(args.gatherHours or math.min(duration,def.defaultGatherHours))
    for _,id in ipairs(ids) do put(id) end
    for _,id in ipairs(behaviors) do put(id) put(rules[id]==nil and '-' or rules[id]) end
    local result=table.concat(parts,'|')
    return #result<=65536 and result or nil
end
return R
