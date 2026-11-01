# 《余烬商路》社区活动系统（A3/A4）UI/UX 重构正式实施任务书

> **文档代号**：`SPEC-ACTIVITY-UI-REFACTOR-20261101`  
> **状态**：用户评审裁决批准（已修正技术方案）  
> **面向执行者**：Codex / 开发代理  
> **核心原则**：代码证据前置、单身体控制点受控、零虚构读数、职责正交解耦、严格渐进式信息公开。

---

## 0. 任务背景与核心边界

### 0.1 目标
将现有仅供调试数据使用的“CRUD 表单面板”，重构为符合末日社区经营体验的**“社区生活与居民福祉看板”**。
通过场景卡片（Scenario Cards）、现场进度看板（Live Board）与真实结算报告，让玩家清晰理解活动的**发起目的、生理/心理收益与现场真实动态**。

### 0.2 执行红线（Hard Constraints）
1. **禁止在 A3/A4 偷跑 A5 围炉聚餐**：不引入未经资源流通与仓储扣减协议认证的聚餐、食材预留或烹饪消费。
2. **禁止虚构收益进度与虚假现场数据**：
   - 严禁出现“50% 心理减压”等未经底层数据支持的浮动进度；
   - 严禁臆测居民具体动作（如“正在沙发闲聊”），除非有确凿的 `Job/Leisure/Duty` 状态事实支持；
   - 严禁虚构寻路 ETA（如“30秒内到位”）。
3. **禁止非必要修改 `ActivityService` / `ActivityStore` 核心生命周期**：
   - 维持单权威原则，后端 `ActivityStore` 仍为唯一持久化根；
   - UI 组件严禁私自维护第二套活动业务状态。
4. **禁止全员逐帧轮询**：
   - 看板刷新必须依托 `Service.revision` 变更检测与适当节流，严禁每帧遍历全据点 NPC。
5. **折叠不等于删除**：
   - 高级设置（Quorum、GatherMinutes、DurationMinutes、规则覆盖）必须完整保留读写能力，折叠抽屉打开、修改、发起、编辑时参数不得丢失。

---

## 1. Stage 0：能力与数据真实性审计前置清单 (Fact Checklist)

在编写任何 UI 前，必须核对并冻结以下底层事实：

### 1.1 内置活动定义事实（`ActivityRegistry.lua`）
| 活动 ID (`id`) | 模式 (`mode`) | 行为白名单 (`behaviors`) | 默认规则 (`defaultRules`) | 默认限制 |
| :--- | :--- | :--- | :--- | :--- |
| `FREE_GATHERING` | `FREE` | `SOCIAL`, `READING`, `SIT`, `SMOKE`, `FITNESS`, `STROLL`, `OBSERVE` | `SOCIAL=2 (优先)`, `OBSERVE=1 (允许)` | 容纳 256 人，Quorum=2，时长 60m，召集 10m |
| `emberroutes:group_discussion` | `SCRIPTED` (`SPEECH_V1`) | `OBSERVE` | `OBSERVE=1 (允许)` | 容纳 32 人，Quorum=2，时长 60m，召集 10m，需 1 名 Speaker |

### 1.2 心理与生理收益结算事实（`ActivityReliefRecord.lua` & `Leisure`）
1. **`SCRIPTED` 模式（演讲动员）**：
   - 结算代码位于 `ActivityRelief.lua:51-53` 与 `ActivityReliefRecord.lua:2`；
   - 数值常量：`BOREDOM = 6`，`UNHAPPINESS = 3`，`STRESS = 0.02`，冷却 `COOLDOWN = 2.5` 小时；
   - **数值与单位语义**：
     - `BOREDOM`：原版属性 0~100，每小时参与最多降低 6 点（文案：**缓解无聊 -6**）；
     - `UNHAPPINESS`：原版属性 0~100，每小时参与最多降低 3 点（文案：**改善不快 -3**）；
     - `STRESS`：原版属性 0.0~1.0（浮点），每小时参与降低 0.02（文案：**舒缓压力 -2%**，严禁用 0.02 误导玩家）；
   - **结算前置条件**：活动成功完结（`event.outcome == 'COMPLETED'`），角色已入场（`m.joined`）、未退场（`not m.withdrawn`）、执勤成功（`m.duty.lastStatus == 'SUCCEEDED'`），且真实有效参与工时 `m.participationHours > 0`。
