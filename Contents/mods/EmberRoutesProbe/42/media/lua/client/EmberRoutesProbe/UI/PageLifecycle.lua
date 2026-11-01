-- A watch may notify synchronously and close its window before returning a
-- release handle. Tokens also reject notifications from earlier watches.
local Lifecycle={}
local TooltipManager=require 'EmberRoutesProbe/UI/TooltipManager'
function Lifecycle.mount(page,watch,receive)
    if page.active or page.disposed then return false end
    local token={}
    page.active=true page.activation=token
    local function current() return page.active and page.activation==token and not page.disposed end
    page.unsubscribe=page.store:subscribe(function(value,changed)
        if current() then page:project(value,changed) end
    end)
    local release,reason=watch(function(snapshot)
        if not current() then return end
        if not page.owner:valid() then page.owner:close() return end
        receive(snapshot)
    end)
    if current() then
        page.release=release
        if not release then receive({state="ERROR",rows={},counts={},reason=reason}) end
    elseif release then release() end
    return true
end
function Lifecycle.unmount(page)
    page.active=false page.activation=nil
    local release,unsubscribe=page.release,page.unsubscribe
    page.release=nil page.unsubscribe=nil
    if unsubscribe then unsubscribe() end
    if release then release() end
    TooltipManager.clearOwner(page)
end
return Lifecycle
