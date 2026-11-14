local f=dofile('tests/lua/tool-custody-ledger-test.lua')
local native=EmberRoutesProbeJava.laborCustody
EmberRoutesProbeJava.laborCustody=function(...)
    native(...)
    error('injected after publication')
end
local created=f.Custody.claim('npc',44,'TOOL','source')
assert(not created,'a thrown bridge must not be reported as success')
local retained
for _,r in pairs(f.root.obligations.byId) do if r.type=='TOOL_CUSTODY' and r.data.itemId==44 then retained=r end end
assert(retained and retained.state=='ACTIVE' and f.state.claims.owners['item:44'],
    'ambiguous publication keeps both obligation and claim')
assert(require('EmberRoutesProbe/Kernel/CommitFence').status(),'ambiguous write fences later work')
assert(not f.Custody.claim('npc',45,'TOOL','source'),'fenced world rejects another custody commit')
print('PASS custody post-publication fault retains responsibility and fences; disk NOT RUN')
