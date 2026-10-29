local S=require 'EmberRoutesProbe/MembershipService'
local L={}
function L.newWorld()
    -- OnNewGame also fires on a replacement character. Do not bless old NPC checkpoints.
    if S.load() then return true end
    for _,key in ipairs({'EmberRoutes/NpcCheckpoints/v2','EmberRoutes/NpcCheckpoint/v1'}) do
        local data=ModData.getOrCreate(key)
        if data.record then return false,'MEMBERSHIP_NEW_WORLD_REQUIRED' end
        if data.snapshot then
            if type(data.snapshot)~='table' or type(data.snapshot.records)~='table' then return false,'MEMBERSHIP_FORMAT_INVALID' end
            for _ in pairs(data.snapshot.records) do return false,'MEMBERSHIP_NEW_WORLD_REQUIRED' end
        end
    end
    local ledger=require('EmberRoutesProbe/SettlementLedger').data()
    for _ in pairs(ledger.entries) do return false,'MEMBERSHIP_NEW_WORLD_REQUIRED' end
    return S.newWorld()
end
function L.install()
    local Probe=require 'EmberRoutesProbe/Boot'
    if Probe.membershipInstalled then return end
    require('EmberRoutesProbe/MembershipRuntime').install()
    Probe.prepareMembershipRecovery=function()
        local ok,why=S.load() if not ok then error(why) end return true
    end
    -- Engine-provided new-world boolean, unlike OnNewGame which includes respawn.
    Events.OnInitGlobalModData.Add(function(isNewGame)
        if isNewGame then
            -- Before bridge.begin, use the freshly loaded engine root rather than a previous world's cache.
            local ok,why=S.newWorld(ModData.getOrCreate('EmberRoutes/Work/v1'))
            if not ok then require('EmberRoutesProbe/Log').write('MEMBERSHIP',why) end
        end
    end)
    Events.OnNewGame.Add(function(player)
        local ok,why=S.load()
        if ok then
            S.character(player)
            if Probe.failureCode=='MEMBERSHIP_NEW_WORLD_REQUIRED' then Probe.begin() end
        else require('EmberRoutesProbe/Log').write('MEMBERSHIP',why) end
    end)
    if Events.OnCharacterDeath then Events.OnCharacterDeath.Add(function(character)
        if not character or not instanceof(character,'IsoPlayer') then return end
        -- carrierId intentionally rejects dead bodies. Use the guarded world-owned lifecycle identity.
        local id=EmberRoutesProbeJava and EmberRoutesProbeJava.ownedCarrierId and EmberRoutesProbeJava.ownedCarrierId(character)
        if id and id~='' and S.view(id) then
            local runtime=require('EmberRoutesProbe/TaskRuntime').current()
            if runtime then runtime:stop(id,'NPC_DIED') end
            S.retire(id,false)
        end
    end) end
    Probe.membershipInstalled=true
end
return L
