-- Real production HUD and lifecycle; only actor/world-facing service data are fixtures.
require "env"
require "ISUI/ISMouseDrag"
require "ISUI/ISPanelJoypad"
require "ISUI/ISTextEntryBox"
local subscribers = 0
local function watch(callback)
    subscribers = subscribers + 1
    local released = false
    return function() if not released then subscribers = subscribers - 1 released = true end end
end
local rows = {
    {id='preview-ada', slot=0, name='Ada Mercer', health=96, healthText='Health: 96%', command='Following / slot 1',
        actual='Keeping formation', feedback='', moods={{tone='STORED',label='Well fed'}}},
    {id='preview-noah', slot=1, name='Noah Brooks', health=52, healthText='Health: 52%', command='Wait here',
        actual='Recovering stamina', feedback='', moods={{tone='PROCESSING',label='Tired'},{tone='MISSING',label='Thirsty'}}},
    {id='preview-ruth', slot=2, name='Ruth Chen', health=24, healthText='Health: 24%', command='Return to settlement',
        actual='Route blocked', feedback='Waiting for a clear route', blocked=true, moods={{tone='MISSING',label='Injured'}}}
}
local session
PreviewServices['EmberRoutesProbe/Settlement/SquadService'] = {new=function(actor, owner)
    session = {rows=rows,closed=false,dirty=true}
    function session:valid() return not self.closed end
    function session:refresh() local dirty=self.dirty self.dirty=false return dirty end
    function session:invalidate() self.dirty=true end
    function session:close() self.closed=true end
    function session:targets(selected)
        local result={} local any=false
        for _,row in ipairs(rows) do if selected[row.id] then any=true end end
        for _,row in ipairs(rows) do if not any or selected[row.id] then result[#result+1]=row end end
        return result
    end
    function session:command() error('Preview cannot execute world commands') end
    return session
end}
PreviewServices['EmberRoutesProbe/Settlement/PersonnelService'] = {watchPortrait=watch}
PreviewServices['EmberRoutesProbe/Work/LaborSignals'] = {watch=watch}
local actorData = {}
local actor = {getModData=function() return actorData end}
local HUD = require 'EmberRoutesProbe/UI/SquadHUD'
local hud = HUD:new(actor,function() end,function() end)
-- addChild during initialise already instantiates the parent in the installed engine.
hud:initialise()
if not hud.javaObject then hud:instantiate() end
NativePreview = hud
NativePreview.previewBanner = false
hud:show()
hud:setX(40) hud:setY(24)
NativePreview.smoke = function(self)
    assert(#self.cards==3 and subscribers==2, 'HUD projection or activation ownership failed')
    assert(self.javaObject:getControls():size()==4, 'Native HUD header buttons detached')
    self:selectAll()
    assert(self.selected['preview-ada'] and self.selected['preview-ruth'], 'Real HUD selection failed')
    self.smokeSummary='Production SquadHUD projects 3 service rows and selects members'
end
PreviewDispose = function()
    hud:close()
    assert(session.closed and subscribers==0, 'HUD preview leaked service subscriptions')
end
PreviewRegions = function()
    local regions={}
    for _,card in ipairs(hud.cards) do
        local top=math.max(card.y,hud.bodyBounds.y)
        local bottom=math.min(card.y+card.height,hud.bodyBounds.y+hud.bodyBounds.height)
        if bottom>top then regions[#regions+1]={id='member:'..card.id,label=card.name,
            x=hud.x+8,y=hud.y+top,width=hud.width-16,height=bottom-top,
            source='Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/SquadHUD.lua'} end
    end
    return regions
end
