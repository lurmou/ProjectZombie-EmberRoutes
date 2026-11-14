local Manifest=require 'EmberRoutesProbe/Hauling/HaulManifest'
local M={}
function M.valid(r)
    if r.state~='DONE' then return false end
    return r.format~=3 or (Manifest.valid(r) and #Manifest.claimItemIds(r)==0 and not r.activeAttempt)
end
return M
