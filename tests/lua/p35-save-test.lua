local R=require 'EmberRoutesProbe/SelfCareRecord'
local job=R.create('j','npc')
job.payload=assert(R.begin(job,'LEISURE'))
job.payload.settlementId='home'
job.payload.leisure={format=1,activity='SOCIAL',socialId='pair',hours=1,applied=true,finished=true}
job.payload.leisureMemory={last='SOCIAL',cooldowns={SOCIAL=3.5}}
assert(R.valid(job))
job.payload.step='IDLE'
local nextPayload=assert(R.begin(job,'REST'))
assert(nextPayload.leisureMemory.cooldowns.SOCIAL==3.5,'routine transition retains game-time cooldown')
job.payload.leisure.applying='bad' assert(not R.valid(job)) job.payload.leisure.applying=true
assert(R.valid(job),'in-flight intent is serializable for UNKNOWN reconciliation, not replay')
job.payload.leisureMemory.cooldowns.SOCIAL=0/0 assert(not R.valid(job),'corrupt saved cooldown rejected')
print('P3.5 save schema: retained cooldown, effect intent, corrupt memory rejected')
