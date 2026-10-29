-- Colonist Dossier Drawer: side-attached flyout window for full traits, skill tree, and searchable recipe library.
require 'ISUI/ISCollapsableWindow'
require 'ISUI/ISButton'
require 'ISUI/ISTextEntryBox'
require 'ISUI/ISScrollingListBox'
local Theme=require 'EmberRoutesProbe/UI/Theme'
local Layout=require 'EmberRoutesProbe/UI/Layout'
local StatMeter=require 'EmberRoutesProbe/UI/StatMeter'
local Tooltip=require 'EmberRoutesProbe/UI/TooltipAnchor'

---@class EmberRoutesPersonnelDossierDrawer:ISCollapsableWindow
local DossierDrawer=ISCollapsableWindow:derive('EmberRoutesPersonnelDossierDrawer')
local function text(key,...) return getText('IGUI_EmberRoutesProbe_Personnel_'..key,...) end

function DossierDrawer:new(owner,x,y,width,height)
    local o=ISCollapsableWindow.new(self,x,y,width,height)
    o.owner,o.fontHeight,o.pad=owner,owner.fontHeight,owner.pad
    o.title=text('dossierTitle')
    o.resizable=false
    o.background=true
    o.backgroundColor=Theme.window
    o.borderColor=Theme.border
    o.activeTab='skills'
    o.searchQuery=''
    o.worker=nil
    o.details=nil
    o.texUnitFill=getTexture('media/ui/SkillPanel/SkillUnit_Fill.png') or getTexture('media/ui/XpSystemUI/SkillUnitFilled.png')
    o.texUnitBorder=getTexture('media/ui/SkillPanel/SkillUnit_Border.png') or getTexture('media/ui/XpSystemUI/SkillUnitBorder.png')
    o:initialise()
    return o
end

function DossierDrawer:initialise()
    ISCollapsableWindow.initialise(self)
end

function DossierDrawer:createChildren()
    ISCollapsableWindow.createChildren(self)
    local h,p=self.fontHeight,self.pad
    local th=self:titleBarHeight()
    local btnH=math.ceil(h*1.55)

    -- Tab Switcher Bar directly under title
    local tabW=math.floor((self.width-p*3)/2)
    self.tabSkillsBtn=ISButton:new(p,th+p/2,tabW,btnH,text('tabSkills'),self,function()
        self:selectTab('skills')
    end)
    self.tabSkillsBtn:initialise()
    Theme.button(self.tabSkillsBtn,true)
    self:addChild(self.tabSkillsBtn)

    self.tabRecipesBtn=ISButton:new(p*2+tabW,th+p/2,tabW,btnH,text('tabRecipes'),self,function()
        self:selectTab('recipes')
    end)
    self.tabRecipesBtn:initialise()
    Theme.button(self.tabRecipesBtn)
    self:addChild(self.tabRecipesBtn)

    local contentY=th+p+btnH
    local contentH=self.height-contentY-p

    -- 1. Skills & Traits List
    self.skillsList=ISScrollingListBox:new(p,contentY,self.width-p*2,contentH)
    self.skillsList:initialise()
    self.skillsList.font=UIFont.Small
    self.skillsList.itemheight=math.ceil(h*2.2)
    self.skillsList.backgroundColor=Theme.panel
    self.skillsList.borderColor=Theme.border
    self.skillsList.drawBorder=true
    self.skillsList.doDrawItem=function(list,y,item,alt) return self:drawSkillItem(list,y,item,alt) end
    self:addChild(self.skillsList)

    -- 2. Recipe Search & List
    local searchH=math.ceil(h*1.6)
    self.searchBox=ISTextEntryBox:new('',p,contentY,self.width-p*2,searchH)
    self.searchBox:initialise()
    self.searchBox:instantiate()
    self.searchBox.font=UIFont.Small
    self.searchBox.onTextChange=function()
        self.searchQuery=string.lower(self.searchBox:getText() or '')
        self:rebuildRecipeList()
    end
    self:addChild(self.searchBox)

    local recipeListY=contentY+searchH+p/2
    local recipeListH=self.height-recipeListY-p
    self.recipesList=ISScrollingListBox:new(p,recipeListY,self.width-p*2,recipeListH)
    self.recipesList:initialise()
    self.recipesList.font=UIFont.Small
    self.recipesList.itemheight=math.ceil(h*1.8)
    self.recipesList.backgroundColor=Theme.panel
    self.recipesList.borderColor=Theme.border
    self.recipesList.drawBorder=true
    self.recipesList.doDrawItem=function(list,y,item,alt) return self:drawRecipeItem(list,y,item,alt) end
    self:addChild(self.recipesList)

    self:selectTab('skills')
    if self.worker then
        self:refresh()
    end
end

