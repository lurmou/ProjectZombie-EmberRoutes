local Registry=require 'EmberRoutesProbe/ContainerRegistry'
local M={} local world,names,fallbacks,sequence
function M.name(id,npc,saved)
    local root=Registry.data()
    if root~=world then world=root names={} fallbacks={} sequence=0 end
    local name
    if npc and npc.getDescriptor then
        local d=npc:getDescriptor()
        if d then name=(d:getForename() or '')..' '..(d:getSurname() or '') end
    end
    if not name or name:match('^%s*$') then name=npc and npc.getFullName and npc:getFullName() end
    if name then name=name:gsub('^%s+',''):gsub('%s+$','') end
    if name and not name:find(id,1,true) and name~=id and not name:find('EmberRoutes',1,true) and not name:match('^[%x%-]+$') then
        names[id]=name
    end
    if not fallbacks[id] then sequence=sequence+1 fallbacks[id]=sequence end
    return names[id] or saved or getText('IGUI_EmberRoutesProbe_Personnel_unnamedMember',tostring(fallbacks[id]))
end
return M
