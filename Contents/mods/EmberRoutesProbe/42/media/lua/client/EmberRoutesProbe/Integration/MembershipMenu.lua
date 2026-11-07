local S=require 'EmberRoutesProbe/Settlement/MembershipService'

local Registry=require 'EmberRoutesProbe/Warehouse/ContainerRegistry'

local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'

local T=require 'EmberRoutesProbe/Settlement/MembershipText'

local Names=require 'EmberRoutesProbe/Warehouse/DisplayNames'

local Menu={}

function Menu.send(actor,id,kind,scope,expected,followSlot)

    local row=S.view(id) if not row then actor:Say(T.reason('NO_MEMBERSHIP')) return end

    local receipt=S.request(actor,id,{kind=kind,settlementId=scope,expectedRevision=expected or row.revision,
        requestId=Registry.id(),followSlot=followSlot})

    actor:Say(T.reason(receipt.reason or receipt.state)) return receipt

end

function Menu.sleepOrder(actor,id)

    if not S.view(id) then actor:Say(T.reason('NO_MEMBERSHIP')) return end

    local Probe=require 'EmberRoutesProbe/Kernel/Boot'

    if not Probe.forceCare then actor:Say(T.reason('SLEEP_UNAVAILABLE')) return end

    local ok=Probe.forceCare(id,'SLEEP')

    actor:Say(T.reason(ok and 'SLEEP_ORDERED' or 'SLEEP_UNAVAILABLE'))

end

function Menu.fill(actor,menu,square,id)

    id=id or require('EmberRoutesProbe/Runtime/Driver').selected(actor)

    local row=S.view(id)

    if row then

        -- 高频指令优先：跟随/等待/返回/解除
        local follow=menu:addOption(T.reason('FOLLOW'),nil,nil)
        local slots=ISContextMenu:getNew(menu)
        menu:addSubMenu(follow,slots)
        for slot=0,2 do
            local rank,revision=slot,row.revision
            local available,why=S.canFollow(actor,id,rank)
            local label=T.reason('FOLLOW_SLOT_'..rank)
            if not available then label=label..' | '..T.reason(why) end
            local option=slots:addOption(label,actor,function(a) Menu.send(a,id,'FOLLOW',nil,revision,rank) end)
            option.notAvailable=not available
        end
        for _,kind in ipairs({'WAIT','RETURN','UNASSIGN'}) do

            local command,revision=kind,row.revision

            menu:addOption(T.reason(command),actor,function(a) Menu.send(a,id,command,nil,revision) end)

        end

        if row.squadLeaderId==S.character(actor) then
            local revision=row.revision
            menu:addOption(T.reason('DISMISS'),actor,function(a) Menu.send(a,id,'DISMISS',nil,revision) end)
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

            if require('EmberRoutesProbe/Settlement/SettlementGeometry').inside(entry,square:getX(),square:getY()) then

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

        local label=getText('IGUI_EmberRoutesProbe_Companion')..' | '..Names.name(carrier.id,carrier.object)

        if row and row.context then label=label..' ('..T.reason(row.context)..')' end

        local option=context:addOption(label,nil,nil)

        local menu=ISContextMenu:getNew(context)

        context:addSubMenu(option,menu)

        if row then

            Menu.fill(actor,menu,nil,carrier.id)

            menu:addOption(T.reason('SLEEP_ORDER'),actor,Menu.sleepOrder,carrier.id)

            if row.settlementId then

                menu:addOption(T.reason('viewDetails'),actor,function(a)

                    require('EmberRoutesProbe/UI/SettlementDashboard').open(a,row.settlementId,'personnel')

                end)

            end

            if EmberRoutesProbeJava and EmberRoutesProbeJava.selectCarrier then

                menu:addOption(getText('IGUI_EmberRoutesProbe_SelectAsTarget'),actor,require('EmberRoutesProbe/Integration/NpcCommands').selectWorker,carrier.id)

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

