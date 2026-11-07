dofile('tests/lua/multi-worker-test.lua')
local Store=require 'EmberRoutesProbe/Work/LaborStore'
local old=Store.record
local record={controlUncertain=true,state='PAUSED'}
Store.record=function() return record end
local worker=require('EmberRoutesProbe/Work/WorkAgent').new('uncertain-fixture')
assert(worker.resume({})=='RECONCILE_REQUIRED','unknown stop effects must not relaunch or acquire a body')
Store.record=old
print('PASS unknown transfer stop blocks resume; native bodies NOT RUN')
