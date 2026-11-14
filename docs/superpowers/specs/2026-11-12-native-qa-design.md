# 原生游戏自动测试：首版设计

状态：用户于 2026-11-12 批准设计并执行。范围是可运行的最小闭环；专用小地图后续评估。

## 目标与取舍

由外部脚本启动隔离游戏，主菜单测试按钮和文件指令使用同一游戏内执行器，结果以小型 JSON 回传。日常场景在同一世界连续运行；冷启动重进加载同一测试世界；需要新起点时创建新的 QA 缓存目录，不删除或覆盖游玩存档。

纯鼠标自动化容易受菜单和模组布局影响，截图交互次数也多；远程执行任意 Lua/Java 会扩大权威边界。采用本地文件协议，只接受 run/status/cancel/quit 和已登记场景。文件通信可参考 tools/ui-preview/PreviewLiveControl.java；它不证明游戏世界链路已可用。

当前 Main.java:7 仅暴露生产桥；新增独立 QA 桥仅在 JVM 明确配置 emberroutes.qa.root 且有效 session.json 时暴露。默认生产启动不注册 QA 桥、不加载 QA 模组/菜单。QaFileProtocol 无引擎依赖；QaBridge 只做 Kahlua 值转换和结果输出；游戏内 Lua 场景负责调用现有服务。

## 权威与生命周期依据

- 原生建档参考安装版 CharacterCreationMain.lua:2159 的 createWorld → LoadingQueueState，以及 MainScreen.lua:1283 的 continueLatestSave。Sandbox 测试世界保留正常保存路径，不能套用无存档的 LastStand。
- 固定起点使用当前原版 Muldraugh spawnpoints.lua 的第一处房屋坐标 10770,10271,0；加载后检验真实室内/可行走地块，再从有界同房间区域选择 NPC 起点/目标，不假造房间。
- 据点创建走 SettlementLedger.commit；NPC 创建走 NpcCommands 的正式 spawn，成员登记走 MembershipService.register，驻扎与 WAIT 通过 request/advance。QA 只写自己的世界标识与样本元数据。
- 移动/取消走 TaskDiagnostic.submit/cancel → TaskRuntime/TaskController/Driver；原生动作套件复用 Actions.execute。正常结束等待执行会话停止及已知效果；异常请求同一停止协议，不能清表冒充完成。原件责任与身体停稳继续分开。
- 保存/退出使用已安装的 MainScreen.quitToDesktop → ExitSave/Persistence 保存协调，不直接绕过屏障调用退出。外部超时标为未完成并保留现场，不写 PASS。

## 文件协议

每个启动目录固定 session.json、command.json、status.json、result.json；写入用临时文件原子替换。session 包含 format=1、runId、version、jarSha256、sourceHash、saveName、cacheDir、autoStart；QA 桥核对实际载入 JAR 和版本。目录与场景编号不从命令接受任意路径。

command 包含 format=1、runId、正整数 seq、op、caseId；op 为 run/status/cancel/quit，caseId 为 smoke/actions。runId 必须匹配，seq 单调递增；重复命令不重复执行，未知字段/格式/场景拒绝。文件大小有界；游戏主线程最多每 250ms 观察一次文件变化。

状态：MENU_READY、LOADING、PREPARING、RUNNING、STOPPING、PASS、FAIL、BLOCKED、CANCELLED。状态变化时写 status；终态写 result，带 runId/seq、版本与源指纹、场景、证据、失败原因。收尾不明用 BLOCKED。请求接受不等于测试通过。

## 首版场景

smoke：校验世界/桥版本 → 创建或核对 QA 据点/NPC → 驻扎后 WAIT → 真实移动到同房间目标 → 核对实际距离/位移/会话收束 → 再发移动并取消 → 核对取消和停稳。actions：在同一合格场景上复用生产原生动作套件，记录每项物品/进食/饮水/中断证据，并走正式清理。两者都不通过强行改状态伪造 PASS。

每次运行只记录该场景覆盖范围。sleep/床姿全链路、真实磁盘故障、规模性能未自动获得覆盖。

## 主菜单与验证

独立 QA 配置下增加清晰的“余烬商路：开发测试”按钮，显示启动中/失败反馈；点击与自动启动使用同一 Session 服务。UI 复用 ISButton 和 PageLifecycle，不绘制第二套按钮。OnGameStart 解除菜单资源，回到菜单可重建；关闭/隐藏不做业务扫描。CN/EN 文案同步。

新增 qa 原生预览场景，运行 preview-native-ui.ps1 -Scene qa -Smoke，回读 CN/EN 截图；随后真实游戏检查主菜单和输入。工程验证、实机动作、保存重进、性能分别记证据。在线需求 §0.1 的“AI 无法实机”前提由本轮明确批准的自动测试方向覆盖，在线正文本轮不改；现有版本和日志要求继续执行。
