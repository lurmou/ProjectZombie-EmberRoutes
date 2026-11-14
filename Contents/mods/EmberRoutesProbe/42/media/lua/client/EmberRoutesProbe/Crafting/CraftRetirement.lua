-- Domain evidence only; shared lifecycle and cross-domain checks remain in BusinessJobs.
local M={}
function M.valid(r)
    if not r.released or (r.state~='DONE' and r.state~='CANCELLED') then return false end
    return not (r.state=='DONE' and r.format==4 and (r.delivered~=r.produced
        or r.produced<r.target and r.reason~='TARGET_REACHED'))
end
return M
