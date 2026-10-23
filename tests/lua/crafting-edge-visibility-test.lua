-- Checks draw submission at viewport edges; stencil rendering requires the game.
dofile('tests/lua/settlement-tabs-test.lua')
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
for _,height in ipairs({17,20,24}) do
    local shell=ERSettlementPreview('crafting',height)
    local list=shell.pages.crafting.views.recipes.draft.list
    list.width=485 list.height=120 list:setYScroll(0)
    local row={kind='chain_step',title='Recipe',sub='Output',stepBadge='1',surfaceBadge='Table',isLast=true}
    local visual=list.emberStyle.prepare(list,row)
    visual.icon={}
    local entry={item={value=row,visual=visual},height=visual.height}
    local texts,icons
    function list:drawText(label,x,y) texts[#texts+1]={label=label,y=y} end
    function list:drawTextureScaledAspect(texture,x,y,w,h) icons[#icons+1]={y=y,height=h} end
    local function draw(y,scroll)
        texts={} icons={} list:setYScroll(scroll or 0)
        list.emberStyle.draw(list,y,entry)
    end
    draw(0)
    local textY,iconY=texts[1].y,icons[1].y
    for _,scroll in ipairs({0,-13}) do
        draw(list.height-1-textY-scroll,scroll)
        check(#texts>0,'partially visible bottom text must reach native stencil')
        draw(-1-textY-scroll,scroll)
        check(#texts>0 and texts[1].y+scroll==-1,'partially visible top text must reach native stencil')
        draw(list.height-1-iconY-scroll,scroll)
        check(#icons==1,'partially visible bottom icon must reach native stencil')
        draw(-1-iconY-scroll,scroll)
        check(#icons==1,'partially visible top icon must reach native stencil')
    end
    draw(list.height)
    check(#texts==0 and #icons==0,'fully invisible row is skipped')
    shell:close()
end
print('PASS '..checks..' edge submission checks; game stencil rendering NOT RUN')
