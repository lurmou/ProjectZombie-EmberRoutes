-- Shared target-level read-only queue with capability-checked existing commands.
local Info=require 'EmberRoutesProbe/UI/InfoList'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local A=require 'EmberRoutesProbe/Work/WorkCommandAdapter'
local Q={}
function Q.new(owner,bounds,choose)
    local q={owner=owner,choose=choose}
    q.info=Info.new(owner,bounds)
    q.info.list:setOnMouseDownFunction(owner,function(_,value)
        local w=value and value.value and value.value.work
        if not w or not owner.active or not owner.activationScope or not owner.activationScope:isCurrent() then return end
        q.selectedId=q.selectedId~=w.key and w.key or nil
        q:set(q.snapshot)
        require 'ISUI/ISContextMenu'
        local menu=ISContextMenu.get(owner.actor:getIndex(),owner:getAbsoluteX()+bounds.x,owner:getAbsoluteY()+bounds.y)
        owner.activationScope:own(menu,function(m) m:hideSelfAndChildren2() end)
        for _,action in ipairs({'stop','resume','return','stopBody'}) do
            if A.capabilities(w.row)[action] then
                menu:addOption(getText('IGUI_EmberRoutesProbe_Distributed_'..action),owner,owner.activationScope:wrapCallback(function()
                    A.command(owner.actor,owner.entry.id,w.row,action)
                end))
            end
        end
        if w.row.npcId then menu:addOption(getText('IGUI_EmberRoutesProbe_Distributed_worker'),owner,owner.activationScope:wrapCallback(function()
            owner.owner:selectTab('personnel',{npcId=w.row.npcId})
        end)) end
    end)
    function q:set(snapshot)
        self.snapshot=snapshot
        local lines={}
        for _,w in ipairs(snapshot.works) do
            if self.choose(w) then
                local r=w.row
                local details={r.name or getText('IGUI_EmberRoutesProbe_Public_unclaimed'),r.reasonText or r.reason or ''}
                if r.targetLocation then
                    local t=r.targetLocation
                    local floorStr=(t.z==0) and getText('IGUI_EmberRoutesProbe_Settlement_floorGround') or ((t.z+1)..getText('IGUI_EmberRoutesProbe_Settlement_floorLevel'))
                    details[#details+1]=floorStr..' | ('..t.x..', '..t.y..')'
                end
                if r.produced~=nil and r.target then details[#details+1]=r.produced..' / '..r.target end
                if r.delivered~=nil and r.target and r.target>0 then details[#details+1]=getText('IGUI_EmberRoutesProbe_Monitor_delivered',r.delivered,r.target) end
                lines[#lines+1]={isCardRow=true,title=w.title,status='READY',statusText=getText('IGUI_EmberRoutesProbe_Distributed_'..w.state),
                    lines=details,work=w}
                if self.selectedId==w.key then
                    for _,line in ipairs(require('EmberRoutesProbe/UI/OrderMonitorCards').detailRows(r,true)) do lines[#lines+1]=line end
                end
            end
        end
        if #lines==0 then lines[1]={text=getText('IGUI_EmberRoutesProbe_Distributed_empty'),color=Theme.muted} end
        self.info:set(lines)
    end
    return q
end
return Q
