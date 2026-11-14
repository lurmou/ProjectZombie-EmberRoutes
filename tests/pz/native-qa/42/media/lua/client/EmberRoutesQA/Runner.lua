local Probe=require 'EmberRoutesProbe/Kernel/Boot'
local Ledger=require 'EmberRoutesProbe/Settlement/SettlementLedger'
local Membership=require 'EmberRoutesProbe/Settlement/MembershipService'
local Commands=require 'EmberRoutesProbe/Integration/NpcCommands'
local Driver=require 'EmberRoutesProbe/Runtime/Driver'
local Diagnostic=require 'EmberRoutesProbe/Runtime/TaskDiagnostic'
local Runtime=require 'EmberRoutesProbe/Runtime/TaskRuntime'
local Actions=require 'EmberRoutesProbe/Runtime/Actions'
local R={}
local function need(value,reason) if not value then error(reason) end return value end
local function distance(npc,p) return math.sqrt((npc:getX()-p.x)^2+(npc:getY()-p.y)^2) end

function R.new(command,session,report)
    local r={command=command,phase='PREPARE',evidence={cases={},requestSequence=command.seq},deadline=EmberRoutesQaJava.clockMs()+90000}
    local function phase(name)
        r.phase=name r.deadline=EmberRoutesQaJava.clockMs()+90000
        report('RUNNING',name,r.evidence)
    end
    local function terminal(state,reason)
        r.done=true r.state=state r.evidence.reason=reason or 'COMPLETE'
        report(state,r.phase,r.evidence)
    end
    local function points(actor)
        local room=need(actor:getCurrentSquare():getRoom(),'QA_INDOOR_ROOM_REQUIRED')
        local found={} local x,y=math.floor(actor:getX()),math.floor(actor:getY())
        for dx=-5,5 do for dy=-5,5 do
            local s=getCell():getGridSquare(x+dx,y+dy,0)
            if s and s:getRoom()==room and s:TreatAsSolidFloor() and not s:HasStairs() and s:isFree(false) then
                found[#found+1]={x=s:getX()+0.5,y=s:getY()+0.5,z=0,square=s}
            end
        end end
        need(#found>=2,'QA_ROOM_HAS_NO_FREE_ROUTE')
        local first=found[1] local target,best=nil,0
        for _,p in ipairs(found) do
            local d=(p.x-first.x)^2+(p.y-first.y)^2
            if d>best then target,best=p,d end
        end
        need(target and best>=4,'QA_ROOM_ROUTE_TOO_SHORT')
        return first,target
    end
    local function memberCommand(kind)
        local member=need(Membership.view(r.id),'QA_MEMBERSHIP_MISSING')
        return Membership.request(r.actor,r.id,{kind=kind,settlementId=kind=='SETTLE' and r.fixture.settlementId or nil,
            requestId=session.runId..':'..command.seq..':'..kind,expectedRevision=member.revision})
    end
    local function beginMove(target,cancel)
        local code,c=Diagnostic.submit(r.actor,'MOVE',{
            validate=function(binding) return binding.id==r.id end,
            start=function(context)
                context.startX=context.npc:getX() context.startY=context.npc:getY()
                local ok,result=context.body.move(r.actor,target) context.result=result
                return ok and type(result)=='string' and string.find(result,'^MOVE_REQUESTED')~=nil,result
            end,
            tick=function(context)
                local motion=EmberRoutesProbeJava.motionResult(context.npc)
                local moved=math.sqrt((context.npc:getX()-context.startX)^2+(context.npc:getY()-context.startY)^2)
                context.moved=moved
                if cancel and not context.cancelled and moved>=0.3 then
                    context.cancelled=true Diagnostic.cancel(context,'QA_CANCEL')
                elseif motion~='MOVING' then context.done=true context.result=motion end
            end,
            finished=function(context) return context.done==true end,
            pause=function() end,
            evidence=function() return {effects='KNOWN',ids={}} end})
        need(code=='QUEUED' and c,'QA_MOVE_REFUSED:'..tostring(code))
        r.context=c r.target=target r.cancelMove=cancel
    end
    function r:cancel(reason)
        if self.done then return end
        self.cancelReason=reason or 'USER_CANCEL'
        if self.context then Diagnostic.cancel(self.context,self.cancelReason) end
        if self.actor and self.command.caseId=='actions' then Actions.execute(self.actor,'cancel') end
        phase('CANCELLING')
        report('STOPPING','CANCELLING',self.evidence)
    end
    function r:step()
        if self.done then return end
        local now=EmberRoutesQaJava.clockMs()
        if now>self.deadline then
            if self.phase=='CANCELLING' then terminal('BLOCKED','STOP_TIMEOUT')
            else self.failure='QA_PHASE_TIMEOUT:'..self.phase self:cancel(self.failure) end
            return
        end
        if self.phase=='CANCELLING' then
            local runtime=Runtime.current()
            if (not self.context or not Diagnostic.active(self.context)) and runtime and (not self.id or not runtime:owns(self.id)) then
                terminal(self.failure and 'FAIL' or 'CANCELLED',self.failure or self.cancelReason)
            end
            return
        end
        if self.phase=='PREPARE' then
            if not Probe.runtimeReady or Probe.restorePending then return end
            self.actor=need(getSpecificPlayer(0),'QA_LOCAL_PLAYER_REQUIRED')
            need(not self.actor:isDead() and self.actor:isLocalPlayer(),'QA_LOCAL_PLAYER_INVALID')
            need(getWorld():getWorld()==session.saveName and getWorld():getGameMode()=='Sandbox','QA_WORLD_MISMATCH')
            need(math.abs(self.actor:getX()-10770)<32 and math.abs(self.actor:getY()-10271)<32,'QA_WORLD_POSITION_MISMATCH')
            self.start,self.destination=points(self.actor)
            local fixture=ModData.getOrCreate('EmberRoutes/NativeQA/v1')
            if fixture.format then need(fixture.format==1,'QA_FIXTURE_FORMAT_UNSUPPORTED')
            else for _ in pairs(fixture) do error('QA_FIXTURE_FORMAT_UNSUPPORTED') end fixture.format=1 end
            self.fixture=fixture
            if not fixture.settlementId then
                local entry,why=Ledger.commit(self.actor,nil,'Native QA',{x=10763,y=10264,w=15,h=15})
                need(entry,'QA_SETTLEMENT_CREATE_FAILED:'..tostring(why)) fixture.settlementId=entry.id
            end
            need(Ledger.get(fixture.settlementId),'QA_SETTLEMENT_LOST')
            if not fixture.npcId then
                local result=Commands.execute(self.actor,'spawn',self.start.square)
                need(type(result)=='string' and string.find(result,'^SPAWNED'),'QA_SPAWN_FAILED:'..tostring(result))
                fixture.npcId=need(EmberRoutesProbeJava.selectedId(),'QA_NPC_ID_MISSING')
            end
            self.id=fixture.npcId
            local binding=Driver.bindId(self.actor,self.id)
            if not binding then return end -- A saved carrier must be restored, never replaced.
            self.npc=binding.handle
            need(EmberRoutesProbeJava.selectCarrier(self.id),'QA_NPC_SELECT_FAILED')
            local member=need(Membership.view(self.id),'QA_MEMBERSHIP_MISSING')
            self.evidence.npcId=self.id self.evidence.settlementId=fixture.settlementId
            self.evidence.start={x=self.npc:getX(),y=self.npc:getY(),z=self.npc:getZ()}
            if member.settlementId~=fixture.settlementId then
                local receipt=memberCommand('SETTLE') need(receipt and receipt.state=='PENDING','QA_SETTLE_REFUSED')
                phase('SETTLING')
            else phase('WAIT_REQUEST') end
        elseif self.phase=='SETTLING' then
            local member=Membership.view(self.id)
            if member and member.settlementId==self.fixture.settlementId and not member.pending then phase('WAIT_REQUEST') end
        elseif self.phase=='WAIT_REQUEST' then
            local receipt=memberCommand('WAIT') need(receipt and receipt.state=='PENDING','QA_WAIT_REFUSED')
            phase('WAITING')
        elseif self.phase=='WAITING' then
            local member=Membership.view(self.id) local runtime=Runtime.current()
            if member and member.context=='WAIT' and not member.pending and runtime and not runtime:owns(self.id) then
                if self.command.caseId=='actions' then
                    need(Actions.execute(self.actor,'suite')=='QUEUED','QA_ACTIONS_REFUSED') phase('ACTIONS')
                else beginMove(self.destination,false) phase('MOVE') end
            end
        elseif self.phase=='MOVE' or self.phase=='CANCEL_MOVE' then
            local c=self.context
            if Diagnostic.active(c) then return end
            local state=c.runtime:inspect(c.handle)
            need(state and state.state=='CLOSED' and c.fact and c.fact.effects=='KNOWN','QA_MOVE_NOT_SETTLED')
            if self.phase=='MOVE' then
                need(distance(self.npc,self.destination)<=0.55 and self.npc:getZ()==0 and (c.moved or 0)>=0.5,'QA_MOVE_PHYSICAL_POSTCONDITION')
                self.evidence.cases.move={state='PASS',remaining=distance(self.npc,self.destination),moved=c.moved,result=c.result}
                beginMove(self.start,true) phase('CANCEL_MOVE')
            else
                need(c.cancelled==true and not self.npc:isMoving() and self.npc:getPath2()==nil,'QA_CANCEL_NOT_STOPPED')
                self.evidence.cases.cancel={state='PASS',moved=c.moved or 0,reason=state.reason or ''}
                terminal('PASS')
            end
        elseif self.phase=='ACTIONS' then
            if not Actions.batch or Actions.isBusy() or Runtime.current():owns(self.id) then return end
            need(#Actions.batch.records==10,'QA_ACTION_CASES_INCOMPLETE')
            for _,record in ipairs(Actions.batch.records) do
                self.evidence.cases[record.name]={state=record.state,detail=tostring(record.detail)}
                need(record.state=='PASSED','QA_ACTION_FAILED:'..record.name..':'..tostring(record.detail))
            end
            need(Actions.batch.state=='PASSED','QA_ACTION_BATCH_FAILED:'..tostring(Actions.batch.state))
            need(Actions.execute(self.actor,'cleanup')=='QUEUED','QA_ACTION_CLEANUP_REFUSED') phase('CLEANUP')
        elseif self.phase=='CLEANUP' then
            if Runtime.current():owns(self.id) then return end
            need(not Actions.cleanupBlocked and not Actions.fixtures,'QA_ACTION_CLEANUP_RETAINED')
            terminal('PASS')
        end
    end
    function r:failed(reason)
        self.failure=tostring(reason)
        self:cancel(self.failure)
    end
    return r
end
return R
