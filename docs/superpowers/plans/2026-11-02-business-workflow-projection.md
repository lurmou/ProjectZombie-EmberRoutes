# 制作、搬运配送、烹饪动态步骤接入计划

> 日期：2026-11-02｜状态：继续已确认普通工作范围；本地顺序实施，保留原执行器与账本。

**Goal:** 现行业务显示各自真实适用步骤，退出固定四段猜测的主显示路径。

**Architecture:** CraftWorkflowView / HaulWorkflowView 为对应业务纯投影，CookingMonitor 就地补只读 steps；Cards 已有同一显示契约。不建立 Workflow Runner，不持久化 GUI 树。

**Tech Stack:** PZ Lua/Kahlua 与既有 Job/Manifest/CookingRecord。

**Spec:** [确认设计](../specs/2026-11-02-workflow-domain-boundaries-design.md)。

## Global Constraints

- 不改变原版动作、派工、存档格式、Claim/容量/炉具的清偿语义。
- 只有业务证据充分才显示 COMPLETED；未执行不借阶段索引假完成。
- BOM、Manifest、烹饪原件/流体/设备义务分别保留；Projector 无世界访问或资产写入。
- 旧受支持探针显示可保留回退，但现代 CRAFT4/HAUL3/COOKING1 使用领域步骤。

## Review Focus

- 制作 APPLIED 只证明当前一次配方效果，不冒充全部订单已完成。
- 取消物流的 WITHDRAWN 不得画成已领取/交付。
- 动态目的地变化不倒退既有 deliveryReceipt。
- 烹饪热源未清偿且无 Session 仍是义务，不能画完成。
- UNKNOWN/流体进行中与普通缺料分开；无对应事实就不造补水/加热步骤。

## Task 1：制作与搬运领域投影

**Files:** 新增 client/EmberRoutesProbe/CraftWorkflowView.lua、HaulWorkflowView.lua，修改 OrderMonitorService.lua；新增 tests/lua/business-workflow-view-test.lua。

**Interfaces:** `View.attach(row,record,control,revision)` 仅修改新建 row；workflow.viewRevision 来自 Job revision 或旧记录 generation，steps 只包含标量。

- [x] 添加配方未确认/已确认、部分交付/撤回/改道、版本与行原件不被修改的断言。
- [x] 实现并接入现有 Service，不改变命令 generation 域。

## Task 2：烹饪义务与步骤

**Files:** CookingMonitor.lua、tests/lua/business-workflow-view-test.lua。

- [x] 根据当前 phase、heat/attempt/原件/设备事实动态生成步骤；专门测试无 Session 未结炉具。
- [x] 保留渐进水/流体与未知效果区别，不从 UI 回写记录。

## Task 3：验证

- [x] CN/EN 成对文案、定向 Kahlua 业务/监控/命令/保存回归、编译与静态检查。
- [x] 更新本轮证据及待办；未实机不宣布 PZ 动作或保存恢复验收完成。

## 执行结果

源码与本批替身/构建检查已执行；发布检查、旧迁移与完整页面夹具仍有失败，不代表全部验收通过。详见[本批证据](../../reviews/2026-11-02/workflow-closure-and-monitor.md)。PZ 实机、性能及总体 B.5 未验收。
