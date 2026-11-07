-- Register with the native options system; the chosen binding is saved by PZ.
require 'keyBinding'
local binding='EmberRoutesSquadWheel'
for _,row in ipairs(keyBinding) do if row.value==binding then return binding end end
table.insert(keyBinding,{value=binding,key=Keyboard.KEY_PERIOD})
return binding
