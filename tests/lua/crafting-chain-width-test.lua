-- Reuse the actual draft and Kahlua layout host; no game renderer is exercised.
dofile('tests/lua/settlement-tabs-test.lua')
local checks=0
local function check(value,message) checks=checks+1 assert(value,message) end
for _,height in ipairs({17,20,24}) do
    local shell=ERSettlementPreview('crafting',height)
    local list=shell.pages.crafting.views.recipes.draft.list
    for _,title in ipairs({'A long recipe name with several words that needs available space',
        '一个包含许多文字而且需要正确省略的非常长的配方名称'}) do
        local row={kind='chain_step',title=title,sub='Planned output x 12345678901234567890',
            stepBadge='Step 123 - prerequisite',surfaceBadge='A long workstation name',isLast=true}
        list.width=485
        local visual=list.emberStyle.prepare(list,row)
        local entry={item={value=row,visual=visual},height=visual.height}
        for _,width in ipairs({485,260,160,485}) do
            -- Keep the entry, as CachedList does: width changes must invalidate layout.
            list.width=width list:setYScroll(0)
            local labels={}
            function list:drawText(label,x,y)
                local measured=getTextManager():MeasureStringX(UIFont.Small,label)
                check(x>=0 and x+measured<=self.width,'chain text exceeds horizontal viewport')
                labels[#labels+1]={x=x,y=y,width=measured}
            end
            list.emberStyle.draw(list,0,entry)
            check(#labels>0,'narrow rows retain readable content')
            for i,a in ipairs(labels) do
                for j,b in ipairs(labels) do
                    if i<j and a.y==b.y then
                        check(a.x+a.width<=b.x or b.x+b.width<=a.x,'chain captions overlap')
                    end
                end
            end
        end
    end
    shell:close()
end
print('PASS '..checks..' chain caption bounds/overlap/resize checks; Kahlua layout host, game renderer NOT RUN')
