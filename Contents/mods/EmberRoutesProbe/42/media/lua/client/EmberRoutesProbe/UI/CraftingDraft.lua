require "ISUI/ISComboBox"
require "ISUI/ISTextEntryBox"
require "ISUI/ISButton"
require "ISUI/ISModalDialog"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Cached=require "EmberRoutesProbe/UI/CachedList"
local Layout=require "EmberRoutesProbe/UI/Layout"
local Tooltip=require "EmberRoutesProbe/UI/TooltipAnchor"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"
local Words=require "EmberRoutesProbe/CraftingText"
local text=Words.get
local Draft={}
function Draft.new(owner,bounds)
    local h,p=owner.fontHeight,owner.pad
    local self={owner=owner,bounds=bounds,presentation=Presentation.new(),expanded={},workerIds={},surfaceIds={}}
    local function button(label,callback)
        local b=ISButton:new(bounds.x,bounds.y,bounds.width,h+p,label,owner,callback)
        b:initialise() Theme.button(b) Tooltip.attach(b,"prerender") owner:addChild(b) return b
    end
    self.run=button(text("button_run"),function() owner:command("run") end)
    self.teach=button(text("button_teach"),function() owner:command("teach") end)
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
    self.worker=ISComboBox:new(bounds.x,bounds.y,bounds.width,h+p,owner,function()
        if not self.syncing then owner:change({npcId=self.workerIds[self.worker.selected] or false}) end
    end)
    for _,box in ipairs({self.platform,self.worker}) do box:initialise() owner:addChild(box) end

    local function step(delta)
        local cur=tonumber(self.quantity:getText()) or 1
        local nextVal=math.max(1,math.min(9999,cur+delta))
        self.quantity:setText(tostring(nextVal))
        owner:change({quantity=nextVal})
    end
    self.btnMinus10=button("-10",function() step(-10) end)
    self.btnMinus1=button("-1",function() step(-1) end)
    self.btnPlus1=button("+1",function() step(1) end)
    self.btnPlus10=button("+10",function() step(10) end)
    self.btnMax=button(text("stepperMax"),function()
        if not self.recipe or not self.preview or not self.preview.counts then return end
        local maxBatches=9999
        local hasMaterial=false
        for _,input in ipairs(self.recipe.inputs or {}) do
            if not input.keep then
                hasMaterial=true
                local count=self.preview.counts[input.slot]
                local avail=count and count.available or 0
                local needPerBatch=input.count or 1
                local possible=math.floor(avail/needPerBatch)
                if possible<maxBatches then maxBatches=possible end
            end
        end
        if not hasMaterial or maxBatches<=0 or maxBatches==9999 then maxBatches=1 end
        local target=math.max(1,math.min(9999,maxBatches*(self.recipe.yield or 1)))
        self.quantity:setText(tostring(target))
        owner:change({quantity=target})
    end)

    self.quantity=ISTextEntryBox:new("1",bounds.x,bounds.y,h*4,h+p)
    self.quantity:initialise() self.quantity.target=owner
    self.quantity.onTextChangeFunction=function()
        local n=tonumber(self.quantity:getText())
        owner:change({quantity=n and n==math.floor(n) and n>=1 and n<=9999 and n or false})
    end
    self.quantity.tooltip=text("quantityHint") Tooltip.attach(self.quantity,"prerender") owner:addChild(self.quantity)

    local style={emptyColor=Theme.muted}
    function style.prepare(list,row)
        local icon=row.fullType and self.presentation:icon(row.fullType) or nil
        if row.kind=="heading" then
            return {height=math.floor(h*1.5),icon=nil}
        elseif row.kind=="output" or row.kind=="input" then
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
        else
            local lines=Text.wrapLimited(row.label,list.width-p*3,UIFont.Small,2)
            return {height=math.max(h+p,#lines*h+math.floor(p/2)),lines=lines,icon=nil}
        end
    end
    function style.draw(list,y,entry)
        local row,v=entry.item.value,entry.item.visual
        local visible=y+list:getYScroll()
        if visible+entry.height<0 or visible>list.height then return y+entry.height end

        if row.kind=="heading" then
            Theme.rect(list,math.floor(p/2),y+entry.height-2,list.width-p,1,Theme.border)
            Theme.text(list,row.label,p,y+math.floor(p/4),Theme.accent)
            return y+entry.height
        end

        if row.kind=="output" or row.kind=="input" then
            local slotSize=v.slotSize or math.floor(h*2.2)
            local slotX=p
            local slotY=y+math.floor((entry.height-slotSize)/2)

            Theme.rect(list,slotX,slotY,slotSize,slotSize,Theme.panel)

            local borderColor=Theme.border
            if row.kind=="output" then
                borderColor=Theme.accent
            elseif row.kind=="input" then
                if row.isTool then
                    borderColor={r=0.94,g=0.73,b=0.36,a=1}
                elseif row.missing then
                    borderColor=Theme.status.ERROR
                elseif row.known then
                    borderColor=Theme.status.READY
                end
            end
            Theme.rect(list,slotX,slotY,slotSize,slotSize,borderColor,true)

            if v.icon then
                list:drawTextureScaledAspect(v.icon,slotX+2,slotY+2,slotSize-4,slotSize-4,1,1,1,1)
            end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor(p/4)
            local subY=titleY+h

            Theme.text(list,v.title or "",textX,titleY,Theme.textColor)

            local subColor=Theme.muted
            if row.kind=="input" then
                if row.missing then
                    subColor=Theme.status.ERROR
                elseif row.known then
                    subColor=Theme.status.READY
                end
            end
            Theme.text(list,v.sub or "",textX,subY,subColor)

            if row.isTool then
                local badgeText=text("toolBadge")
                local bw=getTextManager():MeasureStringX(UIFont.Small,badgeText)+p
                local bx=list.width-p-bw
                Theme.rect(list,bx,titleY,bw,h,Theme.control)
                Theme.rect(list,bx,titleY,bw,h,borderColor,true)
                Theme.text(list,badgeText,bx+math.floor(p/2),titleY,borderColor)
            elseif row.choices and #row.choices>1 then
                local altText=text("altBadge").." "..#row.choices..(self.expanded[row.slot] and " ▲" or " ▼")
                local bw=getTextManager():MeasureStringX(UIFont.Small,altText)+p
                local bx=list.width-p-bw
                Theme.rect(list,bx,titleY,bw,h,Theme.control)
                Theme.rect(list,bx,titleY,bw,h,Theme.accent,true)
                Theme.text(list,altText,bx+math.floor(p/2),titleY,Theme.accent)
            end

            return y+entry.height
        end

        if row.kind=="choice" then
            local slotSize=v.slotSize or math.floor(h*1.6)
            local slotX=p*2
            local slotY=y+math.floor((entry.height-slotSize)/2)

            Theme.rect(list,slotX,slotY,slotSize,slotSize,Theme.control)
            Theme.rect(list,slotX,slotY,slotSize,slotSize,Theme.border,true)
            if v.icon then
                list:drawTextureScaledAspect(v.icon,slotX+1,slotY+1,slotSize-2,slotSize-2,1,1,1,1)
            end

            local textX=slotX+slotSize+p
            local titleY=slotY+math.floor((slotSize-h)/2)
            Theme.text(list,"• "..(v.title or ""),textX,titleY,Theme.accent)
            return y+entry.height
        end

        local color=row.missing and Theme.status.ERROR or Theme.textColor
        for i,line in ipairs(v.lines or {}) do
            Theme.text(list,line,p,y+math.floor(p/4)+(i-1)*h,color)
        end
        return y+entry.height
    end
    function self:activate(row)
        if not row then return end
        if row.kind=="input" and row.choices and #row.choices>1 then
            local expanded=not self.expanded[row.slot] self.expanded={} self.expanded[row.slot]=expanded owner:repaint()
        elseif row.kind=="choice" and row.fullType then owner:warehouse(row.fullType) end
    end
    self.list=Cached.create(owner,bounds,nil,style)
    self.list:setOnMouseDownFunction(owner,function(_,row) owner:focusList(self.list) if row then self:activate(row.value) end end)
    Theme.list(self.list) owner:addChild(self.list)
    local function position(control,r)
        control:setX(r.x) control:setY(r.y) control:setWidth(r.width) control:setHeight(r.height)
    end
    function self:set(recipe,preview,snapshot,value)
        self.recipe=recipe self.preview=preview self.syncing=true
        local needsSurface=recipe and recipe.supported and recipe.surface==true
        local compact=bounds.height<h*22
        local tracks={{basis=compact and h*2+p or h*3+p},{grow=1}}
        if needsSurface then tracks[#tracks+1]={basis=h+p} end
        for _,track in ipairs({{basis=h+p},{basis=h+p},{basis=compact and h*1.5 or h*2},{basis=h+p}}) do tracks[#tracks+1]=track end
        local regions=assert(Layout.axis(bounds,tracks,{direction="column",gap=p/2}))
        self.header=regions[1] position(self.list,regions[2])
        local index=3
        local hasSurfaces=#snapshot.surfaces>0
        self.platform:setVisible(needsSurface==true and hasSurfaces)
        self.surfaceHelp:setVisible(needsSurface==true and not hasSurfaces)
        local surfaceKeys={}
        for _,surface in ipairs(snapshot.surfaces) do surfaceKeys[#surfaceKeys+1]=surface.id..":"..surface.x..":"..surface.y..":"..surface.z end
        local surfaceKey=table.concat(surfaceKeys,"\n")
        if self.surfaceKey~=surfaceKey then
            self.surfaceKey=surfaceKey self.platform:hidePopup() self.platform:clear() self.surfaceIds={false} self.platform:addOption(text("selectSurface"))
            for _,surface in ipairs(snapshot.surfaces) do
                self.surfaceIds[#self.surfaceIds+1]=surface.id
                self.platform:addOption(text("surface").." ("..surface.x..", "..surface.y..", "..surface.z..")")
            end
        end
        self.platform.selected=1 for i,id in ipairs(self.surfaceIds) do if id==value.surface then self.platform.selected=i end end
        if needsSurface then position(self.platform,regions[index]) position(self.surfaceHelp,regions[index]) index=index+1 end
        position(self.worker,regions[index]) index=index+1
        local workerKeys={} for _,worker in ipairs(snapshot.workers) do workerKeys[#workerKeys+1]=worker.id..":"..worker.name end
        local workerKey=table.concat(workerKeys,"\n")
        if self.workerKey~=workerKey then
            self.workerKey=workerKey self.worker:hidePopup() self.worker:clear() self.workerIds={false} self.worker:addOption(text("noWorker"))
            for _,worker in ipairs(snapshot.workers) do self.workerIds[#self.workerIds+1]=worker.id self.worker:addOption(worker.name) end
        end
        self.worker.selected=1 for i,id in ipairs(self.workerIds) do if id==value.npcId then self.worker.selected=i end end

        local q=regions[index] index=index+1
        self.quantityLabel={x=q.x,y=q.y+p/2}
        local labelW=getTextManager():MeasureStringX(UIFont.Small,text("quantity"))+p
        local available=q.width-labelW
        local slotW=math.floor((available-p)/6)
        if slotW>=math.floor(h*0.9) then
            self.btnMinus10:setVisible(true)
            self.btnMinus1:setVisible(true)
            self.btnPlus1:setVisible(true)
            self.btnPlus10:setVisible(true)
            self.btnMax:setVisible(true)
            local stepW=slotW
            local entryW=math.max(10,available-stepW*5-math.floor(p/4)*5)
            local stepperTracks={{basis=stepW},{basis=stepW},{basis=entryW},{basis=stepW},{basis=stepW},{basis=stepW}}
            local sRegions=Layout.axis({x=q.x+labelW,y=q.y,width=available,height=q.height},stepperTracks,{gap=math.floor(p/4)})
            if sRegions then
                position(self.btnMinus10,sRegions[1])
                position(self.btnMinus1,sRegions[2])
                position(self.quantity,sRegions[3])
                position(self.btnPlus1,sRegions[4])
                position(self.btnPlus10,sRegions[5])
                position(self.btnMax,sRegions[6])
            else
                position(self.quantity,{x=q.x+q.width-h*4,y=q.y,width=h*4,height=q.height})
            end
        else
            self.btnMinus10:setVisible(false)
            self.btnMinus1:setVisible(false)
            self.btnPlus1:setVisible(false)
            self.btnPlus10:setVisible(false)
            self.btnMax:setVisible(false)
            position(self.quantity,{x=q.x+q.width-h*4,y=q.y,width=h*4,height=q.height})
        end

        self.conditionBounds=regions[index] index=index+1
        local action=assert(Layout.axis(regions[index],{{grow=2},{grow=1}},{gap=p/2}))
        position(self.run,action[1]) position(self.teach,action[2])
        local conditions=preview and preview.conditions or {}
        local reasons={} local canTeach=false local hard=false local shortage=false local limited=false
        for _,reason in ipairs(conditions) do
            reasons[#reasons+1]=Words.reason(reason)
            if reason=="NPC_RECIPE_UNKNOWN" then canTeach=true
            elseif reason=="PREVIEW_LIMIT" then limited=true
            elseif reason=="MATERIALS_UNAVAILABLE" or reason=="TOOLS_UNAVAILABLE" then shortage=true
            else hard=true end
        end
        local state=preview and preview.state or "CHECKING"
        if state=="CHECKING" then self.hint=text("checking")
        elseif #reasons>0 then self.hint=table.concat(reasons,"  ")
        else self.hint=text("executionRecheck") end
        self.conditionLines=Text.wrapLimited(self.hint,self.conditionBounds.width,UIFont.Small,2)
        self.run.tooltip=self.hint self.teach.tooltip=Words.reason("NPC_RECIPE_UNKNOWN")
        self.teach:setVisible(canTeach and not hard)
        Theme.enable(self.teach,canTeach and not hard)
        Theme.enable(self.run,recipe and recipe.supported and value.quantity~=false and value.npcId~=false
            and state~="CHECKING" and not hard and not canTeach and (state=="READY" or shortage or limited) or false,true)
        self.run:setTitle(text(shortage and "createWaiting" or "button_run"))
        local rows={} local function add(row) rows[#rows+1]=row end
        local units=recipe and recipe.yield and recipe.yield>0 and math.ceil((value.quantity or 1)/recipe.yield) or 1
        self.title=recipe and Text.wrapLimited(recipe.name,self.header.width-h*3,UIFont.Small,compact and 1 or 2) or {text("selectRecipe")}
        self.summaryY=compact and h+p/2 or h*2+p/2
        self.icon=recipe and self.presentation:icon(recipe.product)
        self.summary=recipe and recipe.supported and (text("batches").." "..units.."  |  "..text("extra").." "..(units*recipe.yield-(value.quantity or 1)).."  |  "..text(recipe.surface and "surface" or "hand")) or ""
        if recipe and not recipe.supported then add({kind="heading",label=Words.reason(recipe.reason or "RECIPE_MECHANISM_UNSUPPORTED")}) end
        for _,output in ipairs(recipe and recipe.outputs or {}) do
            local totalCount=output.count*units
            add({
                kind="output",
                fullType=output.fullType,
                title=output.name.." x"..totalCount,
                sub=text("batchOutput").." "..output.count.." ("..text("extra").." "..(totalCount-(value.quantity or 1))..")",
                label=output.name.." x"..totalCount
            })
        end
        for _,keep in ipairs({false,true}) do
            local headed=false
            for _,input in ipairs(recipe and recipe.inputs or {}) do
                if input.keep==keep then
                    if not headed then
                        add({kind="heading",label=text(keep and "keptTools" or "orderMaterials")})
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
                    local stockSub=""
                    if count==nil then
                        stockSub=text("checking")
                    elseif isMissing then
                        stockSub=text("shortageBadge")..": "..availNum.." / "..need.." ("..text("extra").." "..(need-availNum)..")"
                    else
                        stockSub=text("readyBadge")..": "..availNum.." / "..need
                    end
                    local itemName=first and first.name or input.names[1] or "?"
                    add({
                        kind="input",
                        slot=input.slot,
                        fullType=first and first.fullType,
                        title=itemName,
                        sub=stockSub,
                        label=itemName.." "..(count and tostring(availNum) or "?").." / "..need,
                        known=count~=nil,
                        missing=isMissing,
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
        self.platform:hidePopup() self.worker:hidePopup() self.quantity:unfocus()
        for _,control in ipairs({self.platform,self.surfaceHelp,self.worker,self.quantity,self.btnMinus10,self.btnMinus1,self.btnPlus1,self.btnPlus10,self.btnMax,self.list,self.run,self.teach}) do
            Tooltip.clear(control)
        end
    end
    return self
end
return Draft
