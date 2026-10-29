-- Exercise the native-return-table branch with the complete real Lua index.
-- Physical objects are the existing host fixtures, not real Java inventories.
local Read=require 'EmberRoutesProbe/InventoryRead'
local calls=0 local maxSlice=0
local bridge={}
bridge.inventoryReadSlice=function(container,items,size,offset,limit)
    calls=calls+1 maxSlice=math.max(maxSlice,limit)
    local previous=EmberRoutesProbeJava EmberRoutesProbeJava=nil
    local rows,reason=Read.slice(container,items,size,offset,limit)
    EmberRoutesProbeJava=previous
    return {rows=rows,reason=reason}
end
EmberRoutesProbeJava=bridge
dofile('tests/lua/settlement-storage-test.lua')
assert(calls>0 and maxSlice<=32,'real warehouse uses bounded native-return-table branch')
print('PASS native warehouse branch; slices='..calls..' maxItems='..maxSlice..'; Java host mocked')
