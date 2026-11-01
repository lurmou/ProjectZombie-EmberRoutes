-- Backward compatibility forwarding shim for EmberRoutes Activity management.
-- The legacy 519-line ActivityDialog has been retired in favor of SettlementDashboard's 'activities' tab (ActivityPage).
-- Any external call to ActivityDialog.open forwards seamlessly to SettlementDashboard.

local Dialog = {}

---@param owner table
function Dialog.open(owner)
    if not owner then return nil end
    if owner.selectTab then
        owner:selectTab('activities')
        return owner.pages and owner.pages['activities']
    end
    if owner.actor and owner.entry then
        local Dashboard = require 'EmberRoutesProbe/SettlementDashboard'
        return Dashboard.open(owner.actor, owner.entry.id, 'activities')
    end
    return nil
end

return Dialog
