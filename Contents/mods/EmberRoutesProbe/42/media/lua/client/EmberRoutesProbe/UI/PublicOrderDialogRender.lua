-- PublicOrderDialogRender.lua - EmberRoutes UI
-- Rendering: labels, page indicator, conversion dashboard card,
-- blueprint header and the wrapped status card.
-- Moved verbatim from PublicOrderDialog.lua (P1 split); behaviour unchanged.
-- Attached to EmberRoutesPublicOrderDialog by PublicOrderDialog.lua
-- (mixin pattern: this module receives the class table, so there is no
-- circular require back to the dialog module).

local Theme = require 'EmberRoutesProbe/UI/Theme'
local Text = require 'EmberRoutesProbe/UI/Text'

local function text(key,...) return getText('IGUI_EmberRoutesProbe_Public_'..key,...) end

local function attach(Page)
function Page:prerender()
    ISCollapsableWindow.prerender(self)
    local h=self.fontHeight

    -- Left Column Labels
    Theme.text(self,text('recipeSelect'),self.searchLabel.x,self.searchLabel.y+(self.searchLabel.height-h)/2,Theme.textColor)
    Theme.text(self,text('surfaceSelect'),self.surfaceLabel.x,self.surfaceLabel.y+(self.surfaceLabel.height-h)/2,Theme.textColor)

    local pageStr
    if self._pageNum~=self.page or self._totalNum~=self.totalPages then
        self._pageNum=self.page self._totalNum=self.totalPages
        pageStr=(self.page or 1)..' / '..(self.totalPages or 1)
        self._pageKey=pageStr
        self._pageW=getTextManager():MeasureStringX(UIFont.Small,pageStr)
    else
        pageStr=self._pageKey
    end
    local pageW=self._pageW
    Theme.text(self,pageStr,self.pageIndicatorRegion.x+(self.pageIndicatorRegion.width-pageW)/2,self.pageIndicatorRegion.y+(self.pageIndicatorRegion.height-h)/2,Theme.muted)

    if self.activeTab=='order' then
        Theme.text(self,text('targetQuantity'),self.quantityLabel.x,self.quantityLabel.y+(self.quantityLabel.height-h)/2,Theme.textColor)
    else
        Theme.text(self,text('stockThreshold'),self.minimumLabel.x,self.minimumLabel.y+(self.minimumLabel.height-h)/2,Theme.textColor)
        Theme.text(self,text('stockBatch'),self.batchLabel.x,self.batchLabel.y+(self.batchLabel.height-h)/2,Theme.textColor)
    end

    -- Conversion Dashboard Card
    if self.calcDashboardRegion then
        local cr=self.calcDashboardRegion
        Theme.rect(self,cr.x,cr.y,cr.width,cr.height,Theme.panel)
        Theme.rect(self,cr.x,cr.y,cr.width,cr.height,Theme.border,true)

        local row=self.rows and self.rows[self.recipeCombo.selected]
        if not row or not self.conversion then
            local emptyText=text('chooseRecipe')
            if self._mKey~=emptyText then self._mKey=emptyText
                self._mW=getTextManager():MeasureStringX(UIFont.Small,emptyText) end
            local tw=self._mW
            Theme.text(self,emptyText,cr.x+math.max(self.pad,math.floor((cr.width-tw)/2)),cr.y+math.floor((cr.height-h)/2),Theme.muted)
        else
            local conv=self.conversionFull or ''
            if self._cKey~=conv then self._cKey=conv
                self._cW=getTextManager():MeasureStringX(UIFont.Small,conv) end
            local tw=self._cW
            if tw<=cr.width-self.pad*2 then
                Theme.text(self,self.conversionFull,cr.x+math.max(self.pad,math.floor((cr.width-tw)/2)),cr.y+math.floor((cr.height-h)/2),Theme.gold)
            else
                local l1=self.conversionLine1 or '' local l2=self.conversionLine2 or ''
                if self._l1Key~=l1 then self._l1Key=l1
                    self._l1W=getTextManager():MeasureStringX(UIFont.Small,l1) end
                if self._l2Key~=l2 then self._l2Key=l2
                    self._l2W=getTextManager():MeasureStringX(UIFont.Small,l2) end
                local l1w=self._l1W local l2w=self._l2W
                local startY=cr.y+math.max(2,math.floor((cr.height-h*2-2)/2))
                Theme.text(self,self.conversionLine1 or '',cr.x+math.max(self.pad,math.floor((cr.width-l1w)/2)),startY,Theme.textColor)
                Theme.text(self,self.conversionLine2 or '',cr.x+math.max(self.pad,math.floor((cr.width-l2w)/2)),startY+h+2,Theme.gold)
            end
        end
    end

    -- Right Column Header
    Theme.text(self,text('blueprintTitle'),self.blueprintHeaderRegion.x,self.blueprintHeaderRegion.y+(self.blueprintHeaderRegion.height-h)/2,Theme.gold)

    -- Right Column Status Card
    local sr=self.blueprintStatusRegion
    Theme.rect(self,sr.x,sr.y,sr.width,sr.height,Theme.panel)
    Theme.rect(self,sr.x,sr.y,sr.width,sr.height,Theme.border,true)

    local msg=self.notice or self.statusNotice or text('statusChecking')
    -- Wrapping measures every character; cache per text and width.
    local wrapWidth=sr.width-self.pad*2
    if self._statusMsg~=msg or self._statusWidth~=wrapWidth then
        self._statusMsg=msg self._statusWidth=wrapWidth
        self._statusLines=Text.wrapLimited(msg,wrapWidth,UIFont.Small,2)
    end
    local lines=self._statusLines
    local curY=sr.y+math.max(2,math.floor((sr.height-#lines*h)/2))
    for _,line in ipairs(lines) do
        Theme.text(self,line,sr.x+self.pad,curY,self.notice and Theme.gold or (self.statusColor or Theme.textColor))
        curY=curY+h
    end
end
end

return attach
