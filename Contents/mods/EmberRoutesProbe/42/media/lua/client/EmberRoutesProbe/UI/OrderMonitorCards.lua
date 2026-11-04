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
        or getTextOrNull('IGUI_EmberRoutesProbe_Logistics_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_WorkCode_'..key)
        or getTextOrNull('IGUI_EmberRoutesProbe_Stock_'..key) or key
end

local function state(row)
    return row.closed and (row.state=='CANCELLED' and 'paused' or 'done') or row.bucket=='attention' and 'blocked' or row.bucket=='active' and 'active' or 'paused'
end

function Cards.title(row)
    if row.kind=='COOKING' then
        local base=row.title or getText('IGUI_EmberRoutesProbe_Public_cooking')
        if base==getText('IGUI_EmberRoutesProbe_Public_cooking') and row.product then
            local prodName=getItemNameFromFullType and getItemNameFromFullType(row.product)
            if prodName and prodName~='' then return base..' · '..prodName end
        end
        return base
    end
    return row.title or text(row.kind=='HAUL' and 'hauling' or 'crafting')
end

function Cards.signature(row)
    local fields={}
    for _,key in ipairs({'id','name','title','state','stateText','phase','reason','reasonText','summaryText','demandSummary','generation','produced','delivered','target','bodyMode','bucket','carrierAvailable','cargoHeld','cargoSummary','deliverySummary','allocationSummary','allocationDetails','allocated','settled','remaining','observationRevision','feasibilityRevision','compact','demandReason','coverageText'}) do
        fields[#fields+1]=tostring(row[key])
    end
    for _,asset in ipairs(row.assets or {}) do
        for _,key in ipairs({'id','kind','fullType','custody','custodyState','held','delivered','destinationId','displayName','statusText','reasonText','sequence'}) do
            fields[#fields+1]=tostring(asset[key])
        end
    end
    fields[#fields+1]=tostring(row.workflow and row.workflow.viewRevision)
    for _,label in ipairs(row.blockerLabels or {}) do fields[#fields+1]=label end
    for _,step in ipairs(row.stages or {}) do
        for _,key in ipairs({'key','labelKey','status','progress'}) do fields[#fields+1]=tostring(step[key]) end
    end
    for _,child in ipairs(row.children or {}) do fields[#fields+1]=Cards.signature(child) end
    local member=row.membership
    if member then
        for _,key in ipairs({'revision','context','settlementId','settlementName','reason','bedId','bedReason','postingReason','postingRevision'}) do fields[#fields+1]=tostring(member[key]) end
        if member.posting then fields[#fields+1]=member.posting.zoneId fields[#fields+1]=member.posting.category end
    end
    return table.concat(fields,'|')
end

local function makeStr(codepoints, utf8bytes)
    local ok, str = pcall(string.char, unpack(codepoints))
    if ok and str and #str == #codepoints then return str end
    return utf8bytes
end

function Cards.isChinese()
    if _G.getTextOrNull then
        local t = getTextOrNull('IGUI_EmberRoutesProbe_Monitor_crafting')
        if t and t ~= 'Crafting job' and t ~= 'IGUI_EmberRoutesProbe_Monitor_crafting' then
            return true
        end
    end
    if _G.getText then
        local q = getText('IGUI_EmberRoutesProbe_Public_targetQuantity')
        if q and q ~= 'Target Product Quantity' and q ~= 'IGUI_EmberRoutesProbe_Public_targetQuantity' then
            return true
        end
    end
    return false
end

local ICON_DONE = makeStr({10004}, '✔')
local ICON_ACTIVE = makeStr({9679}, '●')
local ICON_WAIT = makeStr({9675}, '○')
local ARROW_WIDE = makeStr({32, 8594, 32}, ' → ')
local ARROW_NARROW = makeStr({8594}, '→')
local BOX_BRANCH = makeStr({9500, 9472, 9472, 32}, '├── ')
local BOX_CORNER = makeStr({9492, 9472, 9472, 32}, '└── ')

local STAGE_KEYS={'IGUI_EmberRoutesProbe_Order_stage_source','IGUI_EmberRoutesProbe_Order_stage_staging',
    'IGUI_EmberRoutesProbe_Order_stage_craft','IGUI_EmberRoutesProbe_Order_stage_store'}
local function stageLabel(index,row)
    local key=row and row.stages and row.stages[index] and row.stages[index].labelKey or STAGE_KEYS[index]
    return key and (getTextOrNull(key) or key) or ''
end

local COLOR_DONE={r=0.35,g=0.88,b=0.60,a=1.0}
local COLOR_ACTIVE={r=1.0,g=0.78,b=0.25,a=1.0}
local COLOR_WAIT={r=0.50,g=0.64,b=0.75,a=0.65}
local COLOR_ARROW={r=0.50,g=0.64,b=0.75,a=0.45}

local SemanticBadge = require 'EmberRoutesProbe/UI/SemanticBadge'

local BOM_COLORS={
    WAITING={r=0.50,g=0.64,b=0.75,a=1.0},
    WITHDRAWN={r=0.50,g=0.50,b=0.50,a=1.0},
    STORED={r=0.35,g=0.88,b=0.60,a=1.0},
    PROCESSING={r=1.0,g=0.78,b=0.25,a=1.0},
    MISSING={r=1.0,g=0.42,b=0.38,a=1.0},
    TRANSIT={r=0.25,g=0.75,b=1.0,a=1.0},
}
local function stepState(row,index,current)
    local explicit=row.stages and row.stages[index] and row.stages[index].status
    if explicit then
        return explicit=='COMPLETED' and 'done' or (explicit=='ACTIVE' or explicit=='BLOCKED'
            or explicit=='UNCERTAIN' or explicit=='OBSERVING' or explicit=='STOPPING') and 'active' or 'wait'
    end
    return index<current and 'done' or index==current and 'active' or 'wait'
end

function Cards.stageNames(row)
    local result={}
    for i=1,row and row.stages and #row.stages or #STAGE_KEYS do result[i]=stageLabel(i,row) end
    return result
end

function Cards.phaseIndex(row)
    if not row then return 1 end
    if row.closed and row.state=='CANCELLED' then return 0 end
    if row.stages then return row.closed and #row.stages+1 or row.stageIndex or 1 end
    if row.closed or row.state=='DONE' then return 5 end
    local phase=row.phase or row.state or ''
    local bMode=row.bodyMode or ''
    if phase=='RETURN' or phase=='RETURNING' or phase=='CONFIRMED' or phase=='DELIVER' or phase=='DELIVERING' or phase=='STORING'
        or bMode=='RETURNING' then
        return 4
    elseif phase=='CRAFTING' or phase=='COMMITTING' or phase=='PROCESSING' or phase=='HAULING'
        or phase=='ADDING' or phase=='HEATING' or phase=='UNLOADING'
        or bMode=='CRAFTING' or bMode=='HAULING' then
        return 3
    elseif phase=='COLLECTING' or phase=='COLLECT' or phase=='STAGING' or phase=='PREPARING' or phase=='FETCHING'
        or bMode=='COLLECT' or bMode=='COLLECTING' then
        return 2
    elseif phase=='PLANNING' or phase=='TARGETS' or phase=='WAITING_CLAIM' or phase=='SEARCHING'
        or phase=='UNCLAIMED' or bMode=='UNCLAIMED' or bMode=='PLANNING' then
        return 1
    end
    local target=row.target or 0
    local produced=row.produced or 0
    local delivered=row.delivered or 0
    if target>0 and delivered>=target then return 5
    elseif target>0 and produced>=target then return 4
    elseif produced>0 then return 3
    elseif delivered>0 then return 4
    end
    return 1
end

function Cards.stageProgress(row,stage)
    if not row then return '' end
    if row.stages then return row.stages[stage] and row.stages[stage].progress or '' end
    local target=row.target or 0
    if stage==3 then
        if row.progressPercent~=nil then
            return tostring(row.progressPercent)..'%'
        end
        if row.progress~=nil then
            return tostring(row.progress)
        end
        if row.produced~=nil or target>0 then
            return tostring(row.produced or 0)..'/'..tostring(target)
        end
    elseif stage==4 then
        if row.delivered~=nil or target>0 then
            return tostring(row.delivered or 0)..'/'..tostring(target)
        end
    elseif stage==2 then
        if (row.kind=='HAUL' or row.kind=='DELIVERY') and target>0 then
            return tostring(row.delivered or 0)..'/'..tostring(target)
        else
            local matCount,matTotal=0,0
            for _,asset in ipairs(row.assets or {}) do
                if asset.kind=='materials' or asset.kind=='cargo' then
                    matTotal=matTotal+1
                    if asset.delivered or asset.held then matCount=matCount+1 end
                end
            end
            if matTotal>0 then return tostring(matCount)..'/'..tostring(matTotal) end
        end
    end
    return ''
end

local function buildTrackCandidate(row,tier,isChinese)
    local cur=Cards.phaseIndex(row)
    local names=Cards.stageNames(row)
    local arrow=(tier<=2) and ARROW_WIDE or ARROW_NARROW
    local segments={}
    local fullText=''

    for i=1,#names do
        local nodeState=stepState(row,i,cur)
        local icon=(nodeState=='done') and ICON_DONE or (nodeState=='active') and ICON_ACTIVE or ICON_WAIT
        local col=(nodeState=='done') and COLOR_DONE
            or (nodeState=='active') and (row.bucket=='attention' and (Visual.colors.blocked or Theme.status.ERROR) or COLOR_ACTIVE)
            or COLOR_WAIT

        local prog=(nodeState=='active') and Cards.stageProgress(row,i) or ''
        local progSuffix=''
        if prog~='' then
            if prog:sub(1,1)==':' or prog:sub(1,1)=='(' then
                progSuffix=prog
            elseif row.useColonProgress then
                progSuffix=': '..prog
            else
                progSuffix='('..prog..')'
            end
        end

        local sep=(progSuffix~='' and progSuffix:sub(1,1)~=':' and ' ') or ''
        local textPart
        if tier==1 then
            textPart=icon..' '..i..'.'..names[i]..(progSuffix~='' and (sep..progSuffix) or '')
        elseif tier==2 then
            textPart=icon..' '..names[i]..(progSuffix~='' and (sep..progSuffix) or '')
        elseif tier==3 then
            textPart=icon..' '..names[i]
        elseif tier==4 then
            textPart=icon..' '..i..progSuffix
        elseif tier==5 then
            textPart=(nodeState=='active') and (icon..' '..names[i]) or icon
        else
            textPart=icon
        end

        segments[#segments+1]={text=textPart,color=col}
        fullText=fullText..textPart

        if i<#names then
            segments[#segments+1]={text=arrow,color=COLOR_ARROW}
            fullText=fullText..arrow
        end
    end

    return segments,fullText
end

function Cards.buildPhaseTrack(row,availableWidth)
    local isChinese=Cards.isChinese()
    local manager=getTextManager()
    for tier=1,6 do
        local segments,fullText=buildTrackCandidate(row,tier,isChinese)
        local w=manager:MeasureStringX(UIFont.Small,fullText)
        if w<=availableWidth or tier==6 then
            local relX=0
            for _,seg in ipairs(segments) do
                seg.relX=relX
                local segW=manager:MeasureStringX(UIFont.Small,seg.text)
                relX=relX+segW
            end
            return segments,fullText
        end
    end
end

function Cards.phaseTrackText(row)
    local isChinese=Cards.isChinese()
    local _,fullText=buildTrackCandidate(row,1,isChinese)
    return fullText
end


function Cards.assetStatus(row,asset)
    if asset.kind=='cargo' and asset.custodyState=='CARRIED' then return 'TRANSIT' end
    if asset.custodyState=='TRANSIT' then return 'TRANSIT' end
    if asset.custodyState=='UNCOLLECTED' then return 'WAITING' end
    if asset.custodyState=='WITHDRAWN' then return 'WITHDRAWN' end
    if asset.custodyState=='RECONCILE' then return 'RECONCILE' end
    if asset.custodyState=='STORED' then return 'STORED' end
    if asset.custodyState=='STATION' or asset.custodyState=='RETURNED' or asset.custodyState=='CONSUMED' then
        return asset.custodyState
    end
    if asset.held then return 'WITHDRAWN' end
    if asset.delivered then
        return 'STORED'
    end
    if row.reason=='ITEM_MISSING' and (asset.kind=='materials' or asset.kind=='cargo') then
        return 'MISSING'
    end
    if asset.kind=='held' then
        return 'WITHDRAWN'
    end
    local phase=row.phase or row.state or ''
    if (phase=='CRAFTING' or phase=='COMMITTING') and asset.kind=='materials' then
        return 'PROCESSING'
    end
    if phase=='COLLECTING' or phase=='COLLECT' or phase=='HAULING' or asset.kind=='cargo' then
        return 'TRANSIT'
    end
    if row.bucket=='attention' and not asset.delivered then
        return 'RECONCILE'
    end
    return 'WAITING'
end

function Cards.rows()
    local CardPanel=require 'EmberRoutesProbe/UI/CardPanel'
    local Badge=require 'EmberRoutesProbe/UI/SemanticBadge'
    local icons=require('EmberRoutesProbe/UI/ItemPresentation').new()
    return {emptyColor=Theme.muted,prepare=function(list,row)
        local p,h=list.emberPad,list.emberFontHeight
        local key=row.uncertain and 'RECONCILE' or row.closed and 'COMPLETED'
            or row.bucket=='active' and 'PROCESSING' or row.bucket=='paused' and 'PAUSED' or 'WAITING'
        local badge=Badge.resolve(key,row.stateText or text('filter_'..(row.bucket or 'waiting')))
        badge.fontHeight=h badge.textWidth=getTextManager():MeasureStringX(UIFont.Small,badge.displayText)
        local width=list.width-p*2
        local badgeW=math.min(width-p*2,badge.textWidth+p*2)
        local icon=icons:icon(row.product)
        local offset=icon and h*2+p or 0
        local title=Text.wrapLimited(Cards.title(row),math.max(1,width-p*2-offset),UIFont.Small,2)
        local subtitle=Text.wrapLimited(row.kind=='DEMAND' and (row.detailContext or row.summaryText or '')
            or row.name or text('unassigned'),math.max(1,width-p*2-offset),UIFont.Small,1)[1] or ''
        local badgeY=p+#title*h+h+p/2
        local fraction=row.target and row.target>0 and math.min(1,(row.delivered or 0)/row.target) or nil
        return {height=badgeY+h+p*3,title=title,subtitle=subtitle,badge=badge,badgeW=badgeW,badgeY=badgeY,
            icon=icon,offset=offset,width=width,p=p,h=h,fraction=fraction,
            frame={statusColor=badge.color},selectedFrame={statusColor=badge.color,selected=true}}
    end,draw=function(list,y,entry)
        local v=entry.item.visual local p,h=v.p,v.h
        if y+list:getYScroll()+entry.height<=0 or y+list:getYScroll()>=list.height then return y+entry.height end
        CardPanel.draw(list,p,y+p/2,v.width,entry.height-p,list.selected==entry.index and v.selectedFrame or v.frame)
        if v.icon then list:drawTextureScaledAspect(v.icon,p*2,y+p,h*2,h*2,1,1,1,1) end
        for i,line in ipairs(v.title) do Theme.text(list,line,p*2+v.offset,y+p+(i-1)*h,Theme.textColor) end
        Theme.text(list,v.subtitle,p*2+v.offset,y+p+#v.title*h,Theme.muted)
        Badge.draw(list,p*2,y+v.badgeY,v.badgeW,h+p,v.badge)
        if v.fraction then Visual.meter(list,p*2,y+entry.height-p*1.3,math.max(1,v.width-p*2),math.max(3,p/2),v.fraction,v.badge.color) end
        return y+entry.height
    end}
end

-- Pure display rows. InfoList owns card/badge/meter layout and native scrolling.
function Cards.detailRows(row,expanded)
    local rows={}
    local function tone(r)
        return r.uncertain and 'RECONCILE' or r.closed and (r.state=='CANCELLED' and 'PAUSED' or 'COMPLETED')
            or r.state=='STOPPING' and 'STOPPING' or r.bucket=='active' and 'PROCESSING'
            or r.bucket=='paused' and 'PAUSED' or 'WAITING'
    end
    local function card(title,lines,status,statusText,meters)
        rows[#rows+1]={isCardRow=true,title=title,lines=lines or {},status=status,statusText=statusText,meters=meters}
    end
    local function action(r)
        local step=r.stages and r.stages[r.stageIndex or 1]
        if step then return getText(step.labelKey) end
        local index=Cards.phaseIndex(r)
        return Cards.stageNames(r)[index]
    end
    local function notice(r)
        if r.uncertain then return text('reconcile') end
        if r.responsibilitySummary then return r.responsibilitySummary end
        if r.demandReason then return r.demandReason end
        if r.bucket=='active' or r.closed then return end
        local code=r.reason
        if code and code~='' and code~='WAITING_CLAIM' and code~='RUNNING' then
            local label=r.reasonText or Cards.reason(code)
            return label==code and text('detail_conditions') or label
        end
    end
    if not row then card(text('selectOrder')) return rows end
    local overview={}
    if row.kind=='DEMAND' then
        overview[#overview+1]=row.detailContext
        overview[#overview+1]=row.demandSummary
    elseif row.compact then overview[#overview+1]=row.summaryText end
    local meters={}
    if row.target and row.target>0 then
        if row.produced~=nil then
            meters[#meters+1]={text=text('detail_produced'),value=tostring(row.produced)..' / '..tostring(row.target),fraction=math.min(1,row.produced/row.target)}
        end
        meters[#meters+1]={text=text('detail_delivered'),value=tostring(row.delivered or 0)..' / '..tostring(row.target),fraction=math.min(1,(row.delivered or 0)/row.target)}
    end
    card(Cards.title(row),overview,tone(row),row.stateText or text('filter_'..(row.bucket or 'waiting')),meters)
    rows[#rows].hero=true
    local alert=notice(row)
    if alert then card(text('detail_attention'),{alert},row.uncertain and 'RECONCILE' or 'WAITING') end
    local children=row.children or {}
    if #children>0 then
        for _,child in ipairs(children) do
            local lines={action(child) or Cards.reason(child.phase)}
            local why=notice(child) if why and why~=alert then lines[#lines+1]=why end
            if child.carrierAvailable==false then lines[#lines+1]=text('carrierMissing') end
            card(child.name or text('unassigned'),lines,(#children>1 or child.uncertain) and tone(child) or nil)
        end
    elseif row.kind~='DEMAND' and row.name then
        local lines={action(row)}
        if row.cargoHeld and row.cargoHeld>0 then lines[#lines+1]=text('detail_carrying',row.cargoHeld) end
        if row.carrierAvailable==false then lines[#lines+1]=text('carrierMissing') end
        card(text('worker',row.name),lines)
    end
    local grouped,keys={},{}
    local function assets(r)
        for _,asset in ipairs(r.assets or {}) do
            local status=Cards.assetStatus(r,asset)
            local key=(asset.fullType or asset.displayName or '?')..':'..(asset.kind or '')..':'..status
            local group=grouped[key]
            if not group then group={asset=asset,status=status,count=0} grouped[key]=group keys[#keys+1]=key end
            group.count=group.count+1
        end
    end
    assets(row) for _,child in ipairs(children) do assets(child) end
    local alerts={RECONCILE=true,MISSING=true,DISCREPANCY=true}
    table.sort(keys,function(a,b)
        local aa,bb=alerts[grouped[a].status]==true,alerts[grouped[b].status]==true
        if aa~=bb then return aa end return a<b
    end)
    if #keys>0 then
        rows[#rows+1]={text=text('detail_items'),color=Theme.muted}
        local limit=expanded and 64 or 6
        for i=1,math.min(limit,#keys) do
            local g=grouped[keys[i]] local a=g.asset
            rows[#rows+1]={isAssetRow=true,fullType=a.fullType,
                name=a.fullType and getItemNameFromFullType(a.fullType) or a.displayName or text('unknownItem'),
                status=g.status,statusText=a.statusText or a.kind=='cargo' and g.status=='STORED' and text('detail_delivered')
                    or a.kind=='cargo' and g.status=='WITHDRAWN' and text('detail_held') or nil,count=g.count,kind=a.kind}
        end
        if #keys>limit then card(text('moreAssets',#keys-limit)) end
    end
    if expanded then
        for _,r in ipairs(#children>0 and children or {row}) do
            for _,step in ipairs(r.stages or r.workflow and r.workflow.steps or {}) do
                local status=step.status or 'PLANNED'
                card(getText(step.labelKey),step.progress and {step.progress} or {},
                    status=='COMPLETED' and 'COMPLETED' or status=='UNCERTAIN' and 'RECONCILE'
                    or status=='ACTIVE' and 'PROCESSING' or status=='STOPPING' and 'STOPPING' or 'WAITING',text('step_'..status))
            end
        end
        local notes={}
        if row.membership then notes[#notes+1]=require('EmberRoutesProbe/MembershipText').summary(row.membership) end
        if row.coverageText then notes[#notes+1]=row.coverageText end
        if row.noteKey then notes[#notes+1]=getText(row.noteKey) end
        if type(row.source)=='table' and row.source.x then notes[#notes+1]=text('source',row.source.x,row.source.y,row.source.z) end
        if type(row.destination)=='table' and row.destination.x then notes[#notes+1]=text('destination',row.destination.x,row.destination.y,row.destination.z) end
        if row.targetLocation then local t=row.targetLocation notes[#notes+1]=text('targetLocation',t.x,t.y,t.z) end
        if row.requested and row.target and row.requested~=row.target then notes[#notes+1]=text('rounded',row.requested,row.target) end
        if row.allocationSummary then notes[#notes+1]=row.allocationSummary end
        for _,node in ipairs(row.nodes or {}) do notes[#notes+1]=text('node',#notes+1,node.name or node.product,node.requested or 0) end
        if (row.kind=='HAUL' or row.kind=='DELIVERY') and not row.closed then notes[#notes+1]=text('haulRecovery') end
        if #notes>0 then card(text('detail_more'),notes) end
    end
    return rows
end
function Cards.details(owner,bounds)
    local info=require('EmberRoutesProbe/UI/InfoList').new(owner,bounds)
    return {list=info.list,set=function(_,row,expanded) info:set(Cards.detailRows(row,expanded)) end}
end
return Cards
