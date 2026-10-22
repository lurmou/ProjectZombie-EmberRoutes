# Phase 0 载体探针测试说明（当前包 0.5.3）

> 日期：2026-10-19｜状态：0.2.0动作及 [0.3.0世界搬运主流程](../reviews/2026-10-19/probe-0.3.0-runtime.md) 已SP实机通过

当前单人优先；新增功能按 [0.5.0存档集中测试](single-player-persistence.md) 跨退出复测，保留 [0.4.0随从回归](single-player-companion.md)。

本次更新推进跨层移动与攻击中退场；具体证据和合并复测步骤见 [0.1.2 记录](../reviews/2026-10-19/probe-0.1.2-stairs-retirement.md)。[0.1.1 移动修复](../reviews/2026-10-19/probe-0.1.1-movement-fix.md) 保留为历史。

## 本包用途

验证一个人类 NPC 的构造、显示、原版路径移动、安全退场，以及0.5.0新增的正常世界保存与恢复。它沿用已批准 [载体探针设计](../superpowers/specs/2026-10-19-phase0-carrier-design.md)。

本包 **只开放 SP 候选驱动**。MP 客户端/专服可输出环境诊断，但创建/移动返回 `DRIVER_UNAVAILABLE`。用户已决定当前专注单人、保留联机接口；不代表通过MP验收。

## 构建与位置

在项目根使用 PowerShell 7、JDK 25：

```powershell
pwsh -NoProfile -File ./tools/build-probe.ps1
```

脚本默认游戏目录为 `D:/Software/GameApp/steam/steamapps/common/ProjectZomboid`；可用 `-GameRoot` 指定其他路径，但依赖哈希必须符合本轮基线，否则构建停止。

- 唯一版本源：根目录 `version.txt`。
- 可加载目录：`Contents/mods/EmberRoutesProbe`。
- 测试压缩包：`build/packages/EmberRoutesProbe-0.5.3.zip`，包含顶层 `EmberRoutesProbe` 文件夹。
- 构建报告：`build/probe-build.json`，记录依赖与产物哈希。
- 原始检查输出：`build/logs`。

生成的 JAR、mod.info、Lua Build.lua 均来自同一次构建；不要只替换其中一个文件。没有修改游戏启动参数，也没有自动安装到其他目录。

## 安装与首轮测试

1. 使用临时测试世界。模组列表若已发现本 Workshop 项目中的 `EmberRoutes Carrier Probe`，直接启用；否则将压缩包解压到 `C:/Users/MuMu/Zomboid/mods`，使路径为 `mods/EmberRoutesProbe/42/mod.info`。只使用其中一份安装，避免相同 mod id 的旧副本覆盖。
2. 保留已安装的 ZombieBuddy，按其正常 JAR 审批流程加载探针；本轮关闭 ProjectRemnants/NPCFW、CommunityTrade 和其他 NPC 模组以固定测试环境。不需要关闭反作弊或修改玩家槽位。
3. 完整退出并重新启动游戏，创建单机自定义沙盒，开启“余烬商路探针 → 启用临时 NPC 载体探针”。进入后检查日志是否同时出现版本 `0.4.0` 的 `BOOT` 与 `READY`；`READY` 只代表入口就绪。
4. 在同楼层、距离玩家 2～4 格的空地右键，选择“余烬商路：载体探针 → 在此生成”。观察是否出现人类实体，镜头与玩家控制是否正常。再次生成应显示 `EXISTS`，不增加第二个人。
5. 右键附近空地“移动到此处”，先测正前、侧面和身后 3～5 格，再测行走中改目标以及一处可绕行的墙角；通过“检查状态”对比目标、位置及 `pathSteps`。走动动画和更新计数增加都不能单独证明真实移动。超过 20 秒未到达会输出 `MOVE_TIMEOUT`，不会反复重试。
6. 可测试“停止”、随后“删除NPC”；先返回 `REMOVAL_PENDING`，等待安全退场后才输出 `REMOVED`。检查 `carrier=absent` 后，重复删除应为 `ABSENT`。0.5.0已有正常保存/恢复路径；要测试保存，应保留人物并按新版集中测试操作。

请使用正常1倍游戏速度。移动20秒有效运行超时，0.4.0已扣除暂停事件观察到的暂停时间；加速行为未单独验收。不需要搭建城镇和生产线，存档测试需要正常退出与重载。

