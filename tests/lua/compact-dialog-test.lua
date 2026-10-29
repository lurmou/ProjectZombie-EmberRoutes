dofile('tests/lua/settlement-tabs-test.lua')
local n=0
for _,size in ipairs({{1280,720,28},{1280,720,32},{1920,1080,20},{3840,2160,32}}) do
 local dialog=ERSettlementPreview('publicOrder',size[3],size[1],size[2])
 assert(dialog.actionButton.y+dialog.actionButton.height<=dialog.height,'action remains inside dialog')
 assert(dialog.blueprintList.y+dialog.blueprintList.height<=dialog.height,'blueprint viewport remains inside dialog')
 n=n+2 dialog:close() dialog.owner:close()
end
print('PASS '..n..' compact dialog/font boundary checks; GPU not run')