2. **`FREE` 模式（茶话闲聚）**：
   - 不走 `ActivityReliefRecord`，而是在划区内将行为偏好覆盖为 `SOCIAL=2` 等；
   - 居民在自身 `SELF_CARE` 会话中执行读书、抽烟、闲坐、交谈，享受原版闲暇生理收益（文案：**依托休闲设施持续恢复身心、增进邻里纽带**）。

### 1.3 参与者底层状态与原因白名单（`ActivityResponsibilities.lua` & `Attendance`）
必须将以下底层返回转化为玩家友好文案，未知状态回退至安全默认值：

| 底层状态 / 原因键值 | 业务真实含义 | 玩家友好文案（`ActivityPresentation` 规范） |
| :--- | :--- | :--- |
| `READY` | 无阻塞，已确认可准入 | **准备就绪** |
| `TRAVELLING` | 正在前往指定划区 | **正在赶往场地** |
| `ADMITTED` | 已在划区内，等待召集锁定 | **已进入场地** |
| `WAIT: ACTIVITY_BOOK_RETURN` | 正在执行自理借阅，需归还书籍 | **正在归还书籍...** |
| `WAIT: ACTIVITY_HAUL_SETTLING`| 正在执行搬运，需交付货物 | **正在完成物资交付...** |
| `WAIT: ACTIVITY_CRAFT_SETTLING`| 正在工坊制作，需交接产物 | **正在工坊收尾...** |
| `WAIT: ACTIVITY_COOKING_SETTLING`| 正在烹饪，需监管炉具或起锅 | **正在烹饪收尾...** |
| `WAIT: ACTIVITY_PERSONAL_SETTLING`| 正在进行其他个人自理事项 | **正在收束日常事务...** |
| `WAIT: ACTIVITY_BODY_BUSY` | 身体控制被原生动作占用 | **正在结束当前动作...** |
| `WAIT: ACTIVITY_CARGO_RETAINED` | 背包含有未结清任务负重 | **正在整理随身物资...** |
| `WAIT: ACTIVITY_NEEDS_CARE` | 遭遇紧急生理需求（饥饿/口渴/疲惫） | **生理需求紧急（无法参加）** |
| `WAIT: ACTIVITY_CARRIER_UNAVAILABLE` | 角色失联或距离过远 | **暂无法取得联系** |
| *(未知 / nil)* | 未明确的底层原因 | **状态确认中** |

---

## 2. 架构设计与文件职责边界

为了彻底避免“巨型 `ActivityPage.lua`”技术债务，重构必须解耦为五个职责清晰的组件：

```
+-----------------------------------------------------------------------------------------+
|                               UI 主容器与协调层                                          |
|  Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua|
|  - 响应 SettlementDashboard 打开/关闭                                                  |
|  - 维护 activeTab (HOME / SETUP / LIVE / HISTORY)                                       |
|  - 监听 Service.revision 变更并节流刷新                                                |
+--------------------+------------------------------------+-------------------------------+
                     |                                    |
                     v                                    v
+--------------------+--------------+   +-----------------+-------------------------------+
|  场景配置驱动目录                 |   |  无状态展示数据转换层                           |
|  ActivityScenarioCatalog.lua      |   |  ActivityPresentation.lua                       |
|  - 场景卡片声明 (id, 标题, 叙事)  |   |  - 纯函数转换：底层 Event/Roster -> UI ViewModel|
|  - 映射底层 ActivityDefinitionId  |   |  - 翻译三阶段收益与人员状态标签                 |
|  - 提供场景合理默认参数           |   |  - 提供未知/异常状态的安全保底文案              |
+--------------------+--------------+   +-----------------+-------------------------------+
                     |                                    |
                     v                                    v
+--------------------+--------------+   +-----------------+-------------------------------+
|  场景卡片与发起组件               |   |  集会现场与看板组件                             |
|  ActivityScenarioCard.lua         |   |  ActivityAtmosphereBoard.lua                    |
|  - 渲染可选场景卡片 (高亮/选中)   |   |  - 阶段进度条 (GATHERING -> RUNNING -> SETTLING)|
|  - 呈现预期收益与前置条件         |   |  - 现场统计与参与者状态卡片 (头像/状态/工时)     |
|  - 人员/场地预检列表              |   |  - 散场真实收益简报卡片 (Debrief)               |
+-----------------------------------+-----------------------------------------------------+
```

### 2.1 各文件具体路径与契约职责

