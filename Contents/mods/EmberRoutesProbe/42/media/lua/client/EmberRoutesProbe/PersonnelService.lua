-- Selected-member projection. UI owns/relinquishes the cache; no world scanning
-- or character handles escape through the returned display rows.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Driver=require 'EmberRoutesProbe/Driver'
local Jobs=require 'EmberRoutesProbe/TaskJobs'
local Service={}
local world,cache=nil,{}
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end
local function load()
    local root=Registry.data() if root~=world then world,cache=root,{} end
end
function Service.invalidate(id) load() cache[id]=nil end
function Service.release(id) if id then cache[id]=nil end end
require('EmberRoutesProbe/Boot').invalidatePersonnel=Service.invalidate
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

local function static(npc)
    local value={skills={},knowledge={},traits={}}
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
    return value
end
function Service.details(actor,scope,id,force)
    load()
    if not require('EmberRoutesProbe/SettlementLedger').view(actor,scope) then return end
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
        membership=require('EmberRoutesProbe/MembershipService').view(id)}
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
    local Probe=require 'EmberRoutesProbe/Boot'
    result.leisure=personal and personal.payload.step~='IDLE' and personal.payload.leisure and personal.payload.leisure.activity
    result.leisureStatus=require('EmberRoutesProbe/LeisureService').status(id)
    result.studyReason=Probe.studyStatus and Probe.studyStatus(id)
    return result
end
function Service.rows(value,mode,page)
    local rows={}
    if not value then return (mode=='skills' or mode=='knowledge') and {{text=text('detailsUnknown')}} or {} end
    local Theme=require 'EmberRoutesProbe/UI/Theme'

    if mode=='skills' then
        for _,skill in ipairs(value.skills or {}) do
            rows[#rows+1]={text=text('skillLevel',skill.name,skill.level),fraction=skill.level/10}
            if skill.multiplier and skill.multiplier>1 then rows[#rows+1]={text=text('xpMultiplier',skill.multiplier)} end
        end
        return rows
    elseif mode=='knowledge' then
        local count=value.knownCount
        rows[#rows+1]={text=count and text('knownCount',count) or text('detailsUnknown')}
        local start=((page or 1)-1)*32+1
        for i=start,math.min(start+31,#(value.knowledge or {})) do rows[#rows+1]={text=value.knowledge[i]} end
        rows[#rows+1]={text=text('knowledgePage',page or 1,math.max(1,math.ceil(#(value.knowledge or {})/32)))}
        return rows
    end

    -- Mental warning only if severe
    if value.mood and (value.mood.UNHAPPINESS or 0)>=80 and (value.mood.STRESS or 0)>=0.8 then
        rows[#rows+1]={text=text('mentalWarning'),color=Theme.status.ERROR}
    end

    -- Study / Self-care progress if actively occurring
    local study=value.study
    if study and study.step~='IDLE' then
        rows[#rows+1]={text=text('studyState',text('study_'..study.step)),color=Theme.accent}
        if study.book then rows[#rows+1]={text=text('studyBook',getItemNameFromFullType and getItemNameFromFullType(study.book) or study.book),fullType=study.book} end
        if study.pages and study.total and study.total>0 then
            rows[#rows+1]={text=text('studyPages',study.pages,study.total),fraction=study.pages/study.total,compact=true,meterLabel=study.pages..'/'..study.total}
        end
    end

    if #rows==0 and (mode=='skills' or mode=='knowledge') then rows[1]={text=text('detailsUnknown')} end
    return rows
end
if Events and Events.LevelPerk then Events.LevelPerk.Add(function(character)
    load()
    for id,row in pairs(cache) do if row.npc==character then cache[id]=nil end end
end) end
return Service
