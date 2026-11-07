from pathlib import Path

path = Path("Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/StorageFilterPanel.lua")
content = path.read_text(encoding="utf-8")

target = """    Log.write("STORAGE_FILTER","APPLY "..result
        .." id="..tostring(tag and tag.id or "unknown")
        .." role="..tostring(tag and tag.logisticsRole or self.store.value.role or "?")
        ..(square and " at="..square:getX()..","..square:getY()..","..square:getZ() or ""))"""

replacement = """    local groupsList = {}
    for g, v in pairs(self.model and self.model.draft and self.model.draft.groups or {}) do
        if v then groupsList[#groupsList + 1] = g end
    end
    Log.write("STORAGE_FILTER","APPLY "..result
        .." id="..tostring(tag and tag.id or "unknown")
        .." role="..tostring(tag and tag.logisticsRole or self.store.value.role or "?")
        .." contType="..tostring(self.container and self.container:getType() or "nil")
        .." groups="..table.concat(groupsList, ",")
        ..(square and " at="..square:getX()..","..square:getY()..","..square:getZ() or ""))"""

assert target in content, "target not found"
content = content.replace(target, replacement, 1)
path.write_text(content, encoding="utf-8")
print("StorageFilterPanel.lua patched")
