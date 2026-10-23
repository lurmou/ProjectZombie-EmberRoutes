require "ISUI/ISPanel"
local Theme=require "EmberRoutesProbe/UI/Theme"
local Text=require "EmberRoutesProbe/UI/Text"
local Presentation=require "EmberRoutesProbe/UI/ItemPresentation"
local Words=require "EmberRoutesProbe/CraftingText"
local Grid={}
function Grid.new(owner,bounds,select)
    ---@type any
    local panel=ISPanel:new(bounds.x,bounds.y,bounds.width,bounds.height)
    panel:initialise() panel.background=false panel.fontHeight=owner.fontHeight panel.pad=owner.pad
    panel.columns=math.max(1,math.floor(bounds.width/(owner.fontHeight*8)))
    panel.rowHeight=owner.fontHeight*5+owner.pad
    panel.capacity=math.min(24,panel.columns*math.max(1,math.floor(bounds.height/panel.rowHeight)))
    panel.presentation=Presentation.new() panel.cells={} panel.selected=0
    function panel:setRows(rows,id)
        local keys={tostring(id)} for _,row in ipairs(rows) do keys[#keys+1]=row.id end
        local key=table.concat(keys,"\n") if self.rowsKey==key then return end self.rowsKey=key
        self.cells={} self.selected=0 local h,p=self.fontHeight,self.pad
        local w=(self.width-p*(self.columns-1))/self.columns
        for i,row in ipairs(rows) do
            local cell={row=row,x=((i-1)%self.columns)*(w+p),y=math.floor((i-1)/self.columns)*self.rowHeight,
                width=w,height=self.rowHeight-p,icon=self.presentation:icon(row.product),
                lines=Text.wrapLimited(row.name,w-p*2,UIFont.Small,2)}
            self.cells[i]=cell if row.id==id then self.selected=i end
        end
        self.empty=Words.get("catalogEmpty")
    end
    function panel:prerender()
        ISPanel.prerender(self)
        if #self.cells==0 then Theme.text(self,self.empty or Words.get("catalogLoading"),self.pad,self.pad,Theme.muted) end
        local h,p=self.fontHeight,self.pad
        local mx=self.getMouseX and self:getMouseX() or nil
        local my=self.getMouseY and self:getMouseY() or nil
        for i,cell in ipairs(self.cells) do
            local isSelected=(i==self.selected)
            local isHover=mx and my and mx>=cell.x and mx<cell.x+cell.width and my>=cell.y and my<cell.y+cell.height
            local bg=isSelected and Theme.selected or (isHover and Theme.hover or Theme.control)
            local bc=isSelected and Theme.accent or (isHover and Theme.accent or Theme.border)

            Theme.rect(self,cell.x,cell.y,cell.width,cell.height,bg)
            Theme.rect(self,cell.x,cell.y,cell.width,cell.height,bc,true)

            if isSelected then
                -- Signature AE2 active slot cyber indicator: 2px fluix cyan bar on left edge
                self:drawRect(cell.x,cell.y,2,cell.height,1,Theme.accent.r,Theme.accent.g,Theme.accent.b)
            end

            if cell.icon then self:drawTextureScaledAspect(cell.icon,cell.x+p,cell.y+p,h*1.8,h*1.8,1,1,1,1) end
            if not cell.row.supported then
                Theme.text(self,"!",cell.x+cell.width-h*1.5,cell.y+p,Theme.gold or Theme.accent)
            elseif cell.row.yield>1 then
                local badge="x"..cell.row.yield
                local bw=getTextManager():MeasureStringX(UIFont.Small,badge)
                Theme.text(self,badge,cell.x+cell.width-bw-p,cell.y+p,Theme.accent)
            end
            for n,line in ipairs(cell.lines) do
                Theme.text(self,line,cell.x+p,cell.y+h*2+p+(n-1)*h,isSelected and Theme.textColor or (isHover and Theme.textColor or Theme.textColor))
            end
        end
    end
    function panel:onMouseDown(x,y)
        owner:focusList(self)
        for _,cell in ipairs(self.cells) do
            if x>=cell.x and x<cell.x+cell.width and y>=cell.y and y<cell.y+cell.height then select(cell.row) return true end
        end
        return true
    end
    function panel:move(delta)
        if #self.cells==0 then return end
        self.selected=math.max(1,math.min(#self.cells,math.max(1,self.selected)+delta)) select(self.cells[self.selected].row)
    end
    function panel:onKeyPress(key)
        if not owner:isListFocused(self) then return end
        if key==Keyboard.KEY_UP then self:move(-self.columns)
        elseif key==Keyboard.KEY_DOWN then self:move(self.columns)
        elseif key==Keyboard.KEY_LEFT then self:move(-1)
        elseif key==Keyboard.KEY_RIGHT then self:move(1)
        elseif key==Keyboard.KEY_ESCAPE then owner:close() end
    end
    function panel:isKeyConsumed(key) return owner:isListFocused(self) and (key==Keyboard.KEY_UP or key==Keyboard.KEY_DOWN or key==Keyboard.KEY_LEFT or key==Keyboard.KEY_RIGHT or key==Keyboard.KEY_ESCAPE) end
    function panel:onJoypadDirUp() self:move(-self.columns) end
    function panel:onJoypadDirDown() self:move(self.columns) end
    function panel:onJoypadDirLeft() self:move(-1) end
    function panel:onJoypadDirRight() self:move(1) end
    function panel:onJoypadDown(button)
        if button==Joypad.BButton then owner:close()
        elseif button==Joypad.AButton and owner.focusDraft then owner:focusDraft()
        elseif button==Joypad.LBumper then owner:turn(-1)
        elseif button==Joypad.RBumper then owner:turn(1) end
    end
    panel:setWantKeyEvents(true) owner:addChild(panel)
    return panel
end
return Grid
