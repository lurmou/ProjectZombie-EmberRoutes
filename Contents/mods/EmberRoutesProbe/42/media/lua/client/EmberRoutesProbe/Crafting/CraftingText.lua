local Text={}
function Text.get(key) return getText("IGUI_EmberRoutesProbe_Crafting_"..key) end
function Text.reason(key)
    if not key or key=="" then return "" end
    return getTextOrNull("IGUI_EmberRoutesProbe_Crafting_"..key) or Text.get("otherReason")
end
return Text
