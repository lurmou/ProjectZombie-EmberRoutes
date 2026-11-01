-- A watch may notify synchronously and close its window before a
-- release handle is returned.
--
-- Activation tokens reject notifications from previous activations.
-- Tooltip dismissal is part of activation teardown.
--
-- IMPORTANT:
-- unmount is NOT permanent page destruction.
-- Page instances remain cached in SettlementDashboard.pages.
-- Therefore unmount must dismiss tooltips, not unregister them.

local Lifecycle = {}
local TooltipManager = require 'EmberRoutesProbe/UI/TooltipManager'

function Lifecycle.mount(page, watch, receive)
    if page.active or page.disposed then return false end
    local token = {}
    page.active = true page.activation = token
    local function current()
        return page.active and page.activation == token and not page.disposed
    end
    page.unsubscribe = page.store:subscribe(function(value, changed)
        if current() then page:project(value, changed) end
    end)
    local release, reason = watch(function(snapshot)
        if not current() then return end
        if not page.owner:valid() then page.owner:close() return end
        receive(snapshot)
    end)
    if current() then
        page.release = release
        if not release then
            receive({ state = "ERROR", rows = {}, counts = {}, reason = reason })
        end
    elseif release then
        release()
    end
    return true
end

function Lifecycle.unmount(page)
    if not page then return end
    -- Invalidate first. Any synchronous/reentrant callback is rejected.
    page.active = false page.activation = nil
    local release = page.release
    local unsubscribe = page.unsubscribe
    page.release = nil page.unsubscribe = nil
    if unsubscribe then unsubscribe() end
    if release then release() end
    -- Temporary dismissal only.
    -- Permanent unregister belongs to page instance destruction.
    TooltipManager.dismissOwner(page)
end

return Lifecycle
