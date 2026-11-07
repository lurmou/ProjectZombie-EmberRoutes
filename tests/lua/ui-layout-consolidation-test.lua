-- Navigation/layout contract, using the same native-host fixture as the existing UI suite.
ERMonitorPreviewOnly=true
dofile('tests/lua/settlement-tabs-test.lua')
local n=0
local function check(v,m) assert(v,m) n=n+1 end
local f=ERSettlementPreview('warehouse',20,960,640)
local actor=f.actor f:close()
local Public=package.loaded['EmberRoutesProbe/Work/PublicWork']
Public.categories=function() return {'crafting','hauling','cooking','cleaning','farming','lumberjack','foraging','toolReturn'} end
local D=require 'EmberRoutesProbe/UI/SettlementDashboard'
for _,height in ipairs({16,20,26}) do
 local fixture=ERSettlementPreview('personnel',height,960,640)
 local page=fixture.pages.personnel
 check(#page.priorityHeaders==8,'all work categories have headers')
 for i,b in ipairs(page.priorityHeaders) do
  check(b.x>=page.matrixBounds.x and b.x+b.width<=page.matrixBounds.x+page.matrixList.width,'header '..i..' is visible')
 end
 check(page.info.list.height>height*3,'work details retain usable viewport')
 check(page.avatarCard==nil and page.avatar3D==nil,'no redundant portrait owner on the work matrix')
 page:toggleDossierDrawer()
 check(page.dossierDrawer and page.dossierDrawer.overview.list.visible,'health overview remains accessible in dossier')
 fixture:selectTab('crafting')
 check(not fixture.footerText or fixture.footerText=='','personnel footer never leaks into crafting')
 check(fixture.pages.crafting.y<=page.y,'warehouse flow reclaims single-page navigation row')
 fixture:onKeyPress(Keyboard.KEY_ESCAPE)
 check(fixture.activeTab=='warehouse','escape returns from crafting without closing dashboard')
 check(not fixture.pages.personnel.active,'hidden personnel watch inactive')
 fixture:close()
 check(not page.dossierDrawerOpen,'closing shell closes owned dossier')
end
print('ui-layout-consolidation: '..n..' PASS; native rendering and mouse dispatch unverified')
