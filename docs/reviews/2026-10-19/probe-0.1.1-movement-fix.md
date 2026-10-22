# 载体探针 0.1.1 移动修复

> 日期：2026-10-19｜状态：源码修复及构建完成，修复后实机待复测

## 实机反馈与证据

用户已测试 0.1.0：能生成 NPC，但“移动到此处”后沿原朝向持续行走，没有按目标点移动。这是移动验收失败，不将此前静态检查通过改写成玩法通过。

本机 `console.txt` 中的 EmberRoutes 行确认运行版本为 0.1.0、游戏 42.21.0、ZB 2.3.4、SP 模式；记录了 SPAWNED、PlayerMovementState、MOVE_TIMEOUT 等状态。仅摘录本模组行保存在 [0.1.0 实机日志摘录](probe-0.1.0-user-runtime.txt)，没有复制整份其他模组/玩家日志。

一条旧日志在请求后的下一帧返回 MOVE_REACHED 且 displacement=0；它只表示角色已在旧判定容差内。由于 0.1.0 未记录目标坐标，不能据此证明鼠标选点正确，更不能把它计为移动成功。0.1.1 为每次请求与进度补充坐标证据。

## 查明的实现缺口

当前游戏 JAR 哈希仍为 `E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。

重新提取当前 JAR 的 `PathFindBehavior2`、`PathFindState`、`player/PlayerMovementState`，结合前轮同基线提取的 IsoPlayer/IsoGameCharacter 核查：

1. `IsoPlayer.initializeStates` 映射普通玩家移动到 PlayerMovementState；该状态仅处理运行/冲刺状态，没有调用 PathFindBehavior2.update，也没有替探针跟随目标。
2. `IsoGameCharacter.pathToLocationF/pathToAux` 提交目标并设置移动/路径标志，不代表当前玩家动作组已经建立路径执行者。
3. `PathFindState.execute` 则明确逐次调用 PathFindBehavior2.update，并处理 Working/Failed/Succeeded。不能因为类存在就假设玩家动作组会运行它。
4. 原探针只设置 AIComponent.justMoved 并调用 super.update，缺少上述持续执行者。普通 doDeferredMovement 仍会沿现有动画朝向提交位移，与用户现象一致。

提取源码位于本地忽略目录 `build/reference/pz-current`；相关文件指纹和实际包哈希见 [0.1.1 机器记录](probe-0.1.1-verification.json)。这是已确认的代码缺口；尚未通过修复后实机排除其他引擎或选点问题。

## 修复

- 新增 ProbeMovement，集中处理移动生命周期、到达、路径失败、原生路径结束但未到指定点、20 秒超时和取消。
- ProbeNpc 在 doDeferredMovement 内显式调用一次原版 PathFindBehavior2.update，以当前路径路点更新朝向；不再同时调用普通前向 root motion 提交路径。
- 同一个更新中读取原版动画位移供原版路径行为使用，末尾清理位移累积。空闲、等待和停止时不继续消耗旧行走位移；不逐帧修改坐标冒充运动。
- 尚未取得路径时不强置持续行走；停止/失败清理 path2 与旧路点标记。没有增加无限重寻路。
- MOVE_TARGET/MOVE_PROGRESS/完成状态与 INSPECT 均含目标、位置、剩余距离、pathSteps、路径结果和当前状态。进度日志最多每现实秒一次。
- 完整版本递增到 0.1.1，Lua/模组元数据/JAR 由同一版本源生成。

此修复只接入探针自身的受控行走，不完成翻越、战斗受击位移或 TimedAction 的适配。MP 驱动仍未实现，未引入伪连接或玩家槽位。

## 检查与边界

- 修改前新回归测试先因缺少 ProbeMovement 失败；实现后 Java 编译、44 项纯逻辑断言通过。
- 新断言验证：每个活动 tick 推进路径一次；持续推进而不是只发请求；到达前不再追加位移；失败/超时/取消后不继续推进；路径结束但未到原目标不冒充到达；可向身后替换目标。
- 这些测试验证驱动契约和状态处理，不模拟完整引擎，不证明真实转向/碰撞已经正确。
- 完整 preflight 通过，LuaLS 为 0 error / 0 warning；原始输出见 [preflight](probe-0.1.1-preflight.txt) 与 [构建/断言](probe-0.1.1-build.txt)。doclink 结果记录于机器记录及本地原始日志；实机状态不由这些检查替代。
- 0.1.0 的“可生成”来自用户反馈和现有日志；0.1.1 显示/移动/停止/碰撞仍需复测。专服、双客户端、存档恢复仍未验证。

## 最小复测

完整退出游戏后替换为 `build/packages/EmberRoutesProbe-0.1.1.zip` 中的整套模组，确认 READY 日志是 `[EmberRoutes v0.1.1]`。

1. 空地生成，等两秒，确认未收到命令时不自行行走。
2. 分别命令走向前、左/右侧、身后 3～5 格，确认转向、接近指定点、停下。
3. 行走中改目标，再测试“停止”；之后可补测一处可绕行墙角。
4. 若失败，保留本次 MOVE_TARGET/MOVE_PROGRESS/结束状态与 INSPECT 行；这些已包含目标和实际位置，不需要靠动画猜测。

通用安装和移除步骤见 [测试说明](../../testing/phase0-carrier.md)。
