-- Shared observation only. Registered STORAGE containers are the authorized
-- bookshelves/library boxes; native references never enter saved Jobs.
local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local Membership=require 'EmberRoutesProbe/SettlementMembership'
local Supply=require 'EmberRoutesProbe/CraftSupply'
local Store=require 'EmberRoutesProbe/LaborStore'
local Wake=require 'EmberRoutesProbe/PlanningWake'
local Library={}
local world,scopes=nil,{}
function Library.eligible(item)
    if not item or not instanceof(item,'Literature') or not item.getNumberOfPages
        or item:getIsCraftingConsumed() then return false end
    local recipes=item.getLearnedRecipes and item:getLearnedRecipes()
    if item:getNumberOfPages()<=0 and (not recipes or recipes:isEmpty())
        and not (item.getBoredomChange and item:getBoredomChange()<0 or item.getUnhappyChange and item:getUnhappyChange()<0) then return false end
    if ItemTag and ItemTag.CONSUME_ON_READ and item.hasTag and item:hasTag(ItemTag.CONSUME_ON_READ) then return false end
    local d=item:getModData()
    return not (d.EmberRoutesHaulFixture or d.EmberRoutesPersistenceSample or d.EmberRoutesProbeFixture
        )
end
function Library.useful(npc,item,target,leisure)
    if not Library.eligible(item) then return false end
    if not CharacterTrait or not npc.hasTrait or npc:hasTrait(CharacterTrait.ILLITERATE) then return false end
    if leisure then
        local d=item:getModData()
        return not (d.literatureTitle and npc:isLiteratureRead(d.literatureTitle))
            and not (d.printMedia and d.printMedia.id and npc:isPrintMediaRead(tostring(d.printMedia.id)))
            and (item.getBoredomChange and item:getBoredomChange()<0 or item.getUnhappyChange and item:getUnhappyChange()<0) or false
    end
    local learned=item:getLearnedRecipes()
    if target then
        local keys=type(target)=='table' and target or {target}
        for _,key in ipairs(keys) do
            if learned and learned:contains(key) and not npc:getKnownRecipes():contains(key) then return true,key end
        end
        return false
    end
    local skill=SkillBook and SkillBook[item:getSkillTrained()]
    if skill then
        local level=npc:getPerkLevel(skill.perk)+1
        return item:getLvlSkillTrained()<=level and item:getMaxLevelTrained()>=level
            and npc:getAlreadyReadPages(item:getFullType())<item:getNumberOfPages()
    end
    return false
end
function Library.revalidate(candidate,ownerId)
    local item=candidate and candidate.item
    local owner=item and Store.owner(candidate.id)
    return item and item:getID()==candidate.id and item:getContainer()==candidate.container
        and candidate.container:getItems():contains(item) and (not owner or owner.taskId==ownerId)
        and Registry.revalidate(candidate.endpoint,'take','local-world')~=nil
        and Registry.logistics(candidate.endpoint)=='STORAGE' and Registry.accepts(candidate.endpoint,item)
        and Library.eligible(item) or false
end
local function view(entry)
    local root=Registry.data()
    if root~=world then world,scopes=root,{} end
    local row=scopes[entry.id]
    local now=getTimestampMs()
    if not row or row.revision~=entry.revision or now>=row.expires or Wake.changed(row.watch) then
        row={revision=entry.revision,watch=Wake.capture(entry),expires=math.huge,
            ids=Membership.query(entry),position=1,books={}}
        scopes[entry.id]=row
    end
    return row
end
function Library.choose(actor,npc,entry,target,budget,offset,leisure)
    local row=view(entry)
    if not row.ids then return nil,true,'CONTAINER_RECORD_INVALID' end
    while not row.complete and budget.scan>0 do
        local frame=row.frame
        if frame then
            local items=frame.endpoint.container:getItems()
            if items:size()~=frame.size then row.expires=0 return nil,false,'INVENTORY_CHANGED' end
            if frame.offset>=frame.size then row.frame=nil
            else
                budget.scan=budget.scan-1
                local item=items:get(frame.offset) frame.offset=frame.offset+1
                if Library.eligible(item) and Registry.accepts(frame.endpoint,item) then
                    if #row.books>=256 then row.complete=true row.reason='LIBRARY_LIMIT' break end
                    row.books[#row.books+1]={item=item,id=item:getID(),container=frame.endpoint.container,
                        endpoint=frame.endpoint,entry=entry}
                end
            end
        else
            local id=row.ids[row.position]
            if not id then row.complete=true break end
            if (budget.containers or 0)<1 then return nil,false,'LIBRARY_OBSERVING' end
            budget.containers=budget.containers-1 budget.scan=budget.scan-1 row.position=row.position+1
            local endpoint,reason=Supply.endpoint(entry,id,'take')
            if endpoint and Registry.logistics(endpoint)=='STORAGE' then
                row.frame={endpoint=endpoint,size=endpoint.container:getItems():size(),offset=0}
            elseif reason=='CONTAINER_UNLOADED' then row.reason='RESOURCE_UNLOADED' end
        end
    end
    if not row.complete then return nil,false,'LIBRARY_OBSERVING' end
    if row.expires==math.huge then row.expires=getTimestampMs()+10000 end
    -- Each caller has a selection cursor, but shares all container observation.
    local start=offset or 1 local finish=math.min(#row.books,start+7)
    for i=start,finish do
        if budget.scan<1 then return nil,false,'LIBRARY_OBSERVING',i end
        budget.scan=budget.scan-1
        local candidate=row.books[i]
        local useful,knowledge=Library.useful(npc,candidate.item,target,leisure)
        if useful and Library.revalidate(candidate) then
            return {item=candidate.item,id=candidate.id,container=candidate.container,endpoint=candidate.endpoint,
                entry=entry,npc=npc,knowledge=knowledge},true
        end
    end
    if finish<#row.books then return nil,false,'LIBRARY_OBSERVING',finish+1 end
    return nil,true,row.reason or 'STUDY_BOOK_UNAVAILABLE'
end
return Library
