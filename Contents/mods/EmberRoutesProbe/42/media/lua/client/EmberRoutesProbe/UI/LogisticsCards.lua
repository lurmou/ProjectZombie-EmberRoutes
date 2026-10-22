local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Presentation=require "EmberRoutesProbe/UI/LogisticsPresentation"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local text=require("EmberRoutesProbe/LogisticsText").get
local Cards={}
local Visual=require "EmberRoutesProbe/UI/StatusVisual"
function Cards.workers()
    return {
        emptyColor=Theme.muted,
        prepare=function(list,row)
            local h,p=list.emberFontHeight,list.emberPad
            local width=list.width-p*3
            local reason=Presentation.activity(row)
            local status=Text.wrapLimited(reason,width,UIFont.Small,1)
            local name=Text.wrapLimited(row.name,width,UIFont.Small,1)
            local progress=row.total>0 and (Presentation.batch(row).." · "..row.delivered.."/"..row.total) or nil
            local progressLine=progress and Text.wrapLimited(progress,width,UIFont.Small,1)[1]
            local state=row.state=="DONE" and "done" or row.reason=="WORKING" and "active" or "paused"
            return {lines={},height=h*(row.total>0 and 3 or 2)+p*2,name=name[1],status=status[1],state=state,
                fraction=row.total>0 and row.delivered/row.total or false,
                progress=progressLine or false,
                tooltip=(status[1]~=reason or (progress and progress~=progressLine)) and (reason..(progress and ("\n"..progress) or "")) or false}
        end,
        draw=function(list,y,entry)
            local v=entry.item.visual local h,p=list.emberFontHeight,list.emberPad
            local visible=y+list:getYScroll()
            if visible+v.height<0 or visible>=list.height then return y+v.height end
            if list.selected==entry.index then
                Theme.rect(list,0,y,list.width,v.height,Theme.selected)
                Theme.rect(list,0,y,math.max(2,p/4),v.height,Theme.accent)
            elseif list.mouseoverselected==entry.index then Theme.rect(list,0,y,list.width,v.height,Theme.hover) end
            Visual.mark(list,p,y+p/2+h/4,h/2,v.state,Visual.colors[v.state])
            Theme.text(list,v.name,p+h,y+p/2,Theme.textColor)
            Theme.text(list,v.status,p,y+p/2+h,Visual.colors[v.state])
            if v.progress then Theme.text(list,v.progress,p,y+p/2+h*2,Theme.accent) end
            if v.fraction then Visual.meter(list,p,y+v.height-p,list.width-p*2,math.max(3,p/3),v.fraction,Visual.colors[v.state]) end
            return y+v.height
        end}
end
function Cards.details(owner,bounds)
    local card={bounds=bounds,lines={},bar=false}
    local style={emptyColor=Theme.muted}
    function style.draw(list,y,entry)
        local v=entry.item.visual local p=owner.pad
        for _,line in ipairs(v.lines) do Theme.text(list,line.text,p,y+line.y,line.color) end
        if v.bar then
            Visual.meter(list,p,y+v.bar.y,list.width-p*2,v.bar.height,v.bar.fraction,Theme.accent)
        end
        if v.track then Visual.drawSteps(list,p,y+v.trackY,v.track) end
        for _,endpoint in ipairs(v.endpoints or {}) do
            Theme.rect(list,p/2,y+endpoint.y,math.max(2,p/4),endpoint.height,endpoint.color)
        end
        return y+entry.height
    end
    card.list=Cached.create(owner,bounds,nil,style) Theme.list(card.list) owner:addChild(card.list)
    function card:set(row)
        local h,p=owner.fontHeight,owner.pad
        local width=bounds.width-p*2
        local lines,y={},p
        local function add(value,color,limit)
            for _,line in ipairs(Text.wrapLimited(value,width,UIFont.Small,limit or 2)) do
                lines[#lines+1]={text=line,y=y,color=color} y=y+h
            end
        end
        self.bar=false local track,trackY local endpoints={}
        if not row then add(text("selectWorker"),Theme.textColor,3)
        else
            add(row.name,Theme.textColor,1) y=y+p/2
            add(Presentation.activity(row),Theme.accent,2) y=y+p
            if row.total>0 then
                local phase=row.state=="DONE" and 3 or row.phase=="DELIVER" and 2 or row.phase=="COLLECT" and 1 or 0
                local state=row.state=="DONE" and "done" or row.reason=="WORKING" and "active" or "paused"
                track=Visual.steps({text("stepCollect"),text("stepDeliver"),text("stepDone")},width,h,p,phase,state)
                trackY=y y=y+track.height+p/2
                add(Presentation.batch(row),Theme.textColor,2)
                if row.state=="DONE" then add(Presentation.kind(row),Theme.muted,1) end
                add(text("delivered").."  "..row.delivered.." / "..row.total,Theme.textColor,1)
                self.bar={y=y+p/2,width=width*math.max(0,math.min(1,row.delivered/row.total)),
                    fraction=math.max(0,math.min(1,row.delivered/row.total)),height=math.max(4,p/2)}
                y=y+p*2
            else add(text("noTask"),Theme.muted,1) y=y+p end
            local completed=row.lastCompleted
            if completed and (completed.id~=row.taskId or row.state~="DONE") then
                add(Presentation.completed(completed),Theme.muted,2)
                add(text("recentSession"),Theme.muted,2) y=y+p
            end
            if row.taskId~="" then
                local start=y
                add(text("source"),Theme.muted,1) add(Presentation.endpoint(row.source),Theme.textColor,2) y=y+p/2
                endpoints[#endpoints+1]={y=start,height=y-start-p/2,color=Visual.colors.active} start=y
                add(text("destination"),Theme.muted,1) add(Presentation.endpoint(row.destination),Theme.textColor,2)
                endpoints[#endpoints+1]={y=start,height=y-start,color=Visual.colors.done}
            end
        end
        self.lines=lines
        local list=self.list local height=y+p
        local entry=list.items[1]
        if not entry then
            list.itemheight=height entry=list:addItem("",{visual={}},nil)
        end
        entry.item.visual={lines=self.lines,bar=self.bar,track=track,trackY=trackY,endpoints=endpoints} entry.height=height entry.tooltip=nil
        list:setScrollHeight(height)
        list:setYScroll(math.max(math.min(0,list:getYScroll()),math.min(0,list.height-height)))
    end
    return card
end
return Cards
