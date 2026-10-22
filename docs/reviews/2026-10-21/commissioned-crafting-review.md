# 委托制作：B42 技术核查

> 后续修正：玩家借用和砧板限制已被用户否定，当前按[0.17.1分类仓储与通用表面](probe-0.17.1-classified-crafting.md)执行；本文保留为历史截点。

> 2026-10-21｜技术核查完成，设计待用户评审｜产品仍为0.16.1；本轮未修改生产代码、未实现制作原型。

## 结论

建议下一步先验证一个真实工作台配方，再建设委托制作完整闭环。首选`Base.CarveWoodenFork`与实际`Chopping_Block`实体：同一NPC取指定原料与刀具、到台制作单件、将原产物和原工具送回登记容器。生产父工单在全过程持有认领，自动物流共享同一认领权威。具体方案见[设计草案](../../superpowers/specs/2026-10-21-commissioned-crafting-design.md)。

主要技术风险不是面板，而是NPC原版动作兼容、技能判定差异、跨阶段资产认领，以及原版消耗/生成与本模组检查点之间的非原子边界。仅保存工单表不能证明崩溃幂等；无法判定的提交必须停在待核对状态，不能自动重做。

## 需求与基线

- 已重新读取[唯一在线需求](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit)文本导出；SHA256为`3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834`，与本日既有记录一致。需求第5.0节要求真实工作台、玩家知识、NPC独立知识与物理技能；管理面板无需额外物理终端。
- 完整生产另有耗材随数量增长、催化工具恒1、依赖环路检测/最多4层、缺工具前置单、单件检查点等硬约束。本次单层原型不代表这些功能已实现，也不取代需求。
- 当前安装PZ42.21.0、ZombieBuddy2.3.4；JAR和原版完整文件哈希见[基线](crafting/baseline.json)。对安装的pzopt覆盖类另做优先类路径复核；原始字节码有分支重排，所审知识方法语义静态判断一致，没有实机类加载/兼容证明。
- 证据分为[当前原版Lua/配方摘录](crafting/vanilla-evidence.md)、[JAR字节码摘录](crafting/jar-evidence.md)和[限定Kahlua合同检查](crafting/contract-check.txt)。索引与类型桩仅作导航。

## 已确认的引擎契约

| 事项 | 当前安装证据与影响 |
| --- | --- |
| B42制作入口 | 当前`craftRecipe`走`ISHandcraftAction`与`HandcraftLogic`，不能直接套旧`ISCraftAction`。构造参数和manualInputs格式见原版E6/E8。 |
| 具体输入 | 动作start创建新logic、填手动输入并调用canPerform建立实际输入缓存。需要按配方IO索引提供原件ArrayList；业务仍须核对最终实际输入ID集合，不允许自动补选私人/地板材料，不设force绕过检查。 |
| 完成信号 | `stop()`同时调用onCancel和onComplete；`performRecipe()`无论成功失败均返回nil。单人perform先执行配方，再调用父perform推进队列。回调/返回值均不能单独作为成功凭据。 |
| 消耗与生成 | `CraftRecipeData.perform`先复验角色，再消耗输入、生成输出、加XP/制作历史；没有与本模组账本共同事务的证据。中途异常可能已有资产效果。 |
| NPC类型 | 公共构造接收IsoGameCharacter，但实际消耗/制作历史路径存在IsoPlayer强转，工作台占用也使用IsoPlayer。当前ProbeNpc继承IsoPlayer，静态类型可接；初始化、动画、历史表和运行行为未验证。不可外推任意角色均支持，不可占真实玩家槽位。 |
| 技能与知识 | 原版required-skill判定可接受recipe-at-hand收益，不完全等价于需求中的NPC物理技能门槛。需额外逐项核对实际技能；知识使用CraftRecipe对象的严格判定，传授后再核验，不靠UI显示已解锁。 |
| 工作台与距离 | HandcraftLogic覆盖的工作台距离门槛是DistToProper小于3；原生容器可达另有2.5距离等检查，但不懂本模组登记/共享权限。材料必须真实搬到NPC，不能把据点全部箱子作为远程扣料池。 |
| 工作台占用 | 原版实体窗口开启设置usingPlayer，关闭清空。NPC需独占租约及实际usingPlayer校验；释放仅清自己的占用。玩家开窗/夺占的冲突需原型确认。 |
| 产物位置 | 原版Actions.addOrDropItem先放包，超重时将同一产物原件落地。先预检容量，事后仍核对原件ID与位置；不能将不在包内误判为未制作并重试。 |

