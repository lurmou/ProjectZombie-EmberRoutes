local S={}
local bridge=EmberRoutesQaJava
local session,runner,pending,menu
local state,phase,sequence='MENU_READY','READY',0
local nextPoll=0
local function report(nextState,nextPhase,evidence)
    state,phase=nextState,nextPhase
    bridge.report(state,phase,sequence,evidence or {})
end
local function closeMenu() if menu then menu:dispose() menu=nil end end
local function launch(command)
    if runner and not runner.done or pending then return false,'BUSY' end
    sequence=command.seq pending=command
    closeMenu()
    report('LOADING','LOAD_FIXED_WORLD')
    if checkSaveFileExists('Sandbox/'..session.saveName) then
        MainScreen.continueLatestSave('Sandbox',session.saveName)
    else
        local screen=MainScreen.instance
        screen:setDefaultSandboxVars()
        SandboxVars.Zombies=6
        SandboxVars.ZombieConfig.PopulationMultiplier=0
        SandboxVars.EmberRoutes.CarrierProbe=true
        getSandboxOptions():updateFromLua()
        getWorld():setGameMode('Sandbox') getWorld():setWorld(session.saveName) getWorld():setMap('Muldraugh, KY')
        local desc=SurvivorFactory.CreateSurvivor()
        desc:setForename('QA') desc:setSurname('Observer')
        getWorld():setLuaPlayerDesc(desc)
        getWorld():setLuaPosX(10770) getWorld():setLuaPosY(10271) getWorld():setLuaPosZ(0)
        createWorld(session.saveName)
        GameWindow.doRenderEvent(false)
        forceChangeState(LoadingQueueState.new())
    end
    return true
end
function S.start()
    local command=bridge.menuRun()
    local ok,why=pcall(launch,command)
    if not ok then pending=nil report('FAIL','WORLD_START_FAILED',{reason=tostring(why)}) return false end
    return why==true
end
function S.onMenu()
    if not bridge then return end
    session=bridge.session() runner=nil pending=nil sequence=0
    closeMenu()
    menu=require('EmberRoutesProbe/UI/QaLaunchButton').new(MainScreen.instance,S.start)
    report('MENU_READY','QA_MENU_READY')
    if session.autoStart then
        local command=bridge.poll()
        if command and command.op=='run' then
            local ok,why=pcall(launch,command)
            if not ok then pending=nil report('FAIL','WORLD_START_FAILED',{reason=tostring(why)}) end
        end
    end
end
function S.onGameStart()
    if not bridge then return end
    closeMenu()
    if not pending then report('BLOCKED','UNREQUESTED_WORLD') return end
    if getWorld():getWorld()~=session.saveName then report('BLOCKED','WORLD_IDENTITY_MISMATCH') return end
    local command=pending pending=nil
    runner=require('EmberRoutesQA/Runner').new(command,session,report)
    report('PREPARING','GAME_READY')
end
function S.tick()
    if not bridge or not session or not getSpecificPlayer(0) then return end
    local now=bridge.clockMs()
    if now<nextPoll then return end nextPoll=now+250
    if runner and not runner.done then
        local ok,why=pcall(runner.step,runner)
        if not ok then runner:failed(why) end
    end
    local command=bridge.poll()
    if not command then return end
    if command.op=='run' then
        if runner and not runner.done then bridge.reject('QA_BUSY') return end
        sequence=command.seq
        runner=require('EmberRoutesQA/Runner').new(command,session,report)
        report('PREPARING','WARM_RUN')
    elseif command.op=='cancel' then
        if runner and not runner.done then sequence=command.seq runner:cancel('EXTERNAL_CANCEL')
        else bridge.reject('QA_NOT_RUNNING') end
    elseif command.op=='status' then
        report(state,phase,runner and runner.evidence or {})
    elseif command.op=='quit' then
        if runner and not runner.done then bridge.reject('QA_BUSY_CANCEL_FIRST') return end
        MainScreen.instance:quitToDesktop()
    end
end
function S.resize() if menu then menu:relayout() end end
return S
