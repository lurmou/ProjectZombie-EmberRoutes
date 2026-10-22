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
    self.quantity=ISTextEntryBox:new("1",bounds.x,bounds.y,h*4,h+p)
    self.quantity:initialise() self.quantity.target=owner
    self.quantity.onTextChangeFunction=function()
        local n=tonumber(self.quantity:getText())
        owner:change({quantity=n and n==math.floor(n) and n>=1 and n<=9999 and n or false})
    end
    self.quantity.tooltip=text("quantityHint") Tooltip.attach(self.quantity,"prerender") owner:addChild(self.quantity)
    local style={emptyColor=Theme.muted}
    function style.prepare(list,row)
        local lines=Text.wrapLimited(row.label,list.width-p*3-h*2,UIFont.Small,row.kind=="choice" and 2 or 3)
        return {lines=lines,height=math.max(h*2,p+#lines*h),icon=row.fullType and self.presentation:icon(row.fullType)}
    end
    function style.draw(list,y,entry)
        local row,v=entry.item.value,entry.item.visual
        if y+list:getYScroll()+entry.height<0 or y+list:getYScroll()>list.height then return y+entry.height end
        local color=row.missing and Theme.accent or row.kind=="heading" and Theme.accent or Theme.textColor
        if v.icon then list:drawTextureScaledAspect(v.icon,p,y+p/2,h*1.6,h*1.6,1,1,1,1) end
        for i,line in ipairs(v.lines) do Theme.text(list,line,p+h*2,y+p/2+(i-1)*h,color) end
        if row.kind=="input" then Theme.text(list,row.missing and "!" or row.known and "+" or "?",list.width-p-h,y+p/2,color) end
        return y+entry.height
    end
    function self:activate(row)
        if not row then return end
        if row.kind=="input" then
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
        local q=regions[index] index=index+1 self.quantityLabel={x=q.x,y=q.y+p/2}
        position(self.quantity,{x=q.x+q.width-h*4,y=q.y,width=h*4,height=q.height})
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
            add({kind="output",fullType=output.fullType,label=output.name.." x"..(output.count*units).."  ("..text("batchOutput").." "..output.count..")"})
        end
        for _,keep in ipairs({false,true}) do
            local headed=false
            for _,input in ipairs(recipe and recipe.inputs or {}) do
                if input.keep==keep then
                    if not headed then add({kind="heading",label=text(keep and "keptTools" or "orderMaterials").." | "..text("availableRequired")}) headed=true end
                    local need=input.count*(keep and 1 or units) local count=preview and preview.counts and preview.counts[input.slot]
                    local choices=input.choices or {} local first=choices[1]
                    if count and count.fullType then for _,choice in ipairs(choices) do if choice.fullType==count.fullType then first=choice break end end end
                    local available=count and tostring(count.available) or "?"
                    local label=(first and first.name or input.names[1] or "?").."  "..available.." / "..need
                    if #choices>1 then label=label.."  ["..text("alternatives").." "..#choices.."]" end
                    add({kind="input",slot=input.slot,fullType=first and first.fullType,label=label,known=count~=nil,
                        missing=count and count.available<count.required})
                    if self.expanded[input.slot] then
                        for _,choice in ipairs(choices) do add({kind="choice",label=choice.name,fullType=choice.fullType}) end
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
        for _,control in ipairs({self.platform,self.surfaceHelp,self.worker,self.quantity,self.list,self.run,self.teach}) do Tooltip.clear(control) end
    end
    return self
end
return Draft
