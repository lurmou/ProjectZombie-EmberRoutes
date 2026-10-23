# 按需配方链 Implementation Plan

用户已批准设计；主代理独立实施，不使用子代理。

**Goal:** 缺少中间材料时规划并真实执行前置制作，支持原木→木板→下游成品。

**Architecture:** 纯有界规划器与原版配方/物理库存读取适配分离。整链沿用单一工单ID和认领权威，以顺序节点驱动原Production执行器，保留中间产物原件。

**Tech Stack:** PZ42.21 / Kahlua Lua / 当前Java桥 / 分类仓储。

**Spec:** [批准设计](../specs/2026-10-22-production-chain-design.md)。

## 全局约束与评审重点

- DFS路径环检测；根为1层，最多4层；规划逐tick限额，耗材按批次，工具跨批复用。
- 不读取玩家背包，不新增虚拟扣货，不放宽现有原版动作支持范围。
- 原料、入库中间产物和工具共享同一稳定taskId；不以释放子工单造成认领空隙。
- 检查多分支争用、可替代输入/多配方、产出取整与副产物、暂停取消、保存未知提交。
- 参考本地D:/Project/Applied-Energistics-2-main的CraftingTreeNode/Calculation及ChildCraftingSimulationState的职责划分；独立实现，不复制源码。

## Task 1: 可回退、可分片的计划计算

- [x] 新增shared/EmberRoutesProbe/ProductionChainPlan.lua：new(recipe,quantity,stock,producers,resolve) / step(budget)，返回拓扑节点、原料ID与阻断原因。
- [x] 新增client/EmberRoutesProbe/ProductionChain.lua：复用CraftingCatalog产物索引、分类实际库存扫描、各节点技能知识/台面检查，new(actor,npc,entry,recipeId,quantity,object,taskId,knownMissing) / step。
- [x] 新增tests/lua/production-chain-test.lua覆盖短缺递归、批量工具、分支回退、原料不重复、环路/深度、产物富余复用和限额。

## Task 2: 同一权威下的物理执行

- [x] 扩展shared/CraftRecord.lua的可选版本化chain与held资产契约；旧format3不变。
- [x] LaborStore.replaceNative原子更换held认领；ProductionSupply扫描和恢复held，活动原件从held中移除，避免重复资源键。
- [x] Production.lua增加链规划阶段、节点切换与保存恢复。中间产物交付后归held保护；节点不释放父单，最终完成或取消才释放。
- [x] 定向执行检查：缺原料等待，补料通知后唤醒；暂停/取消不重做已完成节点，未知提交继续阻断。

## Task 3: 预检和界面一致

- [x] CraftingPreview复用链规划并提供“可前置制作/阻断”结果；CraftingDraft和工单显示当前步骤及最终目标，CN/EN配对。
- [x] 最小制作宿主回归与新增链规划测试；Lua preflight、版本/构建/发布检查、包源一致；仅声明实际完成的静态及宿主验证，实机待确认。
- [x] 更新证据文档、HANDOFF/BACKLOG和设计状态；保留此前实验UI与本轮裁剪核查记录。
