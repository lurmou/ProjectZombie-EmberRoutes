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
    for _,key in ipairs({'id','name','title','state','phase','reason','generation','produced','delivered','target','bodyMode','bucket','carrierAvailable'}) do
        fields[#fields+1]=tostring(row[key])
    end
    for _,asset in ipairs(row.assets or {}) do fields[#fields+1]=tostring(asset.fullType or '') end
    local member=row.membership
    if member then
        for _,key in ipairs({'revision','context','settlementId','settlementName','reason'}) do fields[#fields+1]=tostring(member[key]) end
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
        local nodeState=(i<cur) and 'done' or (i==cur) and 'active' or 'wait'
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

local function bomCapsule(status)
    local badge = SemanticBadge.resolve(status)
    local label = "[" .. (badge.displayText or status) .. "]"
    return label, badge.color or BOM_COLORS[status] or Theme.muted
end

function Cards.assetStatus(row,asset)
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

local icons=require('EmberRoutesProbe/UI/ItemPresentation').new()

function Cards.rows()
    return {emptyColor=Theme.muted,prepare=function(list,row)
        local p,h=list.emberPad,list.emberFontHeight
        local iconSize=h*2 local width=math.max(1,list.width-p*4-iconSize)
        local kind=row.product or (row.assets and row.assets[1] and row.assets[1].fullType)
        local curPhase=Cards.phaseIndex(row)
        local curProg=Cards.stageProgress(row,curPhase)
        local blockerText=nil
        if (row.bucket=='attention' or row.reason=='ITEM_MISSING') and row.assets then
            for _,asset in ipairs(row.assets) do
                local st=Cards.assetStatus(row,asset)
                if st=='MISSING' and asset.fullType then
                    local resolve=_G.getItemNameFromFullType
                    local rawName=type(resolve)=='function' and resolve(asset.fullType) or asset.fullType
                    local itemName=Text.wrapLimited(rawName,math.max(40,width-140),UIFont.Small,1)[1] or rawName
                    blockerText='▲ '..getText('IGUI_EmberRoutesProbe_shortage')..': '..itemName
                    break
                end
            end
        end
        local names=Cards.stageNames(row)
        local stageName=names[curPhase] or ''
        local activeLabel=curPhase==0 and Cards.reason(row.state) or stageName..(curProg~='' and (' '..curProg) or '')
        local lines={Cards.title(row),row.name or ''}
        for i=1,2 do lines[i]=Text.wrapLimited(lines[i],width,UIFont.Small,1)[1] or '' end
        return {
            lines=lines,
            curPhase=curPhase,
            nodeCount=#names,
            activeLabel=activeLabel,
            blockerText=blockerText,
            height=h*3+p*2,
            state=state(row),
            icon=icons:icon(kind),
            iconSize=iconSize
        }
    end,draw=function(list,y,entry)
        local v=entry.item.visual local h,p=list.emberFontHeight,list.emberPad
        if y+list:getYScroll()+v.height<=0 or y+list:getYScroll()>=list.height then return y+v.height end
        if list.selected==entry.index then Theme.rect(list,0,y,list.width,v.height,Theme.selected)
        elseif list.mouseoverselected==entry.index then Theme.rect(list,0,y,list.width,v.height,Theme.hover) end
        local color=Visual.colors[v.state] or Theme.accent
        if v.icon then list:drawTextureScaledAspect(v.icon,p,y+p/2,v.iconSize,v.iconSize,1,1,1,1) end
        Visual.mark(list,p+v.iconSize/3,y+p/2+v.iconSize,h/2,v.state,color)
        local x=p*2+v.iconSize
        Theme.text(list,v.lines[1],x,y+p/2,Theme.textColor)
        Theme.text(list,v.lines[2],x,y+p/2+h,Theme.muted)

        local railX=x
        local railY=y+p/2+2*h+math.floor(h/2)
        local totalRailW=math.min(130,list.width-x-p*2)
        local nodeCount=v.nodeCount or 4
        local nodeSpacing=math.floor(totalRailW/math.max(1,nodeCount-1))
        local curPhase=v.curPhase or 1

        for seg=1,nodeCount-1 do
            local x1=railX+(seg-1)*nodeSpacing
            local x2=railX+seg*nodeSpacing
            local segDone=(seg<curPhase)
            local segColor=segDone and COLOR_DONE or COLOR_ARROW
            local lineH=segDone and 2 or 1
            Theme.rect(list,x1,railY-math.floor(lineH/2),x2-x1,lineH,segColor)
        end

        local nowMs=getTimestampMs()
        local pulseA=0.65+0.35*math.sin(nowMs*0.006)
        for i=1,nodeCount do
            local nx=railX+(i-1)*nodeSpacing
            if i<curPhase then
                Theme.rect(list,nx-3,railY-3,6,6,COLOR_DONE)
            elseif i==curPhase then
                local isAttention=(entry.item.value.bucket=='attention')
                local actR=(isAttention and 1.0 or COLOR_ACTIVE.r)
                local actG=(isAttention and 0.42 or COLOR_ACTIVE.g)
                local actB=(isAttention and 0.38 or COLOR_ACTIVE.b)
                list:drawRect(nx-4,railY-4,8,8,pulseA,actR,actG,actB)
                Theme.rect(list,nx-4,railY-4,8,8,Theme.textColor,true)
            else
                Theme.rect(list,nx-2,railY-2,5,5,COLOR_WAIT,true)
            end
        end

        local textAfterRail=railX+totalRailW+p/2
        if v.blockerText then
            Theme.text(list,v.blockerText,textAfterRail,y+p/2+2*h,Theme.status.ERROR)
        elseif curPhase<=nodeCount then
            local isAttention=(entry.item.value.bucket=='attention')
            local lblCol=isAttention and Theme.status.ERROR or Theme.gold
            Theme.text(list,v.activeLabel,textAfterRail,y+p/2+2*h,lblCol)
        else
            Theme.text(list,(getTextOrNull('IGUI_EmberRoutesProbe_Order_done') or 'IGUI_EmberRoutesProbe_Order_done'),textAfterRail,y+p/2+2*h,COLOR_DONE)
        end

        local row=entry.item.value
        if (row.target or 0)>0 then Visual.meter(list,x,y+v.height-p,math.max(1,list.width-x-p),math.max(2,p/3),
            math.min(1,(row.delivered or 0)/row.target),color) end
        return y+v.height
    end}
end

function Cards.details(owner,bounds)
    local card={}
    local info=require('EmberRoutesProbe/UI/InfoList').new(owner,bounds) card.list=info.list
    function card:set(row)
        local lines={}
        local function add(value,color,fullType)
            if value~=nil and value~='' then
                lines[#lines+1]={text=tostring(value),color=color or Theme.textColor,fullType=fullType}
            end
        end
        if not row then add(text('selectOrder'),Theme.muted)
        else
            add(Cards.title(row),Theme.gold)

            local curPhase=Cards.phaseIndex(row)
            local names=Cards.stageNames(row)
            local stageName=names[curPhase] or ''
            local curProg=Cards.stageProgress(row,curPhase)
            local stageDesc=stageName~='' and (stageName..(curProg~='' and (' '..curProg) or '')) or ''
            local stateText=Cards.reason(row.state)
            local badge='['..stateText..']'..(stageDesc~='' and (' · '..text('stage',stageDesc)) or '')
            add(badge,Visual.colors[state(row)] or Theme.accent)

            local workerName=row.name and row.name~='' and row.name or text('unassigned')
            local bMode=tostring(row.bodyMode or '')
            local activity=(bMode~='' and getTextOrNull('IGUI_EmberRoutesProbe_Monitor_body_'..bMode)) or Cards.reason(bMode)
            local workerLine=text('worker',workerName)
            if activity and activity~='' and activity~=Cards.reason(row.phase) then
                workerLine=workerLine..' ('..activity..')'
            end
            add(workerLine,Theme.textColor)

            if row.membership then add(require('EmberRoutesProbe/MembershipText').summary(row.membership),Theme.muted) end
            if not row.carrierAvailable then add(text('carrierMissing'),Theme.muted) end
            if row.target and row.target>0 then
                if row.produced~=nil then add(text('produced',row.produced,row.target)) end
                add(text('delivered',row.delivered,row.target),Theme.accent)
                if row.requested~=row.target then add(text('rounded',row.requested,row.target),Theme.muted) end
            end
            if row.noteKey then add(getText(row.noteKey),Theme.muted) end
            if row.targetLocation then
                local target=row.targetLocation
                add(text('targetLocation',target.x,target.y,target.z),Theme.muted)
            end

            if row.reason and row.reason~='' and row.reason~='WAITING_CLAIM' then
                local reasonLabel=row.reasonText or Cards.reason(row.reason)
                local isAttention=(row.bucket=='attention' or row.state=='SUSPENDED')
                add(text('reason',reasonLabel),isAttention and (Visual.colors.blocked or Theme.status.ERROR) or Theme.accent)
                if isAttention and not row.readOnly then
                    local adviceKey=row.state=='SUSPENDED' and 'advice_suspended' or 'advice_blocked'
                    add('▲ '..text(adviceKey),Theme.gold)
                end
            end
            if row.uncertain then add(text('reconcile'),Theme.accent) end
            if row.cargoSummary then add(row.cargoSummary,Theme.muted) end

            if type(row.source)=='table' and row.source.x then add(text('source',row.source.x,row.source.y,row.source.z),Theme.muted) end
            if type(row.destination)=='table' and row.destination.x then add(text('destination',row.destination.x,row.destination.y,row.destination.z),Theme.muted) end

            local nodes=row.nodes or {}
            if #nodes>0 then
                add(text('chain'),Theme.accent)
                local curIndex=row.chainIndex or 1
                for i,node in ipairs(nodes) do
                    local status=(i<curIndex) and 'STORED'
                        or (i==curIndex) and (row.bucket=='attention' and 'MISSING' or 'PROCESSING')
                        or 'TRANSIT'
                    local rawName=node.name or node.product or '?'
                    if node.product then
                        local resolve=_G.getItemNameFromFullType
                        rawName=(type(resolve)=='function' and resolve(node.product)) or node.product
                    end
                    local stepTitle=text('node',i,rawName,node.requested or '?')
                    if i==row.chainIndex then stepTitle=stepTitle..' · '..text('currentStep') end
                    lines[#lines+1]={
                        isAssetRow=true,
                        fullType=node.product,
                        name=stepTitle,
                        status=status,
                        count=node.requested or 1,
                        isNode=true
                    }
                end
            end

            local assets=row.assets or {}
            if #assets>0 then
                add(text('originals',#assets),Theme.accent)
                local grouped,keys={},{}
                for _,asset in ipairs(assets) do
                    local status=Cards.assetStatus(row,asset)
                    local key=(asset.fullType or '?')..':'..(asset.kind or '')..':'..status
                    if not grouped[key] then
                        grouped[key]={asset=asset,status=status,count=0}
                        keys[#keys+1]=key
                    end
                    grouped[key].count=grouped[key].count+1
                end
                table.sort(keys)
                local maxDisplay=math.min(#keys,64)
                for i=1,maxDisplay do
                    local group=grouped[keys[i]]
                    local asset=group.asset
                    local rawName=asset.fullType and getItemNameFromFullType(asset.fullType) or text('unknownItem')
                    lines[#lines+1]={
                        isAssetRow=true,
                        fullType=asset.fullType,
                        name=rawName,
                        status=group.status,
                        count=group.count,
                        credited=asset.delivered,
                        kind=asset.kind
                    }
                end
                if #keys>64 then
                    add('... '..text('moreAssets',#keys-64),Theme.muted)
                end
            end

            if (row.kind=='HAUL' or row.kind=='DELIVERY') and not row.closed then add(text('haulRecovery'),Theme.muted) end
        end
        info:set(lines)
    end
    return card
end

return Cards
