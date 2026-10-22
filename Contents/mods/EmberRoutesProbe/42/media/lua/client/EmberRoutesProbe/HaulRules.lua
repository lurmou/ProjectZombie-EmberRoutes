local Rules = {}

function Rules.endpoint(role, tagRole, expectedID, tagID, attached, sameContainer, loaded)
    if not expectedID or expectedID == "" or expectedID ~= tagID or role ~= tagRole then return false, "TAG_INVALID" end
    if not attached or not sameContainer or not loaded then return false, "CONTAINER_UNAVAILABLE" end
    return true, "VALID"
end

function Rules.near(x, y, z, tx, ty, tz)
    return x == x and y == y and z == z and tx == tx and ty == ty and tz == tz
        and math.abs(x - tx) <= 1.6 and math.abs(y - ty) <= 1.6 and math.abs(z - tz) < 0.2
end

function Rules.item(item, containers, destination, snapshot)
    local copies = 0
    for _, container in ipairs(containers) do
        if container:getItems():contains(item) then copies = copies + 1 end
    end
    local valid = copies == 1 and item:getContainer() == destination and destination:getItems():contains(item)
        and item:getID() == snapshot.id and item:getCondition() == snapshot.condition
        and item:getName() == snapshot.name
        and item:getModData().EmberRoutesHaulFixture == snapshot.token
    return valid, "itemID=" .. item:getID() .. " copies=" .. copies .. " condition=" .. item:getCondition()
end

return Rules
