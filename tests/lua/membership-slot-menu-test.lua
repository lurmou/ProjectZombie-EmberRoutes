local ctx=dofile('tests/lua/membership-command-test.lua')
local S,actor=ctx.service,ctx.actor
local spoken
function actor:Say(text) spoken=text end
function getTextOrNull(key) return key end
function getText(key) return key end
package.loaded['EmberRoutesProbe/Settlement/SettlementLedger'].list=function() return {} end
package.loaded['EmberRoutesProbe/Warehouse/DisplayNames']={name=function(id) return id end}
local function menu()
    local m={options={},children={}}
    function m:addOption(name,target,callback)
        local option={name=name,target=target,callback=callback} self.options[#self.options+1]=option return option
    end
    function m:addSubMenu(option,child) self.children[option]=child end
    return m
end
ISContextMenu={getNew=menu}
local Menu=require 'EmberRoutesProbe/Integration/MembershipMenu'
local root=menu() Menu.fill(actor,root,nil,'a')
local slots=root.children[root.options[1]]
assert(slots and #slots.options==3,'FOLLOW exposes three explicit native menu slots')
assert(not slots.options[1].notAvailable and slots.options[2].notAvailable)
assert(slots.options[3].notAvailable,'active slot 2 is shown unavailable')
local chosen=slots.options[1]
chosen.callback(chosen.target)
local result=S.view('a').pending
assert(result and result.state=='PENDING' and result.followSlot==0,'click submits the chosen explicit slot')
S.cancel(actor,'a',result.requestId,S.view('a').revision)
slots.options[1].callback(actor)
assert(not S.view('a').pending and spoken:find('STALE_MEMBERSHIP'),'old menu revision cannot acquire a slot')
print('PASS slot menu choice, occupancy and stale snapshot checks; native context menu mocked')
