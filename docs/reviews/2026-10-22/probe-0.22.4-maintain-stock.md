# 仓储最低存量：实施与定向验证记录

日期：2026-10-22。版本：0.22.4。状态：已实现，Kahlua宿主测试与静态门禁通过，游戏实机未运行。

## 1. 实施范围与接入成果

按用户批准的[实施设计 v1](../../superpowers/specs/2026-10-22-maintain-stock-design.md)与[实施计划](../../superpowers/plans/2026-10-22-maintain-stock.md)完成开发：

| 模块 | 职责与变更 |
|---|---|
| `shared/EmberRoutesProbe/StockRule.lua` | 纯规则计算：缺口 $D = \max(0, M - P)$、请求批次上限 32、多产物取整、规则字段合法性与唯一业务键校验 |
| `client/EmberRoutesProbe/StockStore.lua` | 持久化账本：ModData `maintainStock={format=1,revision,rules}`，原子命令（create/update/enable/disable/delete/retry），据点上限 32/全局 128，周期双向关联与墓碑清理 |
| `shared/EmberRoutesProbe/CraftRecord.lua` | 生产记录契约扩展：可选 `origin={kind="MAINTAIN_STOCK",ruleId,cycleSequence}` 版本化校验，合法支持 `TARGET_REACHED` 提前收束 |
| `client/EmberRoutesProbe/Production.lua` | 生产执行器适配：支持外部预分配 `taskId` 与 `origin`；`nonPreemptive` 避免抢占（不调 `cancelAll`）；批次边界提前收束并记录真实交付与工具归还；提供 `findRootOrders` 供手动单冲突检测 |
| `client/EmberRoutesProbe/StockService.lua` | 后台监督服务：`WarehouseIndex.watch` 引用计数维护、全局有界轮转队列（每 tick 最多评估 4 条、最多派发 1 次）、60 游戏秒低频检查、游戏暂停门禁、完整覆盖检查、跨据点重叠检测、周期终结触发新盘点与保存屏障 |
| `client/EmberRoutesProbe/UI/StockRules.lua` | 制作页第 3 视图：规则列表展示（仓内 P / 目标 M / 状态徽章 / 进度条）、详情卡目标步进修改、操作按钮（启停/重试/删除）、新规则创建表单、参数预填支持 |
| `client/EmberRoutesProbe/UI/CraftingPage.lua` | 顶部导航栏升级为三项（配方/工单/最低存量），支持带参视图切换 |
| `client/EmberRoutesProbe/UI/WarehouseDetails.lua` | 仓储物品详情卡增加“最低存量”一键直达跳转按钮 |
| `shared/Translate/CN/IG_UI.json` & `EN/` | 成对补充 26 项中英文本地化翻译条目 |

## 2. 验证证据

1. **纯规则与生命周期逻辑** (`tests/lua/stock-rules-test.lua`)：
   - 44 项断言通过。覆盖唯一键、参数校验、各状态计算、32 批次上限截断、yield 向上取整、ModData 命令修改、版本递增、周期准备/关联/收束/删除墓碑清理。
2. **监督服务与非抢占派发** (`tests/lua/stock-service-test.lua`)：
   - 10 项断言通过。验证 `checkEarlySettle` 在 $P \ge M$ 与禁用时正确触发提前收束；验证缺口时以 `nonPreemptive = true`、`origin` 派发父单并关联周期。
3. **既有生产契约回归** (`tests/lua/craft-probe-test.lua`)：
   - 全量 652 项断言全部通过。证明普通手动工单、工具复用、负重策略、原件认领和保存恢复未受任何破坏。
4. **会话、配方链与界面回归** (`tests/lua/`)：
   - `execution-sessions-test.lua`: 48 项通过。
   - `production-chain-test.lua`: 18 项通过。
   - `settlement-tabs-test.lua`: 541 项通过。
5. **静态门禁检查**：
   - `preflight`: 103 个 Lua 文件扫描，0 错误，0 警告全部通过；语法、LuaLS、不变量规则 0 命中。
   - `release-check`: 0 错误通过。
   - `doclink`: 4 份相关文档全部 0 断链。

## 3. 边界与未验证事项

- 真实游戏环境尚未运行，真实画面、UI 交互事件响应与原生制作动作效果标记为**未验证**。
- 不扩展自动采集、自动购买或跨据点自动调拨；仅在现有固定物品配方链内自动补齐。
- 单人优先原则保持有效，联机专服适配仍为后续事项。