1. **`ActivityScenarioCatalog.lua`**
   - **路径**：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/ActivityScenarioCatalog.lua`
   - **职责**：
     - 将玩家理解的场景与底层 `ActivityRegistry` 注册的定义进行解耦映射；
     - 声明场景的目的、叙事说明、图标/标签、预期收益结构与默认时序/规则配置；
     - **首期仅注册两个经审计支持的场景**：
       - `free_gathering` $\to$ 映射 `FREE_GATHERING`；
       - `leader_speech` $\to$ 映射 `emberroutes:group_discussion`；
     - **严禁**：私设底层不存在的参数；私自注册未实现的 `feast`（聚餐）。
2. **`ActivityPresentation.lua`**
   - **路径**：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPresentation.lua`
   - **职责**：
     - **纯函数、无状态**的展示适配器；
     - 接收 `(event, detail, roster)` 投影数据，输出 UI 组件所需的纯文本、色块和格式化标签；
     - 严格落实**三阶段心理收益展示**（预期收益 vs 等待结算 vs 实际结算）；
     - 负责状态原因映射（查阅 §1.3 白名单字典）。
3. **`ActivityScenarioCard.lua`**
   - **路径**：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityScenarioCard.lua`
   - **职责**：
     - ISPanel 派生子组件；
     - 渲染单个场景选项（卡片边框、标题、简要收益徽章、推荐标签、选中态高亮）；
     - 响应点击并向父面板派发场景变更。
4. **`ActivityAtmosphereBoard.lua`**
   - **路径**：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityAtmosphereBoard.lua`
   - **职责**：
     - ISPanel 派生子组件；
     - 负责进行中活动（`GATHERING` / `RUNNING`）与收束中（`WINDING_DOWN` / `SETTLING`）的现场可视化；
     - 绘制阶段进度条、法定到场对比条；
     - 绘制居民状态网格（姓名、就绪状态、真实累计参与工时、当前阻塞原因）。
