--[[
    EmberRoutes NPC 即时诊疗系统 (NpcMedical)
    方案 B：即时诊疗面板 (Instant Medical Panel)
    - 点击即时走近并打开 NPC 的原生健康面板 (ISHealthPanel)
    - 废除原版 MP Consent Handshake 握手弹窗
    - 守卫 NPC 相对距离 (<= 2 格，对齐原版交易 UI ISTradingUI.lua:417-419 的 2 格判定)，放宽原版绝对坐标微步强退判定
    - 修正 DidPatientMove 浮点严格相等崩溃，保障包扎/缝合/消毒 TimedAction 顺利执行
]]

require "TimedActions/ISBaseTimedAction"
local Names = require "EmberRoutesProbe/Warehouse/DisplayNames"

local NpcMedical = {}
NpcMedical.activePanels = {}
NpcMedical.installed = false

-- 检查实体是否为受管 NPC
function NpcMedical.isTargetNpc(character)
    if not character or not instanceof(character, "IsoPlayer") then return false end
    if EmberRoutesProbeJava and EmberRoutesProbeJava.carrierId then
        local id = EmberRoutesProbeJava.carrierId(character)
        if id and id ~= "" then return true, id end
    end
    return false
end

-- 寻路并秒开面板的 TimedAction
local ISOpenNpcMedicalAction = ISBaseTimedAction:derive("ISOpenNpcMedicalAction")

function ISOpenNpcMedicalAction:isValid()
    if not self.character or self.character:isDead() then return false end
    if not self.targetNpc or self.targetNpc:isDead() then return false end
    local distSq = IsoUtils.DistanceToSquared(self.character:getX(), self.character:getY(), self.targetNpc:getX(), self.targetNpc:getY())
    return distSq <= 9.0 -- 3.0 格容差
end

function ISOpenNpcMedicalAction:waitToStart()
    self.character:faceThisObject(self.targetNpc)
    return self.character:shouldBeTurning()
end

function ISOpenNpcMedicalAction:update()
    self.character:faceThisObject(self.targetNpc)
    self:forceComplete()
end

function ISOpenNpcMedicalAction:perform()
    NpcMedical.displayHealthPanel(self.character, self.targetNpc)
    ISBaseTimedAction.perform(self)
end

function ISOpenNpcMedicalAction:new(doctor, npc)
    local o = ISBaseTimedAction.new(self, doctor)
    o.targetNpc = npc
    o.maxTime = 0
    o.stopOnWalk = false
    o.stopOnRun = true
    return o
end

-- 玩家点击“医疗检查”入口
function NpcMedical.open(doctor, npc)
    if not doctor or not npc or doctor:isDead() or npc:isDead() then return end

    local distSq = IsoUtils.DistanceToSquared(doctor:getX(), doctor:getY(), npc:getX(), npc:getY())
    local sameFloor = doctor:getZ() == npc:getZ()

    -- 若已有该 NPC 的面板且正处于展示状态，置顶并视情况引导走近
    local existing = NpcMedical.activePanels[npc]
    if existing and existing:getIsVisible() then
        existing:bringToTop()
        if distSq > 4.0 or not sameFloor then
            local square = npc:getCurrentSquare()
            if square then luautils.walkAdj(doctor, square) end
        end
        return
    end

    if distSq <= 4.0 and sameFloor then -- 2 格且同层：立即开窗（对齐原版交易 UI 的 2 格判定）
        NpcMedical.displayHealthPanel(doctor, npc)
    else
        -- 2 格外或跨层：自动寻路走近，到达身边后自动秒开
        local square = npc:getCurrentSquare()
        if square and luautils.walkAdj(doctor, square) then
            -- callback-first: character is the player doctor, not a managed NPC; no TaskController ticket/body exists for a player-initiated walk.
            ISTimedActionQueue.add(ISOpenNpcMedicalAction:new(doctor, npc))
        end
    end
end

