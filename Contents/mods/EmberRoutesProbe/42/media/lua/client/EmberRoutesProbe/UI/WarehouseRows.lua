-- Presentation only. Pending quantities are unknown, never usable inventory.
local Rows={}
local PinyinHelper=require "EmberRoutesProbe/PinyinHelper"
local sourceFields={"id","count","x","y","z","kind","displayType","customName","pending"}
local function sameSources(a,b)
    if #a~=#b then return false end
    for i,value in ipairs(a) do
        if value~=b[i] then
            for _,key in ipairs(sourceFields) do if value[key]~=b[i][key] then return false end end
        end
    end
    return true
end
local function row(old,count,sources,pending)
    if old.count==count and old.pending==pending and sameSources(old.sources,sources) then return old end
    return {fullType=old.fullType,node=old.node,label=old.label,searchKey=old.searchKey,
        count=count,sources=sources,pending=pending,pinned=old.pinned}
end
function Rows.project(snapshot,oldRows,resolveName)
    if snapshot.state=="UPDATING" then
        if not snapshot.retain then return {} end
        local result={}
        for _,old in ipairs(oldRows) do
            local sources,pending={},false
            for _,source in ipairs(old.sources) do
                if source.pending or snapshot.dirtyAll or (snapshot.dirtySources and snapshot.dirtySources[source.id]) then
                    local copy={}
                    for key,value in pairs(source) do copy[key]=value end
                    copy.count=false copy.pending=true sources[#sources+1]=copy pending=true
                else sources[#sources+1]=source end
            end
            local count=old.count
            if pending then count=false end
            result[#result+1]=row(old,count,sources,pending or nil)
        end
        return result
    end
    if snapshot.state~="READY" then return {} end
    local byType,result={},{}
    for _,old in ipairs(oldRows) do byType[old.fullType]=old end
    for _,value in ipairs(snapshot.rows) do
        local old=byType[value.fullType]
        if old and old.node==value.node then
            result[#result+1]=row(old,value.count,value.sources,nil)
        else
            local label=resolveName(value.fullType)
            local inits=PinyinHelper and PinyinHelper.getInitials and table.concat(PinyinHelper.getInitials(label)," ") or ""
            local searchKey=string.lower(label.." "..value.fullType..(inits~="" and (" "..inits) or ""))
            result[#result+1]={fullType=value.fullType,node=value.node,label=label,
                searchKey=searchKey,count=value.count,sources=value.sources,
                pinned=old and old.pinned or false}
        end
    end
    return result
end
return Rows