5. **`ActivityPage.lua`（重构主容器）**
   - **路径**：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ActivityPage.lua`
   - **职责**：
     - 作为顶层据点面板的子页面（保留既有对接契约）；
     - 协调上述子组件的显隐与布局分配；
     - 承载“高级时序与行为偏好折叠抽屉”（保留全部 7 种行为与 6 项时序微调能力）；
     - 驱动业务命令（调用 `Service.start`, `Service.cancel`, `Service.update`）。

---

## 3. 三大核心界面详细规范

### 界面一：社区生活主页（Dashboard Home）
- **触发情境**：玩家打开活动标签页时的首屏。
- **视觉层级**：
  1. **首要焦点（如有进行中活动）**：置顶横幅展示当前进行中的集会状态、已到场/已参与人数、剩余时间，附带“进入现场看板”主按钮。
  2. **核心操作区**：展示场景卡片网格（☕ 闲暇茶叙 / 📢 领袖动员），引导玩家快速发起。
  3. **次要信息区**：底部折叠展示“近期集会历史”（读取已持久化的 CLOSED 记录，若无记录则显示空态提示）。

### 界面二：活动规划与人员配置（Setup & Roster）
- **触发情境**：玩家选中某个场景卡片点击“组织活动”。
- **布局划分**：
  - **左栏（场景与收益透视）**：
    - 场景卡片（大卡片）：标题、叙事描述、**【预期收益】明确标签**（如：`缓解无聊 -6 · 改善不快 -3 · 舒缓压力 -2%`）；
    - 硬件要求检查：所需设施（沙发/椅子数量提示）、所需角色（主讲人指派下拉框）。
  - **右栏（场地与人员确认）**：
    - 目标划区选择下拉框（自动统计该划区容量）；
    - 人员名册列表：左侧勾选框，右侧居民姓名与**实时预检标签**（🟢 准备就绪 / 🟡 正在归还书籍 / 🔴 生理紧急）；
    - 法定人数状态提示：`已选 X 人 / 最低要求 Y 人`。
  - **下栏（高级设置折叠抽屉）**：
    - 默认折叠，按钮标注为：`[+] 展开高级时序与行为偏好 (已预设)`；
    - 展开后展示原有 6 项时序（Quorum、Duration、Gather、Delay、Interval、Occurrences）及 7 项行为权重下拉菜单，支持极客玩家深度调优。

### 界面三：活动现场看板与结算（Live Atmosphere & Debrief）
- **触发情境**：当前有处于 `GATHERING`、`RUNNING` 或刚完结的活动。
- **布局划分**：
  - **顶栏（集会身份与紧急操作）**：活动名称、发起组织者、阶段徽章、`[提前安全散场]` 按钮；
  - **中栏（进度与等待结算提示）**：
    - 阶段横向进度条：`召集阶段 (4/5 到场)` $\to$ `进行阶段 (剩余 38 分钟)` $\to$ `散场核销`；
    - **收益状态明确标注**：`【收益状态】：集会进行中，效果将在圆满结束后结算`（严禁展示虚假的实时百分比减压）；
  - **核心区（居民现场卡片网格）**：
    - 卡片元素：居民姓名、身份（组织者/主讲人/参与者）、出席状态标签、真实累计有效工时（如：`已参与 24 分钟`）；
  - **完结态（结算简报 Debrief）**：
    - 活动关闭后替换为结算面板：展示 `实际结算结果`，列出哪些居民成功降低了无聊/压力，哪些居民因早退未能获得收益。

---

## 4. 实施阶段分解与执行计划 (Execution Roadmap)

### Stage 0：数据与调用链审计（实施前门禁）
- [ ] 核验 `ActivityRegistry.list()` 输出结构与内置定义属性；
- [ ] 核验 `ActivityReliefRecord.lua` 与 `ActivityRelief.lua` 中的数值与状态写入逻辑；
- [ ] 核验 `ActivityResponsibilities.lua` 中的阻塞原因键值与文案对应；
- [ ] 产出 Stage 0 审计确认记录，方可进入编码。

### Stage 1：场景配置与展示转换层落地
- [ ] 创建 `ActivityScenarioCatalog.lua`，完成 `free_gathering` 与 `leader_speech` 两个场景声明；
- [ ] 创建 `ActivityPresentation.lua`，实现三阶段收益文案、状态字典映射与数据安全保底；
- [ ] 编写脱库单测 `activity-presentation-test.lua`，覆盖状态映射与未知原因兜底。

### Stage 2：组件化与向导式发起界面
- [ ] 实现 `ActivityScenarioCard.lua` 卡片组件；
- [ ] 重构 `ActivityPage.lua` 的规划态：
  - 接入场景卡片选择；
  - 接入右侧场地与就绪预检名册；
  - 封装高级参数折叠抽屉（确保保存/编辑时不丢参数）；
- [ ] 运行现有 UI 测试，确保 `activity-dialog-test.lua` 与相关测试通过。

### Stage 3：现场看板与结算反馈
- [ ] 实现 `ActivityAtmosphereBoard.lua` 现场看板组件；
- [ ] 在 `ActivityPage.lua` 中集成进行态展示与阶段进度条；
- [ ] 接入散场真实结算简报（Debrief）；
- [ ] 确保与 `Service.revision` 协同节流刷新，无全员高频轮询。

---

## 5. 工程验收标准与边界测试矩阵

### 5.1 质量验收硬指标
1. **零功能回退**：原有的编辑已召集活动、取消活动、参数修改等底层契约 100% 保持可用；
2. **测试全绿**：修复此前因 Mock 桩落后导致的 6 项单测失败，新增 `presentation` 与 `scenario` 专项测试，测试套件 100% PASS；
3. **双语对齐**：所有新增文案在 `CN/IG_UI.json` 与 `EN/IG_UI.json` 中保持键值 100% 对齐，杜绝英文缺失或未汉化技术 ID。

### 5.2 四大极限边界测试用例
| 测试编号 | 场景设定 | 预期行为与验收标准 |
| :--- | :--- | :--- |
| **TC-ACT-01** | **法定人数不足（Quorum Deficit）** | 发起活动后召集超时（超出 gatherDeadline），系统平稳进入 `CLOSED`，原因标为 `QUORUM_NOT_MET`。看板正确显示“因到场人数不足取消”，不触发任何心理收益。 |
| **TC-ACT-02** | **全员不可达（Unreachable Site）** | 名单成员全员因搬运未完或关在门外无法入场。看板各卡片正确展示对应阻塞原因（如“正在完成物资交付”），不报空指针或状态卡死。 |
| **TC-ACT-03** | **进行中人员因生理紧急退场** | 活动进行中，某 NPC 极度饥饿（触发 `ACTIVITY_NEEDS_CARE`）。该角色安全退出，卡片状态变更为“已退出（生理紧急）”，其他居民继续集会，散场时退场角色不发收益。 |
| **TC-ACT-04** | **玩家中途主动取消** | 玩家点击“提前散场”。活动进入 `WINDING_DOWN` 等待当前动作安全停止，最终关闭。看板显示“集会已取消”，不产生未授权的心理增益。 |