-- 实例化并弹出原生 ISHealthPanel
function NpcMedical.displayHealthPanel(doctor, npc)
    if not doctor or not npc or doctor:isDead() or npc:isDead() then return end
    doctor:faceThisObject(npc)

    -- 若已有该 NPC 的面板，先关闭旧面板
    local existing = NpcMedical.activePanels[npc]
    if existing then
        existing:removeFromUIManager()
        NpcMedical.activePanels[npc] = nil
    end

    local playerNum = doctor:getPlayerNum()
    local x = getPlayerScreenLeft(playerNum) + 70
    local y = getPlayerScreenTop(playerNum) + 50

    local healthPanel = ISHealthPanel:new(npc, x, y, 400, 400)
    healthPanel:initialise()

    local isNpc, npcId = NpcMedical.isTargetNpc(npc)
    local name = (isNpc and Names.name(npcId, npc)) or (npc.getFullName and npc:getFullName()) or "NPC"
    local title = getText("IGUI_health_playerHealth", name)
    local wrap = healthPanel:wrapInCollapsableWindow(title, false)
    wrap:addToUIManager()

    -- 建立病人 (character) 与医生 (otherPlayer) 角色
    healthPanel.character = npc
    healthPanel.otherPlayer = doctor
    healthPanel.doctorLevel = doctor:getPerkLevel(Perks.Doctor)
    healthPanel:setOtherPlayer(doctor)
    healthPanel.isNpcMedicalPanel = true

    if ISMedicalCheckAction and ISMedicalCheckAction.HealthWindows then
        ISMedicalCheckAction.HealthWindows[npc] = wrap
    end

    wrap.targetNpc = npc
    wrap.doctor = doctor
    local orig_close = wrap.close
    wrap.close = function(self)
        if NpcMedical.activePanels[npc] == self then
            NpcMedical.activePanels[npc] = nil
        end
        self:removeFromUIManager()
        return orig_close(self)
    end
    NpcMedical.activePanels[npc] = wrap
end

