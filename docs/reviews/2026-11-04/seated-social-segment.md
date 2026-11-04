# Seated social segment — 2026-11-04

状态：源码与定向 Lua 验证完成；实机未验证；无实施 blocker；未提交、未推送。

依据：完整读取 `/home/hatch/workspace/goals/emberroutes-npc-realism/files/seated-social-brief.md`，按用户指定优先级执行。在线唯一需求入口本轮读取失败，未宣称已同步。只接一坐一站，不启动 DEC-003/DEC-004 或其他行为范围。

## 身体授权调查（先于实施的硬停止判定）

判定：**不需要第二次 Runtime/body 授权、不停止/重启 SIT、不新增 Job 类型，也不修改 Runtime/Controller**。坐姿对话作为原 SIT 叶中的有限配对段推进；站姿参与者仍走既有 SOCIAL Job 路线。此结论仅指现有代码契约可承载该实现，不代表原生动画已验收。

以下路径均相对 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`；行号为本轮最终工作区：

| 代码证据 | 现有契约与结论 |
|---|---|
| `TaskRuntime.lua:178` | Runtime 取得同一 ticket 的 `controller:body(r.ticket)` 后传入业务 `spec.start`，不是每个动作重新授权。 |
| `TaskController.lua:103`、`:108`、`:111`、`:157` | body 能力按原 ticket/代次校验；动作入队没有 SOCIAL 专用授权要求。坐姿对话实际不入队第二个动作，也不调用 move/stop/repose 切换。 |
| `SelfCareExecution.lua:91`、`:196`、`:215` | `c.valid()` 检查原身体、尝试、个人 claim、安全证据；原 SELF_CARE Session 只构建一次闲暇树。 |
| `LeisurePosture.lua:39`、`:45` | REST 寿命由外围 Session 持有；原生坐姿动作退出队列后，家具坐姿成立才返回 Success。坐姿本身不需要第二个持续动作叶。 |
| `SocialActions.lua:3`、`:35`、`:46` | 从既有 SOCIAL 叶抽出 conversation hooks；站姿仍由原 LeisureTimed 驱动，坐姿由原 SIT 叶驱动。效果仍先持久化 `leisure.applying`，再改 stats；未结清标记仍走既有 UNKNOWN 处理。 |
| `LeisureTimed.lua:49`、`:56` | 原社会话计时叶会直接写 `leisure.finished/stopped`，因此不能把整个 SOCIAL 叶直接塞进 SIT；本轮复用对话 hooks，保留 SIT 自己的完成/退出责任。 |

`java/src/main/java/emberroutes/probe/ProbeNpc.java:102` 的 REST 进入只设置原生 bed/resting，`:117` 的退出由原 repose 出口管理。本轮不改 Java、不添加姿态控制器。`ProbeRuntime.java:204` 要求有效 local player 才能 bindId，因此 advert 与临时 pair 保留原 actor，避免坐姿资格检查绕过 actor 或在 advert 过期后无法接受已形成的邀请。

## 数据与生命周期闭环

- **数据**：仍是 `SELF_CARE / LEISURE / SIT / ACTING / KNOWN`，Job ID、attemptId、site proof、claims 与 Session 均不变。只新增可选 `leisure.seatedSocial={socialId,applied?}`，shared `LeisureRecord.lua:32` 限制其只属于 SIT；效果未知围栏继续使用既有 `leisure.applying`。临时 coordinator pairs 仍不恢复，重建 SIT 时不会重放旧对话。
- **创建/认领**：`SocialCoordinator.lua:29` 核对 ACTING SIT、无 zoneVisit/roleDuty、原 ACTIVE Session、实际坐姿/REST、Membership 与原 seat proof/claim owner；`:84` 拒绝双坐姿。`LeisureService.lua:163` 的原 choose 回调扩展坐姿分支，选择 seat point 与同层相邻 standable point，保留 zone 与 canReachTo 检查。仍用 advertise/invite/accept/arrive；坐姿端 `LeisureSit.lua:40` 接受原 attempt，不建新 Job、不重新认领座位。
- **正常释放**：`LeisureSit.lua:18` 只结清配对、SOCIAL 冷却与原随机 pause；原 seat claim/proof 不变。未到 SIT 期限继续同一叶；到期经 `:115` 调用原 leave。到期结束的 pause 留给正常 SIT finished，避免同次结束重复抽样。最终座位释放仍是 `SelfCareExecution.lua:129`、`:149` 的 `LeisureService.finished` / `Store.finishPersonal`，没有社交专用座位释放路径。
- **异常打断**：`SelfCare.lua:198`、`:215` 保留不安全、需求、强制睡眠与无效闲暇的原 stopJob；工作仍用 `LeisureService.workReady`。`SelfCareExecution.lua:259` 经原树 halt，`LeisureSit.lua:66` 取消配对后执行原姿态离开与 REST 退出；只有正常停稳结清才释放座位。站姿伙伴取消时仅结束配对，坐姿未到期则原地继续。家具失效仍先走 `LeisureSit.lua:79` 的原 resolve/leave 失败路径。

advert 6000ms、每轮伙伴 roll、概率、距离²≤900、最多4次 geometry 检查、35秒 approach 超时、10游戏分钟对话和 standing-standing 分支均保留。cut-2 resumeHint、idle-sit 扫描界限、SIT 冷却和初始认领路径未改。原 SIT review 不再把已预留 SOCIAL 作为“结束 SIT 后换 SOCIAL”的 challenger；由同一 SIT 叶承担对话。

坐姿端复用原台词、6秒台词间隔及 boredom -6 / unhappiness -3 / stress -0.02 效果；**不调用站姿的 faceLocationF/playEmote**，因为尚无其保持家具坐姿的原生证据。站姿端转向、手势和计时叶不变。坐姿台词由既有业务 tick 推进，原生视觉与节拍表现待实机确认。

## 定向验证

测试均使用 repo package.path：

```text
Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua
```

| 检查 | 本轮结果 |
|---|---|
| `luac -p`：5份修改生产 Lua + 新测试 | PASS |
| `git diff --check` | PASS |
| `tests/lua/seated-social-segment-test.lua` | PASS：138项（含授权 actor 断言）+ 复用家具夹具26项；真实 Jobs、ReposeSites、LaborStore claims、Service geometry、SocialCoordinator、SocialActions hooks、SIT 叶与 SelfCare 最终释放；native body/pose/visibility 为替身 |
| `tests/lua/p35-social-test.lua` | PASS：原站姿配对、接受/到位、过期/超时、半接受撤回及临时 registry reload 边界 |
| `tests/lua/p35-sit-test.lua` | PASS：原 SIT 候选、REST 进入/退出、连续 review 与中断 |
| `tests/lua/idle-sit-boundary-test.lua` | PASS：52项 + 家具夹具26项；扫描界限与原门禁 |

新测试覆盖：坐姿资格与原 standing available；双向邀请；seat point + 相邻同层 partner point；10游戏分钟；对话期间原 proof/claim 不变；未到期同 SIT 继续；到期后正常结束/释放；需求中断经正常 halt + SelfCare settlement 释放；站姿取消后继续 SIT；无相邻落点拒绝；READING/STROLL/FITNESS/SMOKE 拒绝；双坐姿拒绝；Membership pending、SOCIAL zone、needs、SOCIAL cooldown、decision pause 门禁。没有把两张有效独立座位当成允许 seated-seated 的理由。

测试替身只验证协议与责任；需求中断测试显式调用原叶 halt + SelfCare 最终结清，并非实机 Runtime/身体停止时序证明。初次测试暴露了夹具继承冷却、家具登记 revision 和错误假设 SIT 为10分钟（当前配置为60分钟）；修正测试前置条件，未放宽生产守卫。最终无残留失败。未运行全量回归、Java 构建、打包或游戏。

## UNVERIFIED

- 游戏内坐姿与站姿对话动画（包括坐姿台词显示、站姿手势与姿态共存）。
- 站姿伙伴真实原生寻路。
- 对话中途真实磁盘保存/重载。
- 游戏内社交频率变化。
- 性能。

以上均 **UNVERIFIED**，不得借用 Lua 结果。无已识别的实施 blocker；上述实机验收差额仍保留。
