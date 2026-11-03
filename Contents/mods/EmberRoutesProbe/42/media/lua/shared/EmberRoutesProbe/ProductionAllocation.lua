-- Production-only ItemID manifest. Counts are transfer facts, never inventory.
local Validate=require 'EmberRoutesProbe/Validate'
local A={}
function A.row(r,asset)
    r.outputAllocation=r.outputAllocation or {format=1,assets={}}
    for _,row in ipairs(r.outputAllocation.assets) do if row.id==asset.id then return row end end
    local row={id=asset.id,fullType=asset.fullType,actual=1,allocated=0,transferred=0,remaining=1,state='UNALLOCATED',targets={}}
    r.outputAllocation.assets[#r.outputAllocation.assets+1]=row
    return row
end
function A.assign(row,destination)
    if row.transferred==1 or row.allocated==1 then return false end
    row.targets={{destinationId=destination,quantity=1,transferred=0}}
    row.allocated=1 row.state='ALLOCATED'
    return true
end
function A.settle(row,destination)
    local target=row.targets[1]
    if not target or target.destinationId~=destination or row.allocated~=1 then return false end
    if row.transferred==1 then return false end
    target.transferred=1 row.transferred=1 row.remaining=0 row.state='SETTLED'
    return true
end
function A.count(r,product)
    local allocated,settled=0,0
    for _,row in ipairs(r.outputAllocation and r.outputAllocation.assets or {}) do
        if row.fullType==product then allocated=allocated+row.allocated settled=settled+row.transferred end
    end
    return allocated,settled,math.max(0,r.target-settled)
end
function A.valid(manifest)
    if manifest==nil then return true end
    if type(manifest)~='table' or manifest.format~=1 or type(manifest.assets)~='table' or #manifest.assets>1283840 then return false end
    local seen,count={},0
    for key,row in pairs(manifest.assets) do
        if type(key)~='number' or key~=math.floor(key) or key<1 or key>#manifest.assets or type(row)~='table'
            or not Validate.itemId(row.id) or seen[row.id] or type(row.fullType)~='string'
            or row.actual~=1 or (row.allocated~=0 and row.allocated~=1) or (row.transferred~=0 and row.transferred~=1)
            or row.transferred>row.allocated or row.remaining~=1-row.transferred or type(row.targets)~='table'
            or #row.targets~=row.allocated then return false end
        if row.state~=(row.transferred==1 and 'SETTLED' or row.allocated==1 and 'ALLOCATED' or 'UNALLOCATED') then return false end
        local targetCount=0
        for key in pairs(row.targets) do
            if key~=1 then return false end
            targetCount=targetCount+1
        end
        if targetCount~=row.allocated then return false end
        local target=row.targets[1]
        if target and (type(target)~='table' or type(target.destinationId)~='string' or target.quantity~=1
            or target.transferred~=row.transferred) then return false end
        seen[row.id]=true count=count+1
    end
    return count==#manifest.assets
end
function A.matches(r)
    if not A.valid(r.outputAllocation) then return false end
    if not r.outputAllocation then return true end
    local byId={}
    for _,row in ipairs(r.outputAllocation.assets) do byId[row.id]=row end
    for _,asset in ipairs(r.outputs or {}) do
        local row=byId[asset.id]
        if not row or row.fullType~=asset.fullType or (row.transferred==1)~=(asset.delivered==true)
            or row.allocated==1 and asset.destination~=row.targets[1].destinationId then return false end
    end
    local _,settled=A.count(r,r.product)
    return settled==r.delivered
end
return A
