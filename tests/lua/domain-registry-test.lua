local Registry=require 'EmberRoutesProbe/Kernel/DomainRegistry'
local function contract() return {schemaVersion=1,errorCodes={}} end
local function rejects(f) assert(not pcall(f)) end
rejects(function() Registry.register('invalid',contract(),{providers={{order=1,category='x',module='wrong'}}}) end)
Registry.register('invalid',contract(),{providers={{order=1,category='x',module='EmberRoutesProbe/X/Provider'}}})
rejects(function() Registry.register('invalid',contract(),{}) end)
rejects(function() Registry.register('second',contract(),{providers={{order=2,category='x',module='EmberRoutesProbe/Y/Provider'}}}) end)
rejects(function() Registry.register('second',contract(),{providers={{order=1,category='y',module='EmberRoutesProbe/Y/Provider'}}}) end)
rejects(function() Registry.register('second',contract(),{providers={[2]={order=2,category='y',module='EmberRoutesProbe/Y/Provider'}}}) end)
Registry.register('second',contract(),{providers={{order=2,category='y',module='EmberRoutesProbe/Y/Provider'}},retirement='EmberRoutesProbe/Y/Retirement'})
local result=Registry.providerEntries()
assert(#result==2 and result[1].category=='x' and result[2].providerType=='second')
result[1].module='changed'
assert(Registry.providerEntries()[1].module=='EmberRoutesProbe/X/Provider')
assert(Registry.retirementModule('second')=='EmberRoutesProbe/Y/Retirement')
Registry.seal()
rejects(function() Registry.register('late',contract(),{}) end)
print('PASS domain registration validation and detached metadata; game NOT RUN')
