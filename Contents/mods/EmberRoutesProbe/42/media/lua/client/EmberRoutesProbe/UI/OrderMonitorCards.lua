local Cached=require 'EmberRoutesProbe/UI/CachedList'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Text=require 'EmberRoutesProbe/UI/Text'
local Visual=require 'EmberRoutesProbe/UI/StatusVisual'
local Cards={}
function Cards.text(key,...) return getText('IGUI_EmberRoutesProbe_Monitor_'..key,...) end
local text=Cards.text
function Cards.reason(key)
    if not key or key=='' then return '' end
    return getTextOrNull('IGUI_EmberRoutesProbe_Monitor_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_Public_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_Crafting_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_Logistics_'..key) or key
end
local function state(row)
    return row.closed and 'done' or row.bucket=='attention' and 'blocked' or row.bucket=='active' and 'active' or 'paused'
end
function Cards.title(row) return row.title or text(row.kind=='HAUL' and 'hauling' or 'crafting') end
function Cards.signature(row)
    local fields={}
    for _,key in ipairs({'id','name','title','state','phase','reason','generation','produced','delivered','target','bodyMode','bucket','carrierAvailable'}) do
        fields[#fields+1]=tostring(row[key])
    end
    return table.concat(fields,'|')
end
function Cards.rows()
    return {emptyColor=Theme.muted,prepare=function(list,row)
        local p,h=list.emberPad,list.emberFontHeight
        local width=list.width-p*3
        local lines={Cards.title(row),text('worker',row.name),Cards.reason(row.state)..' · '..Cards.reason(row.phase),
            text('delivered',row.delivered or 0,row.target or 0)}
        for i,line in ipairs(lines) do lines[i]=Text.wrapLimited(line,width,UIFont.Small,1)[1] or '' end
        return {lines=lines,height=h*4+p*2+4,state=state(row)}
    end,draw=function(list,y,entry)
        local v=entry.item.visual local h,p=list.emberFontHeight,list.emberPad
        if y+list:getYScroll()+v.height<0 or y+list:getYScroll()>=list.height then return y+v.height end
        if list.selected==entry.index then Theme.rect(list,0,y,list.width,v.height,Theme.selected)
        elseif list.mouseoverselected==entry.index then Theme.rect(list,0,y,list.width,v.height,Theme.hover) end
        Theme.rect(list,0,y,math.max(3,p/3),v.height,Visual.colors[v.state] or Theme.accent)
        for i,line in ipairs(v.lines) do Theme.text(list,line,p+4,y+p/2+(i-1)*h,i==1 and Theme.textColor or Theme.muted) end

        -- Progress bar at card bottom
        local target=entry.item.value.target or 0
        local delivered=entry.item.value.delivered or 0
        if target>0 then
            local ratio=math.max(0,math.min(1,delivered/target))
            local barW=list.width-p*2-8
            local barH=math.max(3,math.floor(p/2.5))
            local barY=y+v.height-barH-3
            Theme.rect(list,p+4,barY,barW,barH,Theme.control)
            local fillW=math.floor(barW*ratio)
            if fillW>0 and barH>0 then
                local fillColor=ratio>=1.0 and (Theme.status.READY or {r=0.35,g=0.88,b=0.60,a=1}) or Theme.accent
                Theme.rect(list,p+4,barY,fillW,barH,fillColor)
            end
        end
        -- Bottom subtle separator
        Theme.rect(list,0,y+v.height-1,list.width,1,{r=0.20,g=0.28,b=0.35,a=0.5})

        return y+v.height
    end}
end
function Cards.details(owner,bounds)
    local card={}
    local style={emptyColor=Theme.muted,draw=function(list,y,entry)
        for _,line in ipairs(entry.item.visual.lines) do Theme.text(list,line.text,owner.pad,y+line.y,line.color) end
        return y+entry.height
    end}
    card.list=Cached.create(owner,bounds,nil,style) Theme.list(card.list) owner:addChild(card.list)
    function card:set(row)
        local h,p=owner.fontHeight,owner.pad local y=p local lines={}
        local function add(value,color)
            for _,line in ipairs(Text.wrap(value,bounds.width-p*3,UIFont.Small)) do
                lines[#lines+1]={text=line,y=y,color=color or Theme.textColor} y=y+h
            end
            y=y+p/2
        end
        if not row then add(text('selectOrder'),Theme.muted)
        else
            add(Cards.title(row),Theme.gold)
            add(text('identity',row.jobId),Theme.muted)
            add(Cards.reason(row.state)..' · '..Cards.reason(row.phase),Visual.colors[state(row)] or Theme.accent)
            add(text('worker',row.name))
            local bMode=tostring(row.bodyMode or '')
            local activity=(bMode~='' and getTextOrNull('IGUI_EmberRoutesProbe_Monitor_body_'..bMode)) or Cards.reason(bMode)
            add(text('body',activity),Theme.muted)
            if not row.carrierAvailable then add(text('carrierMissing'),Theme.muted) end
            if row.produced~=nil then add(text('produced',row.produced,row.target)) end
            add(text('delivered',row.delivered,row.target),Theme.accent)
            if row.requested~=row.target then add(text('rounded',row.requested,row.target),Theme.muted) end
            if row.reason then add(text('reason',Cards.reason(row.reason)),Theme.accent) end
            if row.uncertain then add(text('reconcile'),Theme.accent) end
            if row.canPause then add(text('pauseBeforeCancel'),Theme.muted) end
            if type(row.source)=='table' and row.source.x then add(text('source',row.source.x,row.source.y,row.source.z),Theme.muted) end
            if type(row.destination)=='table' and row.destination.x then add(text('destination',row.destination.x,row.destination.y,row.destination.z),Theme.muted) end
            local nodes=row.nodes or {}
            if #nodes>0 then
                add(text('chain'),Theme.accent)
                for i,node in ipairs(nodes) do
                    add(text('node',i,node.name or node.product or '?',node.requested or '?')
                        ..(i==row.chainIndex and (' · '..text('currentStep')) or ''),Theme.muted)
                end
            end
            local assets=row.assets or {}
            if #assets>0 then
                add(text('originals',#assets),Theme.accent)
                for i,asset in ipairs(assets) do
                    if i>64 then add(text('moreAssets',#assets-64),Theme.muted) break end
                    local name=asset.fullType and getItemNameFromFullType(asset.fullType) or Cards.reason(asset.kind)
                    add(name..' #'..tostring(asset.id)..(asset.delivered and (' · '..text('credited')) or ''),Theme.muted)
                end
            end

            if row.kind=='HAUL' and not row.closed then add(text('haulRecovery'),Theme.muted) end
        end
        local list=self.list local entry=list.items[1]
        if not entry then list.itemheight=y+p entry=list:addItem('',{visual={}},nil) end
        entry.item.visual={lines=lines} entry.height=y+p entry.tooltip=nil
        list:setScrollHeight(entry.height)
        list:setYScroll(math.max(math.min(0,list:getYScroll()),math.min(0,list.height-entry.height)))
    end
    return card
end
return Cards
