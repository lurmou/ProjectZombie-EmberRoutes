local Sites=require 'EmberRoutesProbe/ReposeSites'
local Driver=require 'EmberRoutesProbe/Driver'
local Names=require 'EmberRoutesProbe/DisplayNames'
local Menu={}
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Repose_'..key,...) end
function Menu.configure(actor,object,revision,mode,npcId)
    local reason=Sites.configure(actor,object,revision,mode,npcId)
    actor:Say(getTextOrNull('IGUI_EmberRoutesProbe_Repose_'..reason) or text('SITE_UNAVAILABLE'))
end
function Menu.fill(actor,parent,objects)
    local seen={} local added=0
    for _,object in ipairs(objects) do
        local view=Sites.view(actor,object)
        local group=view and Sites.group(object)
        if group and not seen[group[1]] then
            seen[group[1]]=true added=added+1
            local name
            if view.mode=='ASSIGNED' then
                local binding=Driver.bindId(actor,view.npcId)
                name=binding and Names.name(view.npcId,binding.handle) or text('unavailableNpc')
            end
            local root=parent:addOption(text('title')..' · '..text('status_'..view.mode,name),nil,nil)
            local menu=ISContextMenu:getNew(parent) parent:addSubMenu(root,menu)
            local function option(caption,mode,npcId)
                menu:addOption(caption,actor,Menu.configure,object,view.revision,mode,npcId)
            end
            option((view.mode=='PUBLIC' and '✓ ' or '')..text('public'),'PUBLIC')
            option((view.mode=='DISABLED' and '✓ ' or '')..text('disable'),'DISABLED')
            local assign=menu:addOption(text('assign'),nil,nil)
            local choices=ISContextMenu:getNew(menu) menu:addSubMenu(assign,choices)
            local count=EmberRoutesProbeJava.workerCount()
            for i=0,math.min(count,256)-1 do
                local id=EmberRoutesProbeJava.workerIdAt(i) local binding=Driver.bindId(actor,id)
                if binding then choices:addOption((view.mode=='ASSIGNED' and view.npcId==id and '✓ ' or '')..Names.name(id,binding.handle),
                    actor,Menu.configure,object,view.revision,'ASSIGNED',id) end
            end
            if count==0 then local empty=choices:addOption(text('noNpc'),nil,nil) empty.notAvailable=true end
            if added>=4 then
                local hint=parent:addOption(text('moreHidden'),nil,nil)
                hint.notAvailable=true
                return
            end
        end
    end
end
return Menu