-- 检索点击地块附近的受管 NPC 列表
local function findNearbyNpcs(square, worldobjects)
    local carriers, seen = {}, {}
    if not square then return carriers end

    -- 1. 优先从 worldobjects 中检索
    if worldobjects then
        for _, obj in ipairs(worldobjects) do
            local isNpc, id = NpcMedical.isTargetNpc(obj)
            if isNpc and not obj:isDead() and not seen[id] then
                seen[id] = true
                carriers[#carriers + 1] = { id = id, object = obj }
            end
        end
    end

    -- 2. 若直选无结果，九宫格范围检索
    if #carriers == 0 then
        local cell = getCell()
        if cell then
            for dx = -1, 1 do
                for dy = -1, 1 do
                    local sq = cell:getGridSquare(square:getX() + dx, square:getY() + dy, square:getZ())
                    local moving = sq and sq:getMovingObjects()
                    if moving then
                        for i = 0, moving:size() - 1 do
                            local obj = moving:get(i)
                            local isNpc, id = NpcMedical.isTargetNpc(obj)
                            if isNpc and not obj:isDead() and not seen[id] then
                                seen[id] = true
                                carriers[#carriers + 1] = { id = id, object = obj }
                            end
                        end
                    end
                end
            end
        end
    end
    return carriers
end

-- 上下文菜单挂接
function NpcMedical.onFillWorldObjectContextMenu(playerIndex, context, worldobjects, test)
    if test then return end
    local doctor = getSpecificPlayer(playerIndex)
    if not doctor or doctor:isDead() then return end

    local square = nil
    if worldobjects then
        for _, obj in ipairs(worldobjects) do
            if obj.getSquare then square = obj:getSquare() end
            if square then break end
        end
    end
    if not square then return end

    local npcs = findNearbyNpcs(square, worldobjects)
    if #npcs == 0 then return end

    -- 拦截并清理原版针对 IsoPlayer 损坏的联机专属选项
    context:removeOptionByName(getText("ContextMenu_Medical_Check"))
    context:removeOptionByName(getText("ContextMenu_Trade"))

    -- 注入单人规范选项：医疗检查 | [NPC名字]
    for _, c in ipairs(npcs) do
        local name = Names.name(c.id, c.object)
        local label = getText("ContextMenu_Medical_Check") .. " | " .. name
        local option = context:addOption(label, doctor, NpcMedical.open, c.object)
        if option then
            option.iconTexture = getTexture("media/ui/Heart_Red.png") or option.iconTexture
        end
    end
end

-- 安装底层被动守卫与兼容钩子
function NpcMedical.installHooks()
    if NpcMedical.installed then return end
    NpcMedical.installed = true

    -- 1. 守卫 ISHealthPanel.update：始终同步瞬时坐标防止强退，超出 2 格仅遮罩，返回后自动解锁
    if ISHealthPanel and ISHealthPanel.update then
        local orig_update = ISHealthPanel.update
        ISHealthPanel.update = function(self)
            if self.otherPlayer and (self.isNpcMedicalPanel or NpcMedical.isTargetNpc(self.character)) then
                local patient = self:getPatient()
                local doctor = self:getDoctor()
                if patient and doctor then
                    if patient:isDead() or doctor:isDead() then
                        self.parent:removeFromUIManager()
                        return
                    end
                    -- 始终同步瞬时坐标，彻底阻止原版因绝对坐标位移 > 0.5 格强制销毁窗口
                    self.characterX = patient:getX()
                    self.characterY = patient:getY()
                    self.otherPlayerX = doctor:getX()
                    self.otherPlayerY = doctor:getY()

                    local distSq = IsoUtils.DistanceToSquared(doctor:getX(), doctor:getY(), patient:getX(), patient:getY())
                    local sameFloor = doctor:getZ() == patient:getZ()
                    if distSq <= 4.0 and sameFloor then
                        -- 在 2 格范围内：解除遮罩，允许操作
                        self.blockingMessage = nil
                        self.blockingAlpha = math.max(0.0, (self.blockingAlpha or 0.0) - 0.05)
                    else
                        -- 脱离 2 格范围：保持窗口开启，展示“太远了”半透明遮罩阻塞交互；重新走近后自动解锁
                        local isNpc, npcId = NpcMedical.isTargetNpc(patient)
                        local name = (isNpc and Names.name(npcId, patient)) or (patient.getFullName and patient:getFullName()) or "NPC"
                        self.blockingMessage = getText("IGUI_TradingUI_TooFarAway", name)
                        self.blockingAlpha = math.min(1.0, (self.blockingAlpha or 0.0) + 0.05)
                    end
                end
            end
            return orig_update(self)
        end
    end

    -- 2. 守卫 ISHealthPanel.DidPatientMove：放宽浮点严格相等，保障医疗 TimedAction (包扎/缝合/消毒) 不中断
    if ISHealthPanel and ISHealthPanel.DidPatientMove then
        local orig_DidPatientMove = ISHealthPanel.DidPatientMove
        ISHealthPanel.DidPatientMove = function(doctor, patient, patientX, patientY)
            if patient and NpcMedical.isTargetNpc(patient) then
                if not doctor or not patient or patient:isDead() then return true end
                if ISHealthPanel.IsCharactersInSameCar(doctor, patient) then return false end
                local distSq = IsoUtils.DistanceToSquared(doctor:getX(), doctor:getY(), patient:getX(), patient:getY())
                return distSq > 4.0 -- 相对距离超出 2 格才判定为脱离移动（对齐原版交易 UI ISTradingUI.lua:417-419 的 2 格判定）
            end
            return orig_DidPatientMove(doctor, patient, patientX, patientY)
        end
    end

    -- 3. 拦截原版右键菜单事件
    Events.OnFillWorldObjectContextMenu.Add(NpcMedical.onFillWorldObjectContextMenu)
end

NpcMedical.installHooks()
Events.OnGameStart.Add(NpcMedical.installHooks)

return NpcMedical
