-- Host microbenchmark only; excludes Exposer/game loop/GC frame spikes.
local Store=require 'EmberRoutesProbe/JobStore'
local rows={} for i=1,32 do rows[i]={itemId=i,custody='CARRIED',weight=0.5,source='crate-a',destination='crate-b'} end
local store=assert(Store.open({}))
assert(store:create({id='bench',npcId='npc',providerType='BENCH',scopeId='s',revision=1,
    state='PREPARING',effects='KNOWN',obligations={},payload={rows=rows}}))
for i=1,1000 do store:get('bench') end
local start=_ERTestNanos()
for i=1,10000 do store:get('bench') end
local elapsed=(_ERTestNanos()-start)/1000000
print('HOST COPY 32 rows x 10000: '..tostring(elapsed)..' ms; game NOT RUN')
