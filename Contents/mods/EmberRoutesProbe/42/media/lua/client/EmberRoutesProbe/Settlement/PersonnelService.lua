-- Selected-member projection. UI owns/relinquishes the cache; no world scanning
-- or character handles escape through the returned display rows.
local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Jobs=require 'EmberRoutesProbe/Runtime/TaskJobs'
local Clock = require 'EmberRoutesProbe/Kernel/Clock'
local Service={}
local world,cache=nil,{}
local portraits,portraitListeners={},{}
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end
local function professionTitle(value)
    if type(value)~='string' then return end
    value=(getTextOrNull and getTextOrNull(value)) or value
    if value:match('^IGUI_') or value:match('^UI_') then return end
    return value
end
local function load()
    local root=Registry.data() if root~=world then world,cache=root,{} portraits={} end
end
-- Only selected, visible consumers own portraits. Shared engine textures are never destroyed.
local portraitClock=0
local function notifyPortrait(id)
    if portraits[id] then portraits[id].dirty=true end
    for _,callback in ipairs(portraitListeners) do callback(id) end
end
function Service.watchPortrait(callback)
    portraitListeners[#portraitListeners+1]=callback
    local function changed(character)
        local ids={}
        for id,row in pairs(portraits) do if row.character==character then ids[#ids+1]=id end end
        for _,id in ipairs(ids) do notifyPortrait(id) end
    end
    local events={}
    for _,key in ipairs({'OnClothingUpdated','OnEquipPrimary','OnEquipSecondary'}) do
        local event=Events and Events[key]
        if event and event.Add and event.Remove then event.Add(changed) events[#events+1]=event end
    end
    local live=true
    return function()
        if not live then return end live=false
        for _,event in ipairs(events) do event.Remove(changed) end
        for i=#portraitListeners,1,-1 do if portraitListeners[i]==callback then table.remove(portraitListeners,i) break end end
    end
end
function Service.releasePortrait(id,owner)
    local row=portraits[id]
    if not row then return end
    row.owners[owner or Service]=nil
    local held=false for _ in pairs(row.owners) do held=true break end
    if not held then portraits[id]=nil end
end
function Service.invalidate(id) load() cache[id]=nil notifyPortrait(id) end
function Service.release(id) if id then cache[id]=nil end end
require('EmberRoutesProbe/Kernel/Boot').invalidatePersonnel=Service.invalidate
local function resolveParentCategory(parent)
    if not parent or (Perks and parent==Perks.None) then return nil end
    local raw=nil
    if type(parent)=='table' and parent.getName then
        local ok,n=pcall(function() return parent:getName() end)
        if ok and type(n)=='string' and n~='' then raw=n end
    end
    if not raw then raw=tostring(parent or 'General') end
    raw=raw:gsub('^Perks%.', '')
    if getTextOrNull then
        local tr=getTextOrNull('IGUI_perks_'..raw)
        if tr then return tr end
        local stripped=raw:gsub('Category$', '')
        local trStripped=getTextOrNull('IGUI_perks_'..stripped)
        if trStripped then return trStripped end
    end
    return raw
end

local function readCraftSkill(handle)
    if not handle or not handle.getPerkLevel or not Perks then return nil end
    local maxLvl=nil
    local craftingPerks={Perks.Woodwork,Perks.MetalWelding,Perks.Blacksmith,Perks.Electricity,Perks.Mechanics,Perks.Tailoring,Perks.Cooking}
    for _,perk in ipairs(craftingPerks) do
        if perk then
            local ok,lvl=pcall(function() return handle:getPerkLevel(perk) end)
            if ok and type(lvl)=='number' then if maxLvl==nil or lvl>maxLvl then maxLvl=lvl end end
        end
    end
    return maxLvl
end

local function readHaulSkill(handle)
    if not handle or not handle.getPerkLevel or not Perks then return nil end
    local maxLvl=nil
    local haulingPerks={Perks.Strength,Perks.Fitness}
    for _,perk in ipairs(haulingPerks) do
        if perk then
            local ok,lvl=pcall(function() return handle:getPerkLevel(perk) end)
            if ok and type(lvl)=='number' then if maxLvl==nil or lvl>maxLvl then maxLvl=lvl end end
        end
    end
    return maxLvl
end

local function readCookSkill(handle)
    if not handle or not handle.getPerkLevel or not Perks or not Perks.Cooking then return nil end
    local ok,lvl=pcall(function() return handle:getPerkLevel(Perks.Cooking) end)
    if ok and type(lvl)=='number' then return lvl end
    return nil
end

local function readAvatarInfo(handle)
    local desc=nil
    if handle and handle.getDescriptor then
        local ok,d=pcall(function() return handle:getDescriptor() end)
        if ok then desc=d end
    end
    local isFemale=false
    if desc and desc.isFemale then
        local ok,f=pcall(function() return desc:isFemale() end)
        if ok then isFemale=f end
    elseif handle and handle.isFemale then
        local ok,f=pcall(function() return handle:isFemale() end)
        if ok then isFemale=f end
    end

    local profTitle=nil
    local profTexture=nil
    if desc then
        if CharacterProfessionDefinition and desc.getCharacterProfession then
            local okDef,def=pcall(function() return CharacterProfessionDefinition.getCharacterProfessionDefinition(desc:getCharacterProfession()) end)
            if okDef and def then
                pcall(function()
                    profTitle=def:getUIName()
                    profTexture=def:getTexture()
                end)
            end
        end
        if not profTexture and desc.getProfession then
            pcall(function()
                local pName=desc:getProfession()
                if pName and pName~='' then
                    profTitle=profTitle or (getTextOrNull and getTextOrNull('UI_prof_'..pName)) or pName
                    if tryGetTexture then
                        profTexture=tryGetTexture('media/ui/Professions/icon_'..pName..'.png')
                            or tryGetTexture('media/ui/professions/'..pName..'.png')
                    end
                end
            end)
        end
    end
    return isFemale,professionTitle(profTitle),profTexture
end

local function getStatVal(char,sel,statName,statEnum)
    if sel and sel[statName]~=nil then return sel[statName] end
    if sel and sel.stats and sel.stats[statName]~=nil then return sel.stats[statName] end
    if not char or not char.getStats then return nil end
    local ok,stats=pcall(function() return char:getStats() end)
    if not ok or not stats then return nil end
    if statEnum and CharacterStat and CharacterStat[statEnum] and stats.get then
        local okVal,val=pcall(function() return stats:get(CharacterStat[statEnum]) end)
        if okVal and type(val)=='number' then return val end
    end
    local methodName='get'..string.upper(string.sub(statName,1,1))..string.sub(statName,2)
    if stats[methodName] then
        local okVal,val=pcall(function() return stats[methodName](stats) end)
        if okVal and type(val)=='number' then return val end
    end
    if type(stats[statName])=='number' then return stats[statName] end
    return nil
end

local function readBodyDamage(handle,w)
    local health=w and w.health
    local isBleeding=w and w.isBleeding or false
    local isInfected=w and w.isInfected or false
    local hasInjury=w and w.hasInjury or false
    if handle and handle.getBodyDamage then
        local okBd,bd=pcall(function() return handle:getBodyDamage() end)
        if okBd and bd then
            if health==nil and bd.getOverallBodyHealth then
                local okH,h=pcall(function() return math.floor(bd:getOverallBodyHealth()) end)
                if okH and type(h)=='number' then health=h end
            end
            pcall(function()
                if bd.getNumPartsBleeding and bd:getNumPartsBleeding()>0 then isBleeding=true end
                if bd.isInfected and bd:isInfected() then isInfected=true end
                if bd.hasInjury and bd:hasInjury() then hasInjury=true end
            end)
        end
    end
    return health,isBleeding,isInfected,hasInjury
end

local function static(npc)
    local value={skills={},knowledge={},traits={}}
    if not npc then return value end
    if PerkFactory and PerkFactory.PerkList and Perks and npc.getPerkLevel then
        local list=PerkFactory.PerkList
        for i=0,math.min(list:size(),128)-1 do
            local perk=list:get(i)
            if perk:getParent()~=Perks.None then
                local multiplier=npc.getXp and npc:getXp():getMultiplier(perk) or nil
                local parent=perk:getParent()
                local parentName=resolveParentCategory(parent)
                value.skills[#value.skills+1]={
                    name=perk:getName(),
                    level=npc:getPerkLevel(perk),
                    multiplier=multiplier,
                    parent=parentName,
                    parentType=type(parent)=='table' and parent.getType and parent:getType() or parent
                }
            end
        end
        table.sort(value.skills,function(a,b) return a.name<b.name end)
    end
    local known=npc.getKnownRecipes and npc:getKnownRecipes()
    value.knownCount=known and known:size() or nil
    if known then
        for i=0,math.min(known:size(),4096)-1 do
            local name=known:get(i)
            value.knowledge[#value.knowledge+1]=Translator and Translator.getRecipeName(name) or name
        end
        table.sort(value.knowledge)
    end
    local traits=npc.getCharacterTraits and npc:getCharacterTraits():getKnownTraits()
    if traits and CharacterTraitDefinition then
        for i=0,math.min(traits:size(),128)-1 do
            local def=CharacterTraitDefinition.getCharacterTraitDefinition(traits:get(i))
            if def then value.traits[#value.traits+1]=def:getLabel() end
        end
    end
    value.craftSkill=readCraftSkill(npc)
    value.haulSkill=readHaulSkill(npc)
    value.cookSkill=readCookSkill(npc)
    local isFemale,profTitle,profTexture=readAvatarInfo(npc)
    value.isFemale=isFemale
    value.profTitle=profTitle
    value.profTexture=profTexture
    return value
end
local function readPortrait(binding,id,owner)
    local now=Clock.nowMs()
    local row=portraits[id]
    if row and row.character~=binding.handle then portraits[id]=nil row=nil end
    if not row then
        local count,oldest,oldTime=0,nil,math.huge
        for key,value in pairs(portraits) do
            count=count+1
            if value.touched<oldTime then oldest,oldTime=key,value.touched end
        end
        if count>=16 then portraits[oldest]=nil end
        local _,_,icon=readAvatarInfo(binding.handle)
        row={character=binding.handle,owners={},snapshot={icon=icon},retryAt=0}
        portraits[id]=row
    end
    row.owners[owner or Service]=true
    portraitClock=portraitClock+1 row.touched=portraitClock
    if row.dirty or not row.snapshot.texture and now>=row.retryAt then
        row.dirty=false
        local texture
        if EmberRoutesProbeJava and EmberRoutesProbeJava.getPortraitTexture then
            texture=EmberRoutesProbeJava.getPortraitTexture(binding.handle)
        end
        row.snapshot={texture=texture,icon=row.snapshot.icon}
        row.retryAt=now+1000
    end
    return row.snapshot
end
function Service.portrait(actor,scope,id,force,owner)
    load()
    if not require('EmberRoutesProbe/Settlement/SettlementLedger').view(actor,scope) then return end
    local binding=Driver.bindId(actor,id)
    if not binding or not Driver.valid(binding) then return end
    return readPortrait(binding,id,owner)
end
function Service.squadPortrait(actor,id,owner)
    load()
    local Membership=require 'EmberRoutesProbe/Settlement/MembershipService'
    local allowed=false
    for _,memberId in ipairs(Membership.squad(actor)) do if memberId==id then allowed=true break end end
    if not allowed then return end
    local binding=Driver.bindId(actor,id)
    if not binding or not Driver.valid(binding) then return end
    return readPortrait(binding,id,owner)
end
function Service.details(actor,scope,id,force)
    load()
    if not require('EmberRoutesProbe/Settlement/SettlementLedger').view(actor,scope) then return end
    local binding=Driver.bindId(actor,id)
    if not binding or not Driver.valid(binding) then return end
    local row=cache[id]
    if force or not row or row.npc~=binding.handle then
        row={npc=binding.handle,value=static(binding.handle)} cache[id]=row
    end
    local value=row.value
    -- Detached summary of the current recurring routine; never exposes payload
    -- mutation or a native action to the page.
    local result={skills=value.skills,knowledge=value.knowledge,knownCount=value.knownCount,traits=value.traits,
        membership=require('EmberRoutesProbe/Settlement/MembershipService').view(id)}
    if binding.handle.getStats and CharacterStat then
        local stats=binding.handle:getStats()
        if stats and stats.get then
            result.mood={}
            for _,key in ipairs({'STRESS','UNHAPPINESS','BOREDOM','PANIC'}) do
                if CharacterStat[key] then result.mood[key]=stats:get(CharacterStat[key]) end
            end
        end
    end
    local personal=Jobs.current():forNpc(id,'SELF_CARE')[1]
    if personal and personal.payload.kind=='STUDY' then
        local p=personal.payload local read=p.reading
        result.study={step=p.step,reason=p.reason,unknown=personal.effects=='UNKNOWN',
            book=read and read.fullType,pages=read and read.pages,total=read and read.total,
            borrowed=p.step~='IDLE' and p.sourceId~=nil,completed=read and read.completed}
    end
    local Probe=require 'EmberRoutesProbe/Kernel/Boot'
    result.leisure=personal and personal.payload.step~='IDLE' and personal.payload.leisure and personal.payload.leisure.activity
    result.tools=require('EmberRoutesProbe/Field/ToolCustodyMonitor').assets(id,binding.handle)
    result.studyReason=Probe.studyStatus and Probe.studyStatus(id)
    return result
end
function Service.enrichWorkers(actor,scope,rawWorkers)
    load()
    local okDriver,Driver=pcall(require,'EmberRoutesProbe/Runtime/Driver')
    local Public=require 'EmberRoutesProbe/Work/OrderQuery'
    local list={}
    for _,w in ipairs(rawWorkers or {}) do
        local id=w.id
        local p=Public.priorities(id)
        local binding=okDriver and Driver and Driver.bindId and Driver.bindId(actor,id)
        local handle=binding and binding.handle
        local row=cache[id]
        if not row or row.npc~=handle then
            row={npc=handle,value=static(handle)}
            cache[id]=row
        end
        local staticVal=row.value
        local health,isBleeding,isInfected,hasInjury=readBodyDamage(handle,w)
        local fatigue=getStatVal(handle,w,'fatigue','FATIGUE')
        local hunger=getStatVal(handle,w,'hunger','HUNGER')
        local thirst=getStatVal(handle,w,'thirst','THIRST')
        local endurance=getStatVal(handle,w,'endurance','ENDURANCE')

        list[#list+1]={
            id=id,
            name=w.name,
            character=handle,
            desc=handle and handle.getDescriptor and handle:getDescriptor(),
            busy=w.busy or false,
            order=w.order,
            health=health,
            isBleeding=isBleeding,
            isInfected=isInfected,
            hasInjury=hasInjury,
            fatigue=fatigue,
            hunger=hunger,
            thirst=thirst,
            endurance=endurance,
            craftSkill=staticVal.craftSkill or (w and w.craftSkill),
            haulSkill=staticVal.haulSkill or (w and w.haulSkill),
            cookSkill=staticVal.cookSkill or (w and w.cookSkill),
            isFemale=staticVal.isFemale or (w and w.isFemale),
            profTitle=staticVal.profTitle or professionTitle(w and w.profTitle),
            profTexture=staticVal.profTexture or (w and w.profTexture),
            activity=w.activity,
            membership=w.membership,
            priorities=p
        }
    end
    return list
end
if Events and Events.LevelPerk then Events.LevelPerk.Add(function(character)
    load()
    for id,row in pairs(cache) do if row.npc==character then cache[id]=nil end end
end) end
return Service
