local Cached=require "EmberRoutesProbe/UI/CachedList"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Visual=require "EmberRoutesProbe/UI/StatusVisual"
local Words=require "EmberRoutesProbe/CraftingText"
local text=Words.get
local Cards={}
local stages={PLANNING=1,COLLECTING=2,CRAFTING=3,COMMITTING=3,CONFIRMED=4,RETURNING=4,DONE=4}
function Cards.state(worker)
    local order=worker and worker.order
    if not order then return worker and worker.busy and "active" or "neutral" end
    if order.uncertain then return "blocked" end
    if order.state=="DONE" then return "done" end
    if order.state=="RUNNING" then return "active" end
    if order.released then return "neutral" end
    return "paused"
end
function Cards.workers()
    return {emptyColor=Theme.muted,
        prepare=function(list,row)
            local h,p=list.emberFontHeight,list.emberPad
            local state=Cards.state(row)
            local order=row.order
            local label=order and Words.reason(order.state=="RUNNING" and order.phase or order.state) or text(row.busy and "otherTask" or "idle")
            return {lines={},height=h*(order and 4 or 3)+p,state=state,name=Text.wrapLimited(order and order.recipeName or row.name,list.width-p*2,UIFont.Small,1)[1],
                workerName=order and row.name,
                badge=Visual.badge(label,state,list.width-p*2,h,p/2)}
        end,
        draw=function(list,y,entry)
            local v=entry.item.visual local p,h=list.emberPad,list.emberFontHeight
            local visible=y+list:getYScroll()
            if visible+v.height<0 or visible>=list.height then return y+v.height end
            if list.selected==entry.index then
                Theme.rect(list,0,y,list.width,v.height,Theme.selected)
                Theme.rect(list,0,y,math.max(2,p/4),v.height,Theme.accent)
            elseif list.mouseoverselected==entry.index then Theme.rect(list,0,y,list.width,v.height,Theme.hover) end
            Theme.text(list,v.name,p,y+p/2,Theme.textColor)
            if v.workerName then Theme.text(list,v.workerName,p,y+h+p/2,Theme.muted) end
            Visual.drawBadge(list,p,y+h*(v.workerName and 2 or 1)+p,v.badge)
            return y+v.height
        end}
end
function Cards.details(owner,bounds)
    local card={}
    local style={emptyColor=Theme.muted}
    function style.draw(list,y,entry)
        local v=entry.item.visual local h,p=owner.fontHeight,owner.pad
        Theme.rect(list,p,y+p,list.width-p*2,h*2+p,Theme.control)
        for i,line in ipairs(v.title) do Theme.text(list,line,p*2,y+p+(i-1)*h,Theme.textColor) end
        Visual.drawBadge(list,p,y+h*2+p*2,v.badge)
        if v.track then Visual.drawSteps(list,p,y+v.trackY,v.track) end
        for _,line in ipairs(v.lines) do Theme.text(list,line.text,p,y+line.y,line.color) end
        for _,bar in ipairs(v.bars or {}) do Visual.meter(list,p,y+bar.y,list.width-p*2,math.max(4,p/2),bar.fraction,bar.color) end
        return y+entry.height
    end
    card.list=Cached.create(owner,bounds,nil,style) Theme.list(card.list) owner:addChild(card.list)
    function card:set(worker,surfaces,surfaceId,draft,quantity)
        local h,p=owner.fontHeight,owner.pad local width=bounds.width-p*2
        local order=worker and worker.order local surface=order and order.surface
        if not order then for _,s in ipairs(surfaces) do if s.id==surfaceId then surface=s break end end end
        local state=Cards.state(worker)
        local label=order and Words.reason(order.state) or text(worker and worker.busy and "otherTask" or "noOrder")
        local caption=order and order.recipeName or draft and draft.name or text("recipe")
        local target=order and order.target or draft and math.ceil((quantity or 1)/(draft.yield or 1))*(draft.yield or 1)
        local v={title=Text.wrapLimited(caption,width-p*2,UIFont.Small,2),
            badge=Visual.badge(label,state,width,h,p/2),lines={},bars={}}
        local index=order and (stages[order.phase] or 0) or 0
        if order and order.released and order.state~="DONE" then index=0 end
        if order then v.track=Visual.steps({text("stepPlan"),text("stepCollect"),text("stepCraft"),text("stepStore")},width,h,p,index,state) end
        v.trackY=h*3+p*3
        local y=v.trackY+(v.track and v.track.height or 0)+p
        local function add(value,color)
            for _,line in ipairs(Text.wrapLimited(value,width,UIFont.Small,3)) do
                v.lines[#v.lines+1]={text=line,y=y,color=color} y=y+h
            end
            y=y+p/2
        end
        local requested=order and order.requested or quantity or 1
        if target then
            add(text("quantity").." "..requested.."   "..text("plannedOutput").." "..target,Theme.accent)
        end
        if draft then
            local outputs={}
            for _,output in ipairs(draft.outputs or {}) do outputs[#outputs+1]=output.name.." x"..output.count end
            if #outputs>0 then add(text("batchOutput").."  "..table.concat(outputs," + "),Theme.textColor) end
            for _,keep in ipairs({false,true}) do
                local heading=false
                for _,input in ipairs(draft.inputs or {}) do
                    if input.keep==keep then
                        if not heading then add(text(keep and "keptTools" or "batchMaterials"),Theme.accent) heading=true end
                        local names=table.concat(input.names," / ")
                        if input.more>0 then names=names.."  (+"..input.more..")" end
                        add("  "..names.." x"..input.count,Theme.textColor)
                    end
                end
            end
        end
        if order and order.target then
            if order.chainTotal and order.chainTotal>0 then
                add(text("chainStep").." "..order.chainIndex.." / "..order.chainTotal.."  → "..order.stepName,Theme.accent)
            end
            for _,metric in ipairs({{key="produced",label="madeCount",color=Theme.accent},{key="delivered",label="storedCount",color=Visual.colors.done}}) do
                add(text(metric.label).."  "..order[metric.key].." / "..order.target,metric.color)
                v.bars[#v.bars+1]={y=y,fraction=order[metric.key]/order.target,color=metric.color} y=y+p*1.5
            end
            if order.requested~=order.target then add(text("roundedTarget").." "..order.requested.." -> "..order.target,Theme.muted) end
        elseif draft and target~=(quantity or 1) then add(text("roundedTarget").." "..quantity.." -> "..target,Theme.muted) end
        add(worker and worker.name or text("noWorker"),Theme.textColor)
        local needsSurface=order and order.surfaceRequired
        if needsSurface==nil then
            if draft then needsSurface=draft.surface else needsSurface=surface~=nil end
        end
        if needsSurface then
            add(text("surface").."  "..(surface and ("("..surface.x..", "..surface.y..", "..surface.z..")") or text("unknownSurface")),Theme.muted)
        else add(text("noSurface"),Theme.muted) end
        if order and not order.released then
            if order.reason then add(Words.reason(order.reason),Visual.colors[state]) end
            if order.uncertain then add(text("uncertain"),Visual.colors.blocked)
            elseif order.resumable and not worker.busy then add(text("continueHint"),Theme.accent) end
        end
        self.visual=v
        local list=self.list local entry=list.items[1]
        if not entry then list.itemheight=y+p entry=list:addItem("",{visual=v},nil) end
        entry.item.visual=v entry.height=y+p entry.tooltip=nil list.selected=0
        list:setScrollHeight(entry.height)
        list:setYScroll(math.max(math.min(0,list:getYScroll()),math.min(0,list.height-entry.height)))
    end
    return card
end
return Cards