-- Detached per-NPC revision snapshot, matching the original BATCH_SETTLE loop.
function Menu.batchRequest(actor,scope,kind,rows)
    local results={}
    for _,row in ipairs(rows) do
        local current=S.view(row.id)
        local receipt
        if kind~='SETTLE' and (not current or current.retired or current.settlementId~=scope) then
            receipt={state='REJECTED',reason='SCOPE_MISMATCH'}
        else
            receipt=S.request(actor,row.id,{kind=kind,settlementId=kind=='SETTLE' and scope or nil,
                expectedRevision=row.revision,requestId=Registry.id()})
        end
        local status=Menu.commandStatus(row.id,kind,receipt)
        results[#results+1]={id=row.id,kind=kind,receipt=receipt,status=status.state,reason=status.reason}
        actor:Say(Names.name(row.id)..': '..T.reason(status.state)..(status.reason and ' | '..T.reason(status.reason) or ''))
    end
    return results
end
function Menu.commandStatus(id,kind,receipt)
    receipt=S.result(id,receipt.requestId) or receipt
    if receipt.state=='REJECTED' or receipt.state=='CANCELLED' then return {state='FAILED',reason=receipt.reason or receipt.state} end
    local row=S.view(id)
    if not row then return {state='FAILED',reason='NO_MEMBERSHIP'} end
    if row.pending and row.pending.requestId~=receipt.requestId then return {state='FAILED',reason='STALE_REQUEST'} end
    if not row.pending and row.lastCommand and row.lastCommand.requestId~=receipt.requestId then return {state='FAILED',reason='STALE_REQUEST'} end
    if row.pending then
        return {state=row.reason and row.reason~='COMMAND_PENDING' and 'BLOCKED' or 'ACCEPTED_PENDING',reason=row.reason~='COMMAND_PENDING' and row.reason or nil}
    end
    if row.reason then return {state='BLOCKED',reason=row.reason} end
    local committed=receipt.state=='COMMITTED' or row.lastCommand and row.lastCommand.requestId==receipt.requestId and row.lastCommand.kind==kind
    if committed and (kind=='RETURN' and row.context=='SETTLEMENT' or kind=='WAIT' and row.context=='WAIT'
        or kind=='SETTLE' and row.context=='SETTLEMENT') then return {state='COMPLETED'} end
    return {state='ACCEPTED_PENDING'}
end
function Menu.batch(actor,menu,scope,workers,guard,receive)
    local settlers={} for _,worker in ipairs(workers or {}) do local row=S.view(worker.id)
        if row then settlers[#settlers+1]={id=worker.id,revision=row.revision} end
    end
    for _,kind in ipairs({'SETTLE','RETURN','WAIT'}) do
        local rows={}
        if kind=='SETTLE' then rows=settlers else
            for _,id in ipairs(S.members(scope)) do local row=S.view(id)
                if row then rows[#rows+1]={id=id,revision=row.revision} end
            end
        end
        local command,snapshot=kind,rows
        menu:addOption(T.reason('BATCH_'..command),actor,function(a)
            if not guard or guard() then
                local results=Menu.batchRequest(a,scope,command,snapshot)
                if receive then receive(results) end
                return results
            end
        end)
    end
end
function Menu.batchLines(results)
    local lines={}
    for _,result in ipairs(results or {}) do
        local status=Menu.commandStatus(result.id,result.kind,result.receipt)
        lines[#lines+1]={text=Names.name(result.id)..': '..T.reason(status.state)..(status.reason and ' | '..T.reason(status.reason) or '')}
    end
    return lines
end
function Menu.posting(actor,menu,id,guard)
    local row=S.view(id) if not row or not row.settlementId then return end
    local function send(value)
        if guard and not guard() then return end
        actor:Say(T.reason(S.setPosting(actor,id,value,row.revision,row.postingRevision or 0)))
    end
    menu:addOption(T.reason('POSTING_CLEAR'),nil,function() send(nil) end)
    local zones=require('EmberRoutesProbe/Settlement/SettlementZones').list(row.settlementId) or {}
    for _,zone in ipairs(zones) do if zone.enabled then
        local option=menu:addOption(T.reason('POSTING')..' | '..zone.name,nil,nil)
        local choices=ISContextMenu:getNew(menu) menu:addSubMenu(option,choices)
        for _,category in ipairs(require('EmberRoutesProbe/Work/OrderQuery').categories()) do
            local value={zoneId=zone.id,category=category}
            choices:addOption(getText('IGUI_EmberRoutesProbe_Public_'..category),nil,function() send(value) end)
        end
    end end
end
return Menu
