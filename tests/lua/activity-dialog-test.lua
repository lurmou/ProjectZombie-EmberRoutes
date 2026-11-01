-- Test forwarding shim contract for ActivityDialog backward compatibility.
local checks=0
local function check(v,m) assert(v,m) checks=checks+1 end

local actor={name='Player'}
local entry={id='home',name='Settlement'}
local targetPage={Type='EmberRoutesActivityPage'}

-- 1. Test Dialog.open with SettlementDashboard instance
local dashboard={
    activeTab=nil,
    pages={activities=targetPage},
    selectTab=function(self,tabId) self.activeTab=tabId end
}

local Dialog=require 'EmberRoutesProbe/UI/ActivityDialog'

check(Dialog.open(nil)==nil,'Dialog.open(nil) safely returns nil')

local res1=Dialog.open(dashboard)
check(dashboard.activeTab=='activities','Dialog.open(dashboard) selects activities tab')
check(res1==targetPage,'Dialog.open(dashboard) returns active activity page')

-- 2. Test Dialog.open with raw actor/entry owner
local openedWith={}
package.loaded['EmberRoutesProbe/SettlementDashboard']={
    open=function(act,id,tab)
        openedWith={act=act,id=id,tab=tab}
        return targetPage
    end
}

local res2=Dialog.open({actor=actor,entry=entry})
check(openedWith.act==actor and openedWith.id=='home' and openedWith.tab=='activities',
    'Dialog.open({actor,entry}) forwards to SettlementDashboard.open on activities tab')
check(res2==targetPage,'returns opened dashboard/page')

print('activity-dialog: '..checks..' PASS (forwarding shim verified)')