`modscan --file ISHandcraftAction.lua`未发现当前已装模组同名文件替换；这不证明所有运行时钩子兼容。候选配方本身没有自定义OnCreate、流体、热源或电力要求；未来新增配方须按注册适配器单独核查。

## 首个配方的取舍

`CarveWoodenFork`脚本要求：雕刻2、已学配方，`AnySurfaceCraft`，1件SmallHandle或WoodenSpoon，1把sharpknife保留工具且不能钝，可轻微磨损，产出1件WoodenFork。`Chopping_Block`的CraftBench接受AnySurfaceCraft。首个适配器固定选择SmallHandle分支，避免静默消耗成品木勺；实际完整ID、IO索引及配方/台归属在原型运行时核对，不能只靠拼接字符串。

生产N把木叉需要N件选定耗材和1把可用刀；“工具恒1”不代表刀无限耐用，刀变钝/损坏应暂停并报告。建造砧板时的Woodwork:1是家具建造门槛，不是木叉制作技能。

备选`SpinThreadFromWool`有真实纺车，但覆盖不到保留工具、技能和知识门槛；`SawLogs`属手持制作，不适合验证本阶段的真实工作台约束。均不如木叉适合作为第一条完整技术样本。

## 现有代码可复用与必须扩展的边界

- [Work/调度入口](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work.lua)已按npcId隔离，但busy、暂停、自动领单与保存入口目前只识别搬运执行器。制作必须接入同一执行仲裁，不可再注册一套互相看不见的NPC控制循环。
- [LaborClaims](../../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/LaborClaims.lua)同资源排他，换taskId会拒绝；同一owner再次acquire要求资源集合一致。[LaborStore](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LaborStore.lua)恢复仅接受EXPLICIT_TRANSFER，finish释放整个认领。不能把生产父单的原料直接交给普通子搬运单，也不能在取料完成时释放生产材料。
- [WorkTransfer](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/WorkTransfer.lua)的真实原件转移、容量和效果前守卫值得复用。生产记录须独立版本化，再由公共认领/执行仲裁接入；不伪装成已有EXPLICIT_TRANSFER结构。
- [Persistence](../../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Persistence.lua)当前保存先停止劳动、再存载体检查点。新增制作需统一静止与核对；原版制作、Lua表、NPC检查点、世界文件并无已证明的原子落盘协议。

## 本轮验证与下一步

已做：原版脚本/Lua和当前JAR定向核查、pzopt知识路径静态复核、文件冲突扫描；在安装Kahlua宿主执行实际ISHandcraftAction代码的限定检查，确认取消双回调及成功/失败均nil。该检查替换了native host，没有执行真实制作、消耗、动画、工作台占用或存档恢复。

[检查夹具](crafting/contract-fixture.lua.txt)保留原始执行内容，[输出](crafting/contract-check.txt)对应本轮运行。可从项目根目录复现，路径由现有KahluaLaborTest相对tests/lua解析：

```powershell
java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java ../../docs/reviews/2026-10-21/crafting/contract-fixture.lua.txt
```

新增文档已登记HANDOFF/BACKLOG；本轮6份Markdown链接检查为0错误、0提示。工作保留在本地；仓库尚无初始提交，不为本次设计把原有未跟踪项目整体纳入提交。

下一步先做原版动作小原型，集中验证真实输入/输出ID、工具磨损、取消和正常保存重进；通过后再实施共享认领扩展与委托生产闭环。完整递归BOM、多人运输交接与崩溃一致性分别留后续，不把本轮静态核查记成玩法通过。原型前保留0.16.1实机物流待确认状态。
