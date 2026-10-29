local S=require 'EmberRoutesProbe/MembershipService'

local Registry=require 'EmberRoutesProbe/ContainerRegistry'

local Ledger=require 'EmberRoutesProbe/SettlementLedger'

local T=require 'EmberRoutesProbe/MembershipText'

local Names=require 'EmberRoutesProbe/DisplayNames'

local Menu={}

function Menu.send(actor,id,kind,scope,expected)

    local row=S.view(id) if not row then actor:Say(T.reason('NO_MEMBERSHIP')) return end

    local receipt=S.request(actor,id,{kind=kind,settlementId=scope,expectedRevision=expected or row.revision,requestId=Registry.id()})

    actor:Say(T.reason(receipt.reason or receipt.state)) return receipt

end

function Menu.sleepOrder(actor,id)

    if not S.view(id) then actor:Say(T.reason('NO_MEMBERSHIP')) return end

    local Probe=require 'EmberRoutesProbe/Boot'

    if not Probe.forceCare then actor:Say(T.reason('SLEEP_UNAVAILABLE')) return end

    local ok=Probe.forceCare(id,'SLEEP')

    actor:Say(T.reason(ok and 'SLEEP_ORDERED' or 'SLEEP_UNAVAILABLE'))

end

function Menu.fill(actor,menu,square,id)

    id=id or require('EmberRoutesProbe/Driver').selected(actor)

    local row=S.view(id)

    if row then

        -- 高频指令优先：跟随/等待/返回/解除
        for _,kind in ipairs({'FOLLOW','WAIT','RETURN','UNASSIGN'}) do

            local command,revision=kind,row.revision

            menu:addOption(T.reason(command),actor,function(a) Menu.send(a,id,command,nil,revision) end)

        end

        if row.pending then

            local request,revision=row.pending.requestId,row.revision

            menu:addOption(T.reason('CANCEL'),actor,function(a)

                local r=S.cancel(a,id,request,revision) a:Say(T.reason(r.reason or r.state))

            end)

        end

        -- 低频：驻扎/迁移至据点
        for _,entry in ipairs(Ledger.list()) do

            if entry.factionId==row.factionId then

                local kind=row.settlementId and row.settlementId~=entry.id and 'TRANSFER' or 'SETTLE'

                local target,revision=entry.id,row.revision

                menu:addOption(T.reason(kind)..' - '..entry.name,actor,function(a) Menu.send(a,id,kind,target,revision) end)

            end

        end

    end

    if square then

        for _,entry in ipairs(Ledger.list()) do

            if require('EmberRoutesProbe/SettlementGeometry').inside(entry,square:getX(),square:getY()) then

                local target,revision=entry.id,entry.revision

                local point={x=square:getX()+0.5,y=square:getY()+0.5,z=square:getZ()}

                menu:addOption(T.reason('SET_RETURN_POINT')..' - '..entry.name,actor,function(a)

                    local ok,why=S.setReturnPoint(a,target,point,revision) a:Say(T.reason(ok and 'RETURN_POINT_SET' or why))

                end)

            end

        end

    end

end

-- Carriers within one square of the click. B42 does not deliver characters

-- through worldobjects and a sprite-edge click lands on an adjacent square.

local function carriersNear(square)

    local cell=getCell() if not cell then return {} end

    local found,seen={},{}

    for dx=-1,1 do for dy=-1,1 do

        local sq=cell:getGridSquare(square:getX()+dx,square:getY()+dy,square:getZ())

        local moving=sq and sq:getMovingObjects()

        if moving then

            for i=0,moving:size()-1 do

                local object=moving:get(i)

                if instanceof(object,'IsoPlayer') and not instanceof(object,'IsoZombie') and not object:isDead() then

                    local id=EmberRoutesProbeJava and EmberRoutesProbeJava.carrierId and EmberRoutesProbeJava.carrierId(object)

                    if id and id~='' and not seen[id] then seen[id]=true found[#found+1]={object=object,id=id} end

                end

            end

        end

    end end

    return found

end

function Menu.npcEntries(actor,context,worldobjects)

    local square

    for _,object in ipairs(worldobjects) do

        if object.getSquare then square=object:getSquare() end

        if square then break end

    end

    if not square then return end

    for index,carrier in ipairs(carriersNear(square)) do

        local row=S.view(carrier.id)

        local label=getText('IGUI_EmberRoutesProbe_Companion')..' · '..Names.name(carrier.id,carrier.object)

        if row and row.context then label=label..' ('..T.reason(row.context)..')' end

        local option=context:addOption(label,nil,nil)

        local menu=ISContextMenu:getNew(context)

        context:addSubMenu(option,menu)

        if row then

            Menu.fill(actor,menu,nil,carrier.id)

            menu:addOption(T.reason('SLEEP_ORDER'),actor,Menu.sleepOrder,carrier.id)

            if row.settlementId then

                menu:addOption(T.reason('viewDetails'),actor,function(a)

                    require('EmberRoutesProbe/SettlementDashboard').open(a,row.settlementId,'personnel')

                end)

            end

            if EmberRoutesProbeJava and EmberRoutesProbeJava.selectCarrier then

                menu:addOption(getText('IGUI_EmberRoutesProbe_SelectAsTarget'),actor,require('EmberRoutesProbe/NpcCommands').selectWorker,carrier.id)

            end

        else

            local hint=menu:addOption(T.reason('NO_MEMBERSHIP'),nil,nil)

            hint.notAvailable=true

        end

        if index>=4 then
            local hint=context:addOption(getText('IGUI_EmberRoutesProbe_Companion_moreHidden'),nil,nil)
            hint.notAvailable=true
            break
        end

    end

end

function Menu.batch(actor,menu,scope,workers)

    local ids={} for _,worker in ipairs(workers) do local row=S.view(worker.id) if row then ids[#ids+1]={id=worker.id,revision=row.revision} end end

    menu:addOption(T.reason('BATCH_SETTLE'),actor,function(a)

        for _,row in ipairs(ids) do Menu.send(a,row.id,'SETTLE',scope,row.revision) end

    end)

end

return Menu