function DossierDrawer:selectTab(tab)
    self.activeTab=tab
    local isSkills=(tab=='skills')
    self.tabSkillsBtn.backgroundColor=isSkills and Theme.selected or Theme.control
    self.tabSkillsBtn.borderColor=isSkills and Theme.accent or Theme.border
    self.tabRecipesBtn.backgroundColor=not isSkills and Theme.selected or Theme.control
    self.tabRecipesBtn.borderColor=not isSkills and Theme.accent or Theme.border

    self.skillsList:setVisible(isSkills)
    self.searchBox:setVisible(not isSkills)
    self.recipesList:setVisible(not isSkills)
end

function DossierDrawer:setWorker(worker)
    self.worker=worker
    if worker then
        self.title=text('dossierTitle')..' - '..worker.name
        local Personnel=require 'EmberRoutesProbe/PersonnelService'
        self.details=Personnel.details(self.owner.actor,self.owner.entry.id,worker.id)
    else
        self.title=text('dossierTitle')
        self.details=nil
    end
    self:refresh()
end

function DossierDrawer:refresh()
    if not self.skillsList or not self.recipesList then return end
    self:rebuildSkillList()
    self:rebuildRecipeList()
end

function DossierDrawer:rebuildSkillList()
    if not self.skillsList then return end
    self.skillsList:clear()
    local d=self.details
    local h,p=self.fontHeight,self.pad
    if not d then return end

    -- 1. Traits section item
    local traits=d.traits or {}
    local traitLines=math.max(1,math.ceil(#traits/3))
    self.skillsList:addItem('__TRAITS__',{isTraits=true,traits=traits,height=h*(traitLines+1)+p*2})

    local CATEGORY_WEIGHTS={
        ['被动技能']=1, ['Passive']=1, ['IGUI_perks_Passive']=1,
        ['体能']=2, ['Physical']=2, ['PhysicalCategory']=2, ['IGUI_perks_PhysicalCategory']=2,
        ['敏捷']=3, ['Agility']=3, ['IGUI_perks_Agility']=3,
        ['战斗']=4, ['Combat']=4, ['IGUI_perks_Combat']=4,
        ['战斗 - 近战']=5, ['Combat - Melee']=5, ['CombatMelee']=5, ['IGUI_perks_CombatMelee']=5,
        ['战斗 - 远程']=6, ['Combat - Firearms']=6, ['CombatFirearms']=6, ['IGUI_perks_CombatFirearms']=6,
        ['枪械']=7, ['Firearm']=7, ['IGUI_perks_Firearm']=7,
        ['合成']=8, ['Crafting']=8, ['IGUI_perks_Crafting']=8,
        ['求生']=9, ['Survival']=9, ['Survivalist']=9, ['IGUI_perks_Survivalist']=9,
        ['农业']=10, ['Farming']=10, ['FarmingCategory']=10, ['IGUI_perks_FarmingCategory']=10,
    }
    local function getCategoryTitle(cat)
        if not cat or cat=='' then return text('skillsTitle') end
        local raw=tostring(cat):gsub('^Perks%.', '')
        if getTextOrNull then
            local tr=getTextOrNull('IGUI_perks_'..raw)
            if tr then return tr end
            local stripped=raw:gsub('Category$', '')
            local trStripped=getTextOrNull('IGUI_perks_'..stripped)
            if trStripped then return trStripped end
        end
        return cat
    end

    -- 2. Group skills by parent category (Vanilla PZ style)
    local groups={}
    local groupOrder={}
    for _,s in ipairs(d.skills or {}) do
        local cat=getCategoryTitle(s.parent)
        if not groups[cat] then
            groups[cat]={}
            groupOrder[#groupOrder+1]=cat
        end
        groups[cat][#groups[cat]+1]=s
    end

    table.sort(groupOrder,function(a,b)
        local wa=CATEGORY_WEIGHTS[a] or 99
        local wb=CATEGORY_WEIGHTS[b] or 99
        if wa~=wb then return wa<wb end
        return a<b
    end)

    for _,cat in ipairs(groupOrder) do
        -- Category Header with gold text and subtle separator
        self.skillsList:addItem('__CAT_'..cat,{isHeader=true,title=cat,height=math.ceil(h*1.8)})
        local perkList=groups[cat]
        table.sort(perkList,function(a,b) return a.name<b.name end)
        for _,s in ipairs(perkList) do
            self.skillsList:addItem(s.name,{isSkill=true,skill=s,height=math.ceil(h*1.8)})
        end
    end
end

function DossierDrawer:drawSkillItem(list,y,entry,alt)
    local item=entry.item
    local h,p=self.fontHeight,self.pad
    local itemH=entry.height or list.itemheight

    if y+list:getYScroll()+itemH<=0 or y+list:getYScroll()>=list.height then return y+itemH end

    if item.isTraits then
        Theme.text(list,text('traitsTitle'),p,y+2,Theme.gold)
        local curX=p
        local badgeY=y+h+2
        local badgeH=h+2
        if #item.traits==0 then
            Theme.text(list,text('noTraits'),p,badgeY,Theme.muted)
        else
            for _,t in ipairs(item.traits) do
                local tw=getTextManager():MeasureStringX(UIFont.Small,t)+8
                if curX+tw>list.width-p*2 then curX=p badgeY=badgeY+badgeH+2 end
                Theme.rect(list,curX,badgeY,tw,badgeH,{r=0.12,g=0.18,b=0.24,a=0.9})
                Theme.rect(list,curX,badgeY,tw,badgeH,{r=0.30,g=0.50,b=0.70,a=0.9},true)
                Theme.text(list,t,curX+4,badgeY+1,{r=0.65,g=0.85,b=1.0,a=1})
                curX=curX+tw+4
            end
        end
        return y+itemH
    end

    if item.isHeader then
        Theme.rect(list,0,y,list.width,itemH,{r=0.08,g=0.10,b=0.13,a=0.9})
        Theme.text(list,item.title,p,y+(itemH-h)/2,Theme.gold)
        Theme.rect(list,p,y+itemH-1,list.width-p*2,1,Theme.border)
        return y+itemH
    end

    if item.isSkill then
        local s=item.skill
        if alt then Theme.rect(list,0,y,list.width,itemH,Theme.panel) end

        -- Left: Skill Name (e.g. 木工)
        local hasLevel=(s.level and s.level>0)
        local nameColor=hasLevel and Theme.textColor or Theme.muted
        Theme.text(list,s.name,p+6,y+(itemH-h)/2,nameColor)

        -- Right: Vanilla PZ 10-pip square progress bar
        local pipSize=math.max(10,math.floor(h*0.72))
        local pipGap=2
        local totalPipW=10*pipSize+9*pipGap
        local multW=(s.multiplier and s.multiplier>1) and 34 or 0
        local pipsX=list.width-p-totalPipW-multW-8
        local pipsY=y+(itemH-pipSize)/2

        for i=1,10 do
            local px=pipsX+(i-1)*(pipSize+pipGap)
            if i<=s.level then
                -- Unlocked level: Golden Fill & Border (Vanilla PZ 1.0, 0.89, 0.38)
                if self.texUnitFill then
                    list:drawTextureScaled(self.texUnitFill,px,pipsY,pipSize,pipSize,1,1.0,0.89,0.38)
                else
                    Theme.rect(list,px,pipsY,pipSize,pipSize,{r=1.0,g=0.89,b=0.38,a=1})
                end
                if self.texUnitBorder then
                    list:drawTextureScaled(self.texUnitBorder,px,pipsY,pipSize,pipSize,1,1.0,0.89,0.38)
                end
            else
                -- Locked / Empty level: Dark grey border
                if self.texUnitBorder then
                    list:drawTextureScaled(self.texUnitBorder,px,pipsY,pipSize,pipSize,0.8,0.28,0.30,0.34)
                else
                    Theme.rect(list,px,pipsY,pipSize,pipSize,{r=0.20,g=0.22,b=0.25,a=0.8},true)
                end
            end
        end

        -- Multiplier / Boost
        if s.multiplier and s.multiplier>1 then
            local multStr='×'..string.format('%.1f',s.multiplier)
            Theme.text(list,multStr,pipsX+totalPipW+6,y+(itemH-h)/2,Theme.gold)
        end
        return y+itemH
    end

    return y+itemH
end

function DossierDrawer:rebuildRecipeList()
    if not self.recipesList then return end
    self.recipesList:clear()
    local d=self.details
    if not d or not d.knowledge then return end
    local q=self.searchQuery
    for _,rec in ipairs(d.knowledge) do
        if q=='' or string.find(string.lower(rec),q,1,true) then
            self.recipesList:addItem(rec,{recipe=rec})
        end
    end
end

function DossierDrawer:drawRecipeItem(list,y,entry,alt)
    local h,p=self.fontHeight,self.pad
    local itemH=entry.height or list.itemheight
    if y+list:getYScroll()+itemH<=0 or y+list:getYScroll()>=list.height then return y+itemH end
    if alt then Theme.rect(list,0,y,list.width,itemH,Theme.panel) end
    local glyph='●'
    Theme.text(list,glyph,p,y+(itemH-h)/2,Theme.accent)
    Theme.text(list,entry.item.recipe or entry.text,p+h,y+(itemH-h)/2,Theme.textColor)
    return y+itemH
end

function DossierDrawer:prerender()
    ISCollapsableWindow.prerender(self)
    -- Keep docked attached to dashboard
    local dash=self.owner and self.owner.owner
    if dash and dash.getX and dash.getY then
        local targetX=dash:getX()+dash.width+4
        local screenW=getCore():getScreenWidth()
        if targetX+self.width>screenW then targetX=dash:getX()-self.width-4 end
        if math.abs(self:getX()-targetX)>2 or math.abs(self:getY()-dash:getY())>2 then
            self:setX(targetX)
            self:setY(dash:getY())
            self:setHeight(dash.height)
        end
    end
end

function DossierDrawer:close()
    self:removeFromUIManager()
    self:setVisible(false)
    if self.owner then
        self.owner.dossierDrawerOpen=false
    end
end

function DossierDrawer:dispose()
    Tooltip.clear(self.skillsList)
    Tooltip.clear(self.recipesList)
    self:close()
end

return DossierDrawer
