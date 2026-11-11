-- PublicOrderDialogBlueprint.lua - EmberRoutes UI
-- Blueprint rows: hero output card, materials / tools breakdown,
-- multi-step production chain steps and the status-bar message.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

local Recipe = require 'EmberRoutesProbe/Crafting/ProductionRecipe'
local Catalog = require 'EmberRoutesProbe/Crafting/CraftingCatalog'
local Cached = require 'EmberRoutesProbe/UI/CachedList'
local Theme = require 'EmberRoutesProbe/UI/Theme'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end
local function craftText(key,...) return getText('IGUI_EmberRoutesProbe_Crafting_'..key,...) end

local function attach(Page)
function Page:updateBlueprint()
    self:updateConversion()
    local row=self.rows[self.recipeCombo.selected]
    if not row or not row.id then
        Cached.reconcile(self.blueprintList,{},function() return '' end,function() return '' end,true)
        self.statusNotice=text('chooseRecipe')
        return
    end

    local spec=self.currentSpec or (Recipe.read(row.id) and Recipe.describe(Recipe.read(row.id))) or row
    local preview=self.previewData
    local targetQty=tonumber(self.quantity:getText()) or 1
    if self.activeTab=='stock' then
        targetQty=tonumber(self.batch:getText()) or 10
    end

    local yield=(row and (row.resultCount or row.yield)) or (spec and (spec.resultCount or spec.yield)) or 1
    if not yield or yield<1 then yield=1 end
    local units=math.max(1,math.ceil(targetQty/yield))
    local totalExpected=units*yield

    local rows={}
    local function add(r) rows[#rows+1]=r end

    -- 1. Hero Output Card
    local prodType=row.product or (spec and spec.product)
    local prodName=(spec and spec.outputs and type(spec.outputs[1])=='table' and spec.outputs[1].name)
        or (row and row.outputs and row.outputs[1] and row.outputs[1].name)
        or (getItemNameFromFullType and prodType and getItemNameFromFullType(prodType))
        or (prodType and tostring(prodType):match("[^.]+$"))
        or row.name or (spec and spec.name) or 'Product'
    local recipeTitle=row.name or (spec and spec.name)
    local subStr=text('batchCount',yield,units)
    if recipeTitle and recipeTitle~=prodName then
        subStr=subStr..' | '..recipeTitle
    end
    add({
        kind='output',
        fullType=prodType,
        title=prodName..' x'..totalExpected,
        sub=subStr,
        heading=text('outputHeading'),
        label='output:'..tostring(row.id)..':'..tostring(prodType)..':'..totalExpected
    })

    -- 2. Inputs & Tools Breakdown
    local hasInputs=spec and spec.inputs and #spec.inputs>0
    if hasInputs then
        -- Materials (keep == false)
        local matHeaded=false
        for _,input in ipairs(spec.inputs) do
            if not input.keep then
                if not matHeaded then
                    add({kind='heading',section='materials',label=text('materialsHeading')})
                    matHeaded=true
                end
                local need=input.count*units
                local count=preview and preview.counts and preview.counts[input.slot]
                local avail=count and count.available or 0
                local isMissing=(count and count.available<need) or (count==nil)
                local precursor=isMissing and preview and preview.chain and #preview.chain.nodes>1
                local choices=input.choices or {}
                local first=choices[1]
                if count and count.fullType then
                    for _,choice in ipairs(choices) do
                        if choice.fullType==count.fullType then first=choice break end
                    end
                end
                local itemName=first and first.name or (input.names and input.names[1]) or 'Material'
                local subStr=tostring(avail)..' / '..need
                if precursor then subStr=subStr..'  '..text('chainSupplyTag') end
                add({
                    kind='input',
                    slot=input.slot,
                    fullType=first and first.fullType,
                    title=itemName,
                    sub=subStr,
                    known=count~=nil,
                    missing=isMissing and not precursor,
                    precursor=precursor,
                    isTool=false,
                    choices=choices,
                    label='input:'..tostring(row.id)..':'..tostring(input.slot)..':'..tostring(first and first.fullType)..':'..need..':'..tostring(avail)
                })
            end
        end

        -- Tools (keep == true)
        local toolHeaded=false
        for _,input in ipairs(spec.inputs) do
            if input.keep then
                if not toolHeaded then
                    add({kind='heading',section='tools',label=text('toolsHeading')})
                    toolHeaded=true
                end
                local choices=input.choices or {}
                local count=preview and preview.counts and preview.counts[input.slot]
                local hasTool=count and count.available>=1
                local first=choices[1]
                if count and count.fullType then
                    for _,choice in ipairs(choices) do
                        if choice.fullType==count.fullType then first=choice break end
                    end
                end
                local toolName=first and first.name or (input.names and input.names[1]) or 'Tool'
                local subStr=hasTool and craftText('readyBadge') or craftText('shortageBadge')
                if #choices>1 then
                    local altNames={}
                    for _,c in ipairs(choices) do
                        if c.name~=toolName and not altNames[c.name] then
                            altNames[#altNames+1]=c.name
                            altNames[c.name]=true
                        end
                    end
                    if #altNames>0 then
                        subStr=subStr..' | '..text('toolAlternatives',table.concat(altNames,' / '))
                    end
                end
                add({
                    kind='input',
                    slot=input.slot,
                    fullType=first and first.fullType,
                    title=toolName,
                    sub=subStr,
                    known=count~=nil,
                    missing=not hasTool,
                    precursor=false,
                    isTool=true,
                    choices=choices,
                    label='tool:'..tostring(row.id)..':'..tostring(input.slot)..':'..tostring(first and first.fullType)..':'..tostring(hasTool)..':'..tostring(#choices)
                })
            end
        end
    end

    -- 3. Multi-Step Production Chain Steps
    if preview and preview.chain and #preview.chain.nodes>1 then
        add({kind='heading',label=craftText('chainPlanHeading',#preview.chain.nodes)})
        local byId,byType=Catalog.productionIndex()
        for i,node in ipairs(preview.chain.nodes) do
            local isLast=(i==#preview.chain.nodes)
            local stepBadge=craftText(isLast and 'stepFinal' or 'stepPrecursor',i)
            local surfaceBadge=node.surface and craftText('badgeSurface') or craftText('badgeHand')
            local canSwitch=false
            local nextRecipeId,nextRecipeName
            if not isLast and byType and node.product then
                local producers=byType[node.product] or {}
                if #producers>1 then
                    for idx,cand in ipairs(producers) do
                        if cand.id==node.recipeId then
                            local nextIdx=(idx%#producers)+1
                            nextRecipeId=producers[nextIdx].id
                            nextRecipeName=producers[nextIdx].name
                            canSwitch=true
                            break
                        end
                    end
                    if not canSwitch and #producers>0 then
                        nextRecipeId=producers[1].id
                        nextRecipeName=producers[1].name
                        canSwitch=true
                    end
                end
            end
            local switchText=canSwitch and text('switchRecipe',nextRecipeName) or nil
            add({
                kind='chain_step',
                fullType=node.product,
                stepIndex=i,
                isLast=isLast,
                stepBadge=stepBadge,
                surfaceBadge=surfaceBadge,
                title=node.recipeName,
                sub=craftText('planOutput',tostring(node.totalOutput or node.requested)),
                canSwitch=canSwitch,
                nextRecipeId=nextRecipeId,
                nextRecipeName=nextRecipeName,
                switchText=switchText,
                label='chain_step:'..i..':'..tostring(node.recipeId or node.product)..':'..tostring(nextRecipeId or '')
            })
        end
    else
        -- Single-step summary chain card
        local isSurface=row.surface or (spec and spec.surface)
        local surfaceBadge=isSurface and craftText('badgeSurface') or craftText('badgeHand')
        add({
            kind='chain_step',
            fullType=row.product or (spec and spec.product),
            stepIndex=1,
            isLast=true,
            stepBadge=craftText('stepFinal',1),
            surfaceBadge=surfaceBadge,
            title=row.name or (spec and spec.name),
            sub=craftText('planOutput',tostring(totalExpected)),
            label='single_step:1:'..tostring(row.id)..':'..totalExpected
        })
    end

    Cached.reconcile(self.blueprintList,rows,function(r) return r.label end,function(r) return r.label end,true)

    -- Update Status Bar Message
    if preview then
        if preview.chain and #preview.chain.nodes>1 then
            self.statusNotice=text('statusChain')
            self.statusColor=Theme.accent
        elseif preview.state=='WAITING' then
            self.statusNotice=getText('IGUI_EmberRoutesProbe_Public_WAITING_CLAIM') self.statusColor=Theme.muted
        elseif preview.state=='READY' then
            self.statusNotice=text('statusReady')
            self.statusColor={r=0.35,g=0.88,b=0.60,a=1.0}
        elseif preview.conditions and #preview.conditions>0 then
            self.statusNotice=text('statusShortage')
            self.statusColor={r=0.95,g=0.45,b=0.35,a=1.0}
        else
            self.statusNotice=text('statusReady')
            self.statusColor={r=0.35,g=0.88,b=0.60,a=1.0}
        end

        if preview.eligibleWorkerCount~=nil then
            local workerMsg = (preview.eligibleWorkerCount>0)
                and getText('IGUI_EmberRoutesProbe_Public_workersReady',preview.eligibleWorkerCount)
                or getText('IGUI_EmberRoutesProbe_Public_noWorkersReady')
            self.statusNotice = self.statusNotice .. ' | ' .. workerMsg
        end
    else
        self.statusNotice=text('statusChecking')
        self.statusColor=Theme.muted
    end
end
end

return attach
