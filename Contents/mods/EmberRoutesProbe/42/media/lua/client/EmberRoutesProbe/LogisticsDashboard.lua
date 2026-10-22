-- Retained entry point for existing menus; one shell owns both pages.
local Dashboard={}
function Dashboard.open(actor,id)
    return require("EmberRoutesProbe/SettlementDashboard").open(actor,id,"logistics")
end
return Dashboard
