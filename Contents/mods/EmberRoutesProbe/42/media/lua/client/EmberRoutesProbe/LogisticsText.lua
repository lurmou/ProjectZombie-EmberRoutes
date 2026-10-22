local Text={}
function Text.get(key)
    local code,detail=string.match(key,"^(%u[%u_]+)%s+(.*)$")
    if code then return Text.get(code).." "..detail end
    for _,prefix in ipairs({"IGUI_EmberRoutesProbe_Logistics_","IGUI_EmberRoutesProbe_WorkCode_","IGUI_EmberRoutesProbe_Settlement_"}) do
        local value=getTextOrNull(prefix..key)
        if value then return value end
    end
    return key
end
return Text