## 日志与结果判读

客户端优先查看 `C:/Users/MuMu/Zomboid/console.txt` 中的 `[EmberRoutes v0.5.3]` 行。角色头顶仅显示简短状态码，详细原因写日志。

| 状态 | 含义 |
|---|---|
| `SPAWNED` | 构造和注册调用已完成，显示是否正确仍需观察 |
| `MOVE_REQUESTED` | 已提交原版路径请求，尚未证明移动成功 |
| `MOVE_TARGET` / `MOVE_PROGRESS` | 请求的确切目标与每秒路径进度：位置、剩余距离、pathSteps、路径结果 |
| `MOVE_REACHED` | 运行时位置已进入目标容差，还需观察碰撞和动画 |
| `MOVE_TIMEOUT` | 20 秒内未到达；日志记录真实位移距离 |
| `MOVE_FAILED` / `MOVE_PATH_ENDED` | 原生路径失败，或路径结束但尚未到原请求目标；停止，不报告成功 |
| `INSPECT` | 打印稳定 id、位置、world/pending/square 注册情况、更新计数、状态及失败原因 |
| `INVALID_POINT` / `INVALID_TILE` | 坐标、距离、楼层或方格条件不满足，没有强制加载区块 |
| `CARRIER_STOPPED` / `COMMAND_FAILED` | 本次驱动/命令失败；记录原因并尝试显式移除，不继续刷命令 |
| `CLEANUP_FAILED` | 清理失败且仍保留对象引用；保留日志，不认为已经移除 |
| `REMOVAL_PENDING` | 隐藏并保护临时对象，解除外部关系并等待攻击动画结束；尚未真正删除 |
| `REMOVAL_BLOCKED` / `REMOVAL_FAILED` | 未能确认安全或退场失败，保留对象；保留日志后显式重试，不无限点击 |
| `CARRIER_RETIRING` | 正在退场，不能继续下达移动命令 |
| `DRIVER_UNAVAILABLE` | 当前 MP 模拟入口未实现，没有生成实体 |
| `WRONG_THREAD` / `API_INCOMPATIBLE` | 执行线程或引擎接口不符合探针条件 |

若只有 BOOT 没有 READY，或提示 Java 接口未加载/版本不匹配，先检查 ZB 加载日志、包版本和重复安装，不把问题归类成“NPC 不会走”。

## 人工结果记录

| 项目 | 当前结果 | 测试时填写 |
|---|---|---|
| SP 加载、生成 | 0.1.0 用户反馈可生成；0.1.1 待复测 | 结果与日志 |
| NPC 基础位移 | 0.1.1 用户确认可移动，日志有位置变化与到达 | 0.1.2 重测并加入楼梯上下楼 |
| 镜头、玩家输入、全面绕障 | 未完成专项验收 | 分项记录 |
| 重复创建、停止、移除、再次创建 | 0.1.1 攻击中删除报错；0.1.2 待复测 | 等待 REMOVED；检查啃咬中退场 |
| 保存、返回菜单、重新开局 | 未验证 | 先手动移除；观察异常与遗留 |
| 僵尸识别、受击、死亡 | 未验证 | 后续交互关口，不属于首轮通过声明 |
| 专服与双客户端同步 | 未实现/未验证 | 当前仅有诊断和拒绝生成 |
| 动作白名单 | 0.2.0 SP 十项实机通过，MP 未实现 | 0.3.0 新增世界容器搬运待实机 |
| 断线、持久化、性能 | 未实现/未验证 | 后续关口 |

## 已知技术边界与卸载

SP 候选仍执行 IsoPlayer 的普通更新链。实现用 finally 恢复玩家实例与摄像机引用，且没有写真实玩家槽位；但原版 OnPlayerUpdate 及其他同步调用副作用尚未实机验证，这不等于完全解耦。当前没有复制 NPCFW 的 ASM 补丁，也未证明所有第三方模组兼容。

OnSave/OnPreMapLoad 的清理回调是辅助措施，不能保证崩溃或任意保存顺序下无残留。测试结束先移除实体、退出游戏，再禁用/移走本探针目录；不改动 ZombieBuddy 本身。测试存档不作为正式经营存档继续使用。
