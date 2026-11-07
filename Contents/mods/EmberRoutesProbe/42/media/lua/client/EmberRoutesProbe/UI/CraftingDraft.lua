require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local UICache=require "EmberRoutesProbe/UI/UICache"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Tooltip=require "EmberRoutesProbe/UI/TooltipManager"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"
local Words=require "EmberRoutesProbe/Crafting/CraftingText"
local text=Words.get
local Draft={}
function Draft.new(owner,bounds)
    local h,p=owner.fontHeight,owner.pad
    local self={owner=owner,bounds=bounds,presentation=Presentation.new(),expanded={},surfaceIds={}}

    function self:activate(row)
        if not row then return end
        if row.kind=="input" and row.choices and #row.choices>1 then
            local expanded=not self.expanded[row.slot] self.expanded={} self.expanded[row.slot]=expanded owner:repaint()
        elseif row.kind=="choice" and row.fullType then owner:warehouse(row.fullType) end
    end

    local style={emptyColor=Theme.muted}
    function style.prepare(list,row)
        local icon=row.fullType and self.presentation:icon(row.fullType) or nil
        if row.kind=="heading" then
            return {height=math.floor(h*1.6),icon=nil}
        elseif row.kind=="output" then
            local slotSize=math.floor(h*2.2)
            local textW=math.max(1,list.width-slotSize-p*3)
            local titleLines=Text.wrapLimited(row.title or row.label,textW,UIFont.Small,1)
            local subLines=row.sub and Text.wrapLimited(row.sub,textW,UIFont.Small,1) or {}
            local headerH=math.floor(h*1.3)
            return {
                height=slotSize+p+headerH,
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or "",
                sub=subLines[1] or "",
                headerH=headerH,
                sectionTitle=text("expectedOutput")
            }
        elseif row.kind=="input" then
            local slotSize=math.floor(h*2.2)
            local textW=math.max(1,list.width-slotSize-p*3)
            local titleLines=Text.wrapLimited(row.title or row.label,textW,UIFont.Small,1)
            local subLines=row.sub and Text.wrapLimited(row.sub,textW,UIFont.Small,1) or {}
            return {
                height=slotSize+p,
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or "",
                sub=subLines[1] or ""
            }
        elseif row.kind=="choice" then
            local slotSize=math.floor(h*1.6)
            local textW=math.max(1,list.width-slotSize-p*4)
            local titleLines=Text.wrapLimited(row.label,textW,UIFont.Small,1)
            return {
                height=slotSize+math.floor(p/2),
                icon=icon,
                slotSize=slotSize,
                title=titleLines[1] or ""
            }
        elseif row.kind=="chain_step" then
            local slotSize=math.floor(h*1.8)
            local cardH=slotSize+math.floor(p*0.6)
            local connectorH=row.isLast and 0 or math.floor(h*0.9)
            local gap=math.floor(p/2)
            local textX=p+4+slotSize+gap
            local right=list.width-p-4
            local hasSurface=row.surfaceBadge and row.surfaceBadge~=""
            local available=math.max(0,right-textX-gap*(hasSurface and 2 or 1))
            local manager=getTextManager()
            -- Bound both badges so a long translation still leaves room for the name.
            local badgeLimit=math.floor(available/3)
            local stepW=math.min(manager:MeasureStringX(UIFont.Small,row.stepBadge or "")+p,badgeLimit)
            local surfaceW=hasSurface and math.min(manager:MeasureStringX(UIFont.Small,row.surfaceBadge)+p,badgeLimit) or 0
            local surfaceX=right-surfaceW
            local nameX=textX+stepW+gap
            local nameW=math.max(0,(hasSurface and surfaceX-gap or right)-nameX)
            local function fit(label,width)
                if not label or width<=0 then return "" end
                local clipped=Text.wrapLimited(label,width,UIFont.Small,1)[1] or ""
                -- wrapLimited permits a single glyph wider than an extremely narrow column.
                return manager:MeasureStringX(UIFont.Small,clipped)<=width and clipped or ""
            end
            return {
                width=list.width,
                height=cardH+connectorH,
                icon=icon,
                slotSize=slotSize,
                cardH=cardH,
                connectorH=connectorH,
                title=fit(row.title or row.label,nameW),
                sub=fit(row.sub,right-textX),
                stepBadge=fit(row.stepBadge,stepW-p),
                surfaceBadge=fit(row.surfaceBadge,surfaceW-p),
                textX=textX,nameX=nameX,stepW=stepW,surfaceX=surfaceX,surfaceW=surfaceW,
                isLast=row.isLast
            }
        else
            local lines=Text.wrapLimited(row.label,list.width-p*3,UIFont.Small,2)
            return {height=math.max(h+p,#lines*h+math.floor(p/2)),lines=lines,icon=nil}
        end
    end
    local activeList, activeScroll
    local function safeText(txt,tx,ty,color)
        if not txt or txt=="" then return end
        local sy=ty+activeScroll
        -- Submit intersecting glyphs; the native list stencil clips the edge.
        if sy+h>0 and sy<activeList.height then
            Theme.text(activeList,txt,tx,ty,color)
        end
    end

    local function safeRect(rx,ry,rw,rh,color,border)
        if not color or rw<=0 or rh<=0 then return end
        local sy=ry+activeScroll
        if sy+rh<=0 or sy>=activeList.height then return end
        local clipTop=math.max(0,-sy)
        local clipBottom=math.max(0,(sy+rh)-activeList.height)
        local drawY=ry+clipTop
        local drawH=rh-clipTop-clipBottom
        if drawH>0 then
            Theme.rect(activeList,rx,drawY,rw,drawH,color,border)
        end
    end

    local function safeTexture(tex,tx,ty,tw,th)
        if not tex then return end
        local sy=ty+activeScroll
        if sy+th>0 and sy<activeList.height then
            activeList:drawTextureScaledAspect(tex,tx,ty,tw,th,1,1,1,1)
        end
    end

    function style.draw(list,y,entry)
        local row,v=entry.item.value,entry.item.visual
        if row.kind=="chain_step" and v.width~=list.width then
            v=style.prepare(list,row) entry.item.visual=v
        end
        local scroll=list:getYScroll()
        local visible=y+scroll
        if visible+entry.height<=0 or visible>=list.height then return y+entry.height end
        activeList=list activeScroll=scroll

        if row.kind=="heading" then
            local barH=math.floor(h*1.2)
            local barY=y+math.floor((entry.height-barH)/2)
            safeRect(p,barY,list.width-p*2,barH,Theme.control,false)
            local accentColor=row.section=="tools" and {r=0.94,g=0.73,b=0.36,a=1} or Theme.accent
            safeRect(p,barY,3,barH,accentColor,false)
            safeText(row.label,p+8,barY+math.floor((barH-h)/2),Theme.textColor)
            return y+entry.height
        end

        if row.kind=="output" then
            local headerH=v.headerH or math.floor(h*1.3)
            local barH=math.floor(h*1.2)
            safeRect(p,y+2,list.width-p*2,barH,Theme.control,false)
            safeRect(p,y+2,3,barH,Theme.accent,false)
            safeText(v.sectionTitle or text("expectedOutput"),p+8,y+2+math.floor((barH-h)/2),Theme.accent)

            local slotSize=v.slotSize or math.floor(h*2.2)
            local slotX=p
            local slotY=y+headerH+math.floor(p/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.panel,false)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.accent,true)

            if v.icon then
                safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4)
            end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            safeText(v.title or "",textX,titleY,Theme.textColor)
            if v.sub and v.sub~="" then
                safeText(v.sub,textX,subY,Theme.muted)
            end

            return y+entry.height
        end

        if row.kind=="input" then
            local slotSize=v.slotSize or math.floor(h*2.2)
            local slotX=p
            local slotY=y+math.floor((entry.height-slotSize)/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.panel,false)

            local borderColor=Theme.border
            local countColor=Theme.textColor
            if row.precursor then borderColor=Theme.accent countColor=Theme.accent
            elseif row.isTool then
                borderColor={r=0.94,g=0.73,b=0.36,a=1}
                countColor=row.missing and Theme.status.ERROR or Theme.status.READY
            elseif row.missing then
                borderColor=Theme.status.ERROR
                countColor=Theme.status.ERROR
            elseif row.known then
                borderColor=Theme.border
                countColor=Theme.status.READY
            end
            safeRect(slotX,slotY,slotSize,slotSize,borderColor,true)

            if v.icon then
                safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4)
            end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            safeText(v.title or "",textX,titleY,Theme.textColor)
            safeText(v.sub or "",textX,subY,countColor)

            if row.isTool then
                local badgeText=text("toolBadge")
                local bw=UICache.measure(UIFont.Small,badgeText)+p
                local bx=list.width-p-bw
                safeRect(bx,titleY,bw,h,Theme.control,false)
                safeRect(bx,titleY,bw,h,borderColor,true)
                safeText(badgeText,bx+math.floor(p/2),titleY,borderColor)
            elseif row.choices and #row.choices>1 then
                -- Badge label is rebuilt only when its two inputs change; the
                -- old code concatenated and re-measured it on every draw.
                local expanded=self.expanded[row.slot] and true or false
                local cache=self._altTextCache
                if not cache then cache={} self._altTextCache=cache end
                local entry=cache[row.slot]
                local altText
                if entry and entry.count==#row.choices and entry.expanded==expanded then
                    altText=entry.text
                else
                    altText=text("altBadge").." "..#row.choices..(expanded and " ^" or " v")
                    cache[row.slot]={count=#row.choices,expanded=expanded,text=altText}
                end
                local bw=UICache.measure(UIFont.Small,altText)+p
                local bx=list.width-p-bw
                safeRect(bx,titleY,bw,h,Theme.control,false)
                safeRect(bx,titleY,bw,h,Theme.accent,true)
                safeText(altText,bx+math.floor(p/2),titleY,Theme.accent)
            end

            return y+entry.height
        end

        if row.kind=="choice" then
            local slotSize=v.slotSize or math.floor(h*1.6)
            local slotX=p*2
            local slotY=y+math.floor((entry.height-slotSize)/2)

            safeRect(slotX,slotY,slotSize,slotSize,Theme.control,false)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.border,true)
            if v.icon then
                safeTexture(v.icon,slotX+1,slotY+1,slotSize-2,slotSize-2)
            end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor((slotSize-h)/2)
            safeText("* "..(v.title or ""),textX,titleY,Theme.accent)
            return y+entry.height
        end

        if row.kind=="chain_step" then
            local cardW=list.width-p*2
            local cardH=v.cardH or math.floor(h*2.4)
            local cardY=y
            local isLast=row.isLast
            local nodeColor=isLast and (Theme.gold or Theme.accent) or Theme.accent

            safeRect(p,cardY,cardW,cardH,Theme.panel,false)
            safeRect(p,cardY,cardW,cardH,isLast and nodeColor or Theme.border,true)

            local slotSize=v.slotSize or math.floor(h*1.8)
            local slotX=p+4
            local slotY=cardY+math.floor((cardH-slotSize)/2)
            safeRect(slotX,slotY,slotSize,slotSize,Theme.control,false)
            safeRect(slotX,slotY,slotSize,slotSize,isLast and nodeColor or Theme.border,true)
            if v.icon then
                safeTexture(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4)
            end

            local badgeH=math.floor(h*1.0)
            local badgeW=v.stepW
            local textX=v.textX
            local titleY=cardY+math.max(2,math.floor((cardH-h*2)/2))
            local subY=titleY+h

            safeRect(textX,titleY,badgeW,badgeH,Theme.control,false)
            safeRect(textX,titleY,badgeW,badgeH,nodeColor,true)
            safeText(v.stepBadge,textX+math.floor(p/2),titleY+math.floor((badgeH-h)/2),nodeColor)

            local nameX=v.nameX
            safeText(v.title or "",nameX,titleY,Theme.textColor)
            safeText(v.sub or "",textX,subY,nodeColor)

            if row.surfaceBadge then
                local sW=v.surfaceW
                local sX=v.surfaceX
                safeRect(sX,titleY,sW,badgeH,Theme.control,false)
                safeRect(sX,titleY,sW,badgeH,Theme.border,true)
                safeText(v.surfaceBadge,sX+math.floor(p/2),titleY+math.floor((badgeH-h)/2),Theme.muted)
            end

            if not isLast then
                local pipeX=math.floor(list.width/2)
                local pipeTop=cardY+cardH
                local connH=v.connectorH or math.floor(h*0.9)
                local pipeBottom=pipeTop+connH
                safeRect(pipeX-1,pipeTop,2,connH-5,Theme.accent,false)
                safeRect(pipeX-4,pipeBottom-6,8,1,Theme.accent,false)
                safeRect(pipeX-3,pipeBottom-5,6,1,Theme.accent,false)
                safeRect(pipeX-2,pipeBottom-4,4,1,Theme.accent,false)
                safeRect(pipeX-1,pipeBottom-3,2,2,Theme.accent,false)
            end

            return y+entry.height
        end

        local color=row.missing and Theme.status.ERROR or Theme.textColor
        for i,line in ipairs(v.lines or {}) do
            safeText(line,p,y+math.floor(p/4)+(i-1)*h,color)
        end
        return y+entry.height
    end

    self.list=Cached.create(owner,bounds,nil,style)
    self.list:setOnMouseDownFunction(owner,function(_,row) owner:focusList(self.list) if row then self:activate(row.value) end end)
    Theme.list(self.list)
    owner:addChild(self.list)

    local function button(label,callback)
        local b=ISButton:new(bounds.x,bounds.y,bounds.width,h+p,label,owner,callback)
        b:initialise() Theme.button(b) Tooltip.register(b,{method="prerender",owner=owner}) owner:addChild(b) return b
    end
    self.run=button(text("button_run"),function() owner:command("run") end)
    self.surfaceHelp=button(text("registerSurface"),function()
        if self.helpModal then return end
        local width=math.min(owner.width,h*30)
        local message=table.concat(Text.wrap(text("surfaceHint"),width-p*4,UIFont.Small),"\n")
        local modal=ISModalDialog:new(owner:getAbsoluteX()+(owner.width-width)/2,owner:getAbsoluteY()+h*2,width,0,message,false,owner,
            function() self.helpModal=nil end,owner.actor:getIndex())
        function modal:destroy() self:setVisible(false) self:removeFromUIManager() end
        self.helpModal=modal modal:initialise() modal:addToUIManager()
    end)
    self.platform=ISComboBox:new(bounds.x,bounds.y,bounds.width,h+p,owner,function()
        if not self.syncing then owner:change({surface=self.surfaceIds[self.platform.selected] or false}) end
    end)
    self.platform:initialise() owner:addChild(self.platform)

    self.stepper=require('EmberRoutesProbe/UI/StepperInput'):new(bounds.x,bounds.y,bounds.width,h+p,1,1,9999,nil,function(value)
        owner:change({quantity=value and value==math.floor(value) and value>=1 and value<=9999 and value or false})
    end)
    owner:addChild(self.stepper)
    self.quantity=self.stepper.entry
    self.quantity.tooltip=text("quantityHint") Tooltip.register(self.quantity,{method="prerender",owner=owner})

    local function position(control,r)
        control:setX(r.x) control:setY(r.y) control:setWidth(r.width) control:setHeight(r.height)
    end
    function self:set(recipe,preview,snapshot,value)
        self.recipe=recipe self.preview=preview self.syncing=true
        if type(value.quantity)=="number" and tonumber(self.quantity:getText())~=value.quantity then self.stepper:setValue(value.quantity) end
        local needsSurface=recipe and recipe.supported and recipe.surface==true
        local compact=bounds.height<h*22
        local rowH=compact and math.floor(h*1.2) or (h+p)
        local tracks={{basis=compact and (h*2+math.floor(p/2)) or (h*3+p)},{grow=1}}
        if needsSurface then tracks[#tracks+1]={basis=rowH} end
        for _,track in ipairs({{basis=rowH},{basis=compact and math.floor(h*1.3) or (h*2)},{basis=rowH}}) do tracks[#tracks+1]=track end
        local regions=assert(Layout.axis(bounds,tracks,{direction="column",gap=p/2}))
        self.header=regions[1] position(self.list,regions[2])
        local index=3
        local hasSurfaces=snapshot and snapshot.surfaces and #snapshot.surfaces>0 or false
        self.platform:setVisible(needsSurface==true)
        self.surfaceHelp:setVisible(needsSurface==true and not hasSurfaces)
        local surfaceKeys={}
        for _,surface in ipairs(snapshot.surfaces or {}) do surfaceKeys[#surfaceKeys+1]=surface.id..":"..surface.x..":"..surface.y..":"..surface.z end
        local surfaceKey=table.concat(surfaceKeys,"\n")
        if self.surfaceKey~=surfaceKey then
            self.surfaceKey=surfaceKey self.platform:hidePopup() self.platform:clear() self.surfaceIds={false} self.platform:addOption(text("autoNearestSurface"))
            for _,surface in ipairs(snapshot.surfaces or {}) do
                self.surfaceIds[#self.surfaceIds+1]=surface.id
                self.platform:addOption(text("surface").." ("..surface.x..", "..surface.y..", "..surface.z..")")
            end
        end
        self.platform.selected=1 for i,id in ipairs(self.surfaceIds) do if id==value.surface then self.platform.selected=i end end
        if needsSurface then position(self.platform,regions[index]) position(self.surfaceHelp,regions[index]) index=index+1 end

        local q=regions[index] index=index+1
        self.quantityLabel={x=q.x,y=q.y+p/2}
        local labelW=math.min(q.width*0.35,getTextManager():MeasureStringX(UIFont.Small,text("quantity"))+p)
        self.stepper:setX(q.x+labelW) self.stepper:setY(q.y)
        self.stepper:layoutCompact(math.max(1,q.width-labelW),q.height)

        self.conditionBounds=regions[index] index=index+1
        position(self.run,regions[index])
        local conditions=preview and preview.conditions or {}
        local reasons={} local hard=false local shortage=false local limited=false
        for _,reason in ipairs(conditions) do
            reasons[#reasons+1]=Words.reason(reason)
            if reason=="PREVIEW_LIMIT" then limited=true
            elseif reason=="MATERIALS_UNAVAILABLE" or reason=="TOOLS_UNAVAILABLE" then shortage=true
            elseif reason~="NPC_RECIPE_UNKNOWN" then hard=true end
        end
        local state=preview and preview.state or "CHECKING"
        if state=="CHECKING" then self.hint=text("checking")
        elseif #reasons>0 then self.hint=table.concat(reasons,"  ")
        elseif preview and preview.chain then self.hint=text("chainReady")
        else self.hint=text("executionRecheck") end
        if preview and preview.blocker then self.hint=preview.blocker.recipeName..": "..self.hint end
        self.conditionLines=Text.wrapLimited(self.hint,self.conditionBounds.width,UIFont.Small,2)
        self.run.tooltip=self.hint
        Theme.enable(self.run,recipe and recipe.supported and value.quantity~=false
            and state~="CHECKING" and not hard and (state=="READY" or shortage or limited) or false,true)
        self.run:setTitle(text(shortage and "createWaiting" or "button_run"))
        local rows={} local function add(row) rows[#rows+1]=row end
        local units=recipe and recipe.yield and recipe.yield>0 and math.ceil((value.quantity or 1)/recipe.yield) or 1
        self.title=recipe and Text.wrapLimited(recipe.name,self.header.width-h*3,UIFont.Small,compact and 1 or 2) or {text("selectRecipe")}
        self.summaryY=compact and h+p/2 or h*2+p/2
        self.icon=recipe and self.presentation:icon(recipe.product)
        self.summary=recipe and recipe.supported and (text("batches").." "..units.."  |  "..text(recipe.surface and "surface" or "hand")) or ""
        if recipe and not recipe.supported then add({kind="heading",label=Words.reason(recipe.reason or "RECIPE_MECHANISM_UNSUPPORTED")}) end
        for _,output in ipairs(recipe and recipe.outputs or {}) do
            local totalCount=output.count*units
            local subText=""
            if output.count>1 or units>1 then
                subText=text("batchOutput").." "..output.count
            end
            add({
                kind="output",
                fullType=output.fullType,
                title=output.name.." x"..totalCount,
                sub=subText,
                label=output.name.." x"..totalCount
            })
        end
        for _,keep in ipairs({false,true}) do
            local headed=false
            for _,input in ipairs(recipe and recipe.inputs or {}) do
                if input.keep==keep then
                    if not headed then
                        add({kind="heading",section=keep and "tools" or "materials",label=text(keep and "keptTools" or "orderMaterials")})
                        headed=true
                    end
                    local need=input.count*(keep and 1 or units)
                    local count=preview and preview.counts and preview.counts[input.slot]
                    local choices=input.choices or {}
                    local first=choices[1]
                    if count and count.fullType then
                        for _,choice in ipairs(choices) do
                            if choice.fullType==count.fullType then first=choice break end
                        end
                    end
                    local availNum=count and count.available or 0
                    local isMissing=count and (count.available<need) or (count==nil)
                    local precursor=isMissing and preview and preview.chain and state=="READY"
                    local stockSub=""
                    if count==nil then
                        stockSub=text("checking")
                    else
                        stockSub=tostring(availNum).." / "..need
                    end
                    if precursor then stockSub=stockSub.."  > "..text("chainSupply") end
                    local itemName=first and first.name or input.names[1] or "?"
                    add({
                        kind="input",
                        slot=input.slot,
                        fullType=first and first.fullType,
                        title=itemName,
                        sub=stockSub,
                        label=itemName.." "..(count and tostring(availNum) or "?").." / "..need..(precursor and " >" or ""),
                        known=count~=nil,
                        missing=isMissing and not precursor,
                        precursor=precursor,
                        isTool=keep,
                        choices=choices
                    })
                    if self.expanded[input.slot] then
                        for _,choice in ipairs(choices) do
                            add({kind="choice",label=choice.name,fullType=choice.fullType})
                        end
                    end
                end
            end
        end
        if preview and preview.chain and #preview.chain.nodes>1 then
            add({kind="heading",label=getText("IGUI_EmberRoutesProbe_Crafting_chainPlanHeading",#preview.chain.nodes)})
            for i,node in ipairs(preview.chain.nodes) do
                local isLast=(i==#preview.chain.nodes)
                local stepBadge=getText("IGUI_EmberRoutesProbe_Crafting_"..(isLast and "stepFinal" or "stepPrecursor"),i)
                local surfaceBadge
                -- Chain nodes carry a boolean surface requirement, not a container name.
                -- Only legacy string labels may be used as container translation keys.
                if type(node.surface)=="string" then
                    surfaceBadge=getTextOrNull("IGUI_ContainerTitle_"..node.surface) or node.surface
                elseif node.surface==true then
                    surfaceBadge=text("badgeSurface")
                else
                    surfaceBadge=text("badgeHand")
                end
                add({
                    kind="chain_step",
                    fullType=node.product,
                    stepIndex=i,
                    isLast=isLast,
                    stepBadge=stepBadge,
                    surfaceBadge=surfaceBadge,
                    title=node.recipeName,
                    sub=getText("IGUI_EmberRoutesProbe_Crafting_planOutput",tostring(node.totalOutput or node.requested)),
                    label="chain_step:"..i..":"..tostring(node.product or node.recipeName)
                })
            end
        end
        if preview and preview.partial then add({kind="heading",label=text("partialStock")}) end
        for _,skill in ipairs(preview and preview.skills or {}) do
            add({kind="skill",label=skill.name.."  "..skill.current.." / "..skill.required,missing=skill.current<skill.required})
        end
        for _,reason in ipairs(conditions) do add({kind="condition",label=Words.reason(reason),missing=true}) end
        Cached.reconcile(self.list,rows,function(row) return row.label end,function(row) return row.kind..":"..tostring(row.slot or row.fullType or row.label) end,true)
        self.syncing=false
    end
    function self:draw()
        if not self.header then return end
        if self.icon then owner:drawTextureScaledAspect(self.icon,self.header.x,self.header.y,h*2,h*2,1,1,1,1) end
        for i,line in ipairs(self.title or {}) do Theme.text(owner,line,self.header.x+h*2+p,self.header.y+(i-1)*h,Theme.textColor) end
        Theme.text(owner,self.summary or "",self.header.x+h*2+p,self.header.y+self.summaryY,Theme.muted)
        Theme.text(owner,text("quantity"),self.quantityLabel.x,self.quantityLabel.y,Theme.muted)
        for i,line in ipairs(self.conditionLines or {}) do Theme.text(owner,line,self.conditionBounds.x,self.conditionBounds.y+(i-1)*h,Theme.accent) end
    end
    function self:hide()
        if self.helpModal then self.helpModal:destroy() self.helpModal=nil end
        self.platform:hidePopup() self.quantity:unfocus()
        for _,control in ipairs({self.platform,self.surfaceHelp,self.quantity,self.stepper,self.list,self.run}) do
            Tooltip.clear(control)
        end
    end
    return self
end
return Draft
