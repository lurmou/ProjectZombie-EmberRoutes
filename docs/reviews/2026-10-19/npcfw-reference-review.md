# ProjectRemnants / NPCFW 首轮参考评审

> 日期：2026-10-19｜状态：当前 JAR 静态核查完成，实机未验证

## 结论

值得作为 NPC 子系统的首要参考。当前包确实包含实体、跟随、避障、自理、岗位与车辆控制等大量实现；这不是只有 UI 或动作名称的空架子。但本轮不能认定其已经满足 EmberRoutes 的专服权威、多观察者与恢复要求，也不能按旧反编译稿直接迁入实现。

本轮只读参考目录，未修改、安装或运行上游模组。没有将上游实现复制到产品源码或纳入本仓库交付物。

## 基线与方法

- 参考目录：`D:/Project/ProjectRemnants`；根目录 `NPCFW.jar` Manifest 版本 `v0.3.0`。
- 当前 JAR SHA-256：`5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E`。
- `_decompiled/NPCFW.jar` SHA-256：`2A5FCA40046773DCFF3995D44A304D4952E53C1C6F5A9557B7A5A10937A38D2C`；与当前包不同。
- 因此 `_decompiled/src`、`_decompiled/v2` 只作导航，不直接作为当前二进制证据。
- 使用 CFR 0.152 对当前 JAR 选择性重新反编译；对 `IsoNPC`、`PhasingSystem`、`NPCDirectOrderController` 另用 `javap -c -p` 复核。
- 新提取结果位于本地忽略目录 `build/reference/npcfw-current`。下表行号均属于本次 CFR 输出，不能套用旧源码树。
- 游戏与 ZombieBuddy 哈希均与 [2026-10-18 基线](../2026-10-18/baseline.json) 一致。工具、需求快照及提取文件哈希见 [本轮基线](baseline.json)。

选择性反编译命令：

```powershell
java -jar 'C:/Users/MuMu/Zomboid/mods/_javatest/cfr.jar' 'D:/Project/ProjectRemnants/NPCFW.jar' --jarfilter '^npcfw[./](core[./](IsoNPC|NPCManager|NPCController|NPCFWAgent|SelfCareCoordinator|NPCPlayerFactory|PhasingSystem|NPCBootstrap)|ai[./]leaves[./]FollowLeaf|patch[./]IsoPlayerPatch|conversation[./]NPCDirectOrderController)$' --outputdir 'build/reference/npcfw-current' --silent true
```

## 已核实的机制及采用边界

| 领域 | 当前包中的证据 | 对 EmberRoutes 的意义 |
|---|---|---|
| 人类实体 | `core/IsoNPC.java:134` 继承 IsoPlayer；`initNPCDefaults:748` 附近调用 setNpc(true)、设置碰撞；`update:1432` 中调用 super.update | 候选载体有实际参考；不能把该更新方式直接视作专服驱动器 |
| 本地玩家耦合 | `IsoNPC.java:711` 的 isLocalPlayer 与 possessed 关联；初始化写 playerIndex=0 | 该字段赋值本身不证明占用真实玩家槽位，但必须逐调用排除相机、UI、玩家存档依赖 |
| 输入及更新补丁 | `core/NPCBootstrap.java:236` 起注册多种 transformer；`patch/IsoPlayerPatch.java` 操作 updateInternal2、瞄准等路径 | 上游依靠自有 Java Agent 与 ASM，不是单纯调用 setNpc 的方案；不能直接当作 ZombieBuddy 已支持的扩展点 |
| 跟随避障 | `ai/leaves/FollowLeaf.java:224` 处理目标车辆；`:376`/`:525` 前方随从让行；`:1252` 读取目标 playerMoveDir；`:1597` 使用速度策略 | 可参考方向、编队、路径重算和恢复的分工；本轮未证明“按键第一帧镜像”或完整礼让体验 |
| 显隐交接 | `core/PhasingSystem.java` 使用 75/90 格进入退出滞回，活跃工作会先暂停；getLocalPlayers 读取 IsoPlayer.players/getInstance | 比直接按距离销毁完善，但观察者来源不能直接满足专服全部远端玩家的要求 |
| 自理动作 | `42/media/lua/client/NPCFW_SelfCareActions.lua:1` 起加载原版动作；`:297` 起派发自理动作，先处理背包到主库存转移 | 实际具有动作包装与取消管理；仍须独立验证 NPC 的 MP 提交端、原版联网身份依赖 |
| 实例快照 | `core/NPCManager.java:1510` 起保存描述、外观、Stats、BodyDamage、XP、知识、ModData；库存使用原版二进制 save 并保存穿戴/手持索引 | 应参考必要状态覆盖与失败处理；保存字段丰富不代表跨文件崩溃安全或所有模组状态完整 |
| 权威约束 | `conversation/NPCDirectOrderController.java:161` 起按 GameClient/GameServer 和线程检查权限；拒绝文本提示仅 SP 或 host | 存在局部权威意识，但不是完整 NPC 同步协议的证明 |
| 驾驶 | 当前 JAR 列表包含 NPCVehicleDriver、VehicleObstacleScanner、VehicleTrajectoryPlanner 等模块；mod.info 称 experimental NPC driving | 作为后续专项入口；本轮尚未审阅全部驾驶算法，不称其“成熟可直接用” |

原版磁盘脚本已确认存在：`ISEatFoodAction`、`ISDrinkFluidAction`、`ISTakeWaterAction`、`ISInventoryTransferAction`。规格中的 `ISTransferAction` 不能直接作为已核实名称；饮用液体与从水源取水分别验收。

## 复用路线

1. **推荐：参考当前包的机制，独立实现最小载体和接入契约。** 保持 EmberRoutes 的稳定身份、服务端裁决、任务与事务账本独立；按验证结果逐项扩大复用。
2. **将 NPCFW 作为外部运行依赖。** 可减少部分 SP 开发，但必须先证明所需接口、生命周期、控制权与现有补丁不冲突；当前证据不足以锁定此路线。
3. **整体移植后修改。** 耦合范围很大，也会继承附身、原版 UI、据点和驾驶规则；不作为首轮方案。

首轮文件清单检索未找到 README 或 LICENSE。目录中存在带有反对盗用字样的目录名；这不是对完整许可的解释。本轮仅记录本地事实，不把“可读取/可反编译”等同于已经获得源码复制分发条件，也不假定它是开放源码项目。

## 验证状态

- 已完成：文件/Manifest/哈希核查；关键类新反编译；三类字节码复核；Lua 动作包装与原版动作文件定位。
- 未执行：游戏启动、SP 操作、专服双客户端、战斗、动作中断、存读档、强退恢复及性能测试。
- 未完成：完整许可/公开 API 核查、全部 agent 补丁覆盖、完整网络实现、驾驶与生产系统逐模块评审。

下一步设计见 [首个载体探针](../../superpowers/specs/2026-10-19-phase0-carrier-design.md)。
