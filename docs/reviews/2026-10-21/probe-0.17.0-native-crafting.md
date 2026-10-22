# 0.17.0：原版木叉制作原型

> 后续修正：玩家借用和砧板限制已被用户否定，当前按[0.17.1分类仓储与通用表面](probe-0.17.1-classified-crafting.md)执行；本文保留为历史截点。

> 2026-10-21｜状态：实现及必要本地检查完成；新实机未运行｜主代理独立实施，无Deepseek委托或子代理

用户明确要求在已讨论设计上直接开始下一步。已重读唯一在线需求，SHA256仍为`3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834`。[设计](../../superpowers/specs/2026-10-21-commissioned-crafting-design.md)与[实施计划](../../superpowers/plans/2026-10-21-crafting-prototype.md)限定先做原版动作原型，完整生产父单与BOM后续。

## 本轮行为

新增`CraftRecipeAdapter`定向核对当前安装的木叉配方/砧板：实际输入IO索引、保留工具与耗材、单件输出、玩家知识、NPC独立知识与真实雕刻2级。改变配方结构拒绝适配；原生InputScript.canUseItem校验刀具状态。仅选择玩家主背包中未装备、未收藏、未被认领的一件SmallHandle和一把可用刀，最多检查512项；不扫描世界箱子或包中包，不借用木勺替料。

`CraftProbe`按稳定npcId管理独立原型记录，UUID标识订单和砧板、generation隔离旧动作。显式试制使用ISInventoryTransferAction接收原件、ISHandcraftAction制作、再把原产物及原工具交回玩家。两人站在真实台旁，原型不自动寻路、生成材料、改技能或注册玩家槽位；传授是独立显式操作。入口只在原版Debug诊断子菜单。

动作使用实例级守卫，不覆盖原版类。每件新logic与manualInputs；start填充后与效果前核对实际输入集合、原件身份/位置、知识技能、占台和容量。原版performRecipe负责消耗、生成、XP及工具磨损；本模组以实际耗材、工具及新产物核对结算，不把onComplete或nil返回视为成功。独占台只在无其他使用者时设置，释放时仅清本NPC占用。

新增Work执行器注册和唤醒入口，原型复用现有每tick全局最多4名工人的调度预算。busy、人工接管、暂停、保存和删除门禁覆盖运行及待归还记录；自动物流重新启用也不能绕过持货门禁。其他NPC不受当前原型阻塞。原型借用记录阻止另一原型在首次转移之前借用同一原件，同时尊重LaborStore已有认领。

原型输入/输出只在玩家与NPC主背包流转，当前世界仓储规划不扫描这两类库存。**没有把该借用记录当成正式生产锁料实现**：后续开放共享仓库必须按设计接入统一LaborClaims、所有者集合变更和加载冲突核对，不能直接复用此局部借用检查冒充完整生产权威。

## 保存与失败边界

ModData仅保存版本化标量记录，包括订单/NPC/请求者、输入与产物ID、砧板ID、代次、阶段及核对结果；不保存userdata或闭包。加载先完整核查记录和借用冲突，再发布；运行记录暂停，COMMITTING记录标不确定，不自动入队。正常保存走既有Work.pauseAll取消尚未提交动作，然后现有载体检查点保存原件。

取消先失效代次再清自有队列。待归还阶段只能显式返回已知原件；缺失或不确定效果不会自动重做，也不会按类型补产物。原生容量逻辑若把产物落地，保留原产物ID；用户拾回后，只有原生消耗、工具和产物身份已核对的记录才可在归还后结束。消耗后异常且证据不足仍保留门禁。

新增静态核对确认：新CraftRecipeData的消耗结果不应依赖旧getIsCraftingConsumed标志。当前ItemUser.RemoveItem清物品container并从列表移除；适配器核对原版getAllConsumedItems包含指定耗材、耗材已不在两边主包且无container。此结论来自当前安装JAR，不是猜测标志位。原版Lua与JAR基线沿用[本轮制作基线](crafting/baseline.json)；构建再次校验PZ42.21.0与ZombieBuddy2.3.4哈希。

普通存取流程仍未实机验收；原版消耗/生成、ModData、NPC检查点和世界文件没有共同原子落盘协议的证明。未知提交保守停工不是“崩溃无损”。完整递归BOM、缺工具前置生产、定额补库、正式制作页和MP均未实现。

## 检查记录

- 新增`craft-probe-test.lua`加载安装目录的实际ISHandcraftAction和ActionManager Lua，使用安装Kahlua执行；原生Java制作、背包、队列和NPC是替身。定向覆盖实际技能/知识门槛、IO索引、重复效果、取消/占用、输入换同类、异常后不重试、落地产物及正常保存/重进门禁。
- 相关multi-worker与logistics-progress回归通过；夹具内部复用早期搬运断言，没有运行历史全套。输出保存在`build/logs/craft-targeted-final.txt`；最终检查数量以日志为准。
- 必需preflight含Lua语法、结构/祖先契约、候选规则、LuaLS与索引检查。结构工具明确报告原版ISFluidEmptyAction的既有解析缺口，不把未解析文件记为通过；LuaLS告警另逐条核对。原始记录`build/logs/preflight-0.17.0.txt`、`build/logs/craft-luals-warnings.txt`。
- 版本元数据构建及固定JAR基线、现有Java逻辑/检查点/名单/表迁移检查通过；没有修改Java业务源码。生成`build/packages/EmberRoutesProbe-0.17.0.zip`，未发布工坊。输出`build/logs/build-0.17.0.txt`。

游戏引擎未启动，NPC原生制作历史、动画、真实转移/磨损、玩家占台冲突、正常存档重进及性能均未验证。只安排[三组简短集中实测](../../testing/single-player-native-crafting.md)，不追加历史清单。

## 最终收尾

最终制作合同检查69项通过，输出`build/logs/craft-final-contract.txt`；[保留副本](crafting/0.17.0-contract-check.txt)。完整preflight通过：76份Lua语法0错误/警告，LuaLS0错误，仅余既有DebugMenu链式覆盖的duplicate-set-field与ContainerConfigControls动态控件表的missing-fields两项信息提示。类型初查的原型动态字段和空值提示已通过类型声明及logic/产物守卫收口，不是遗留错误。日志`craft-luals-warnings.txt`保留的是修正前诊断，最终以preflight日志为准。

7份相关Markdown链接检查0错误/提示；release-check0错误/提示。最终ZIP的83个文件与模组目录逐字节一致，SHA256为`166436896945D31AF67F05B6452193F1AAC4EE86F324E298A29F3C7CDD9D2371`，核对记录`build/qa/probe-0.17.0-package-check.json`及[保留副本](crafting/0.17.0-package-check.json)。最终Lua收尾后仅重新打包，沿用已通过构建的0.17.0 JAR；未重复修改Java业务或发布工坊。
