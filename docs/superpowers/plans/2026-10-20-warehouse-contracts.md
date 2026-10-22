# Warehouse Contracts Implementation Plan

> 主代理按顺序实施；项目规则禁止未经请求安排并行代理。用户已批准范围，无需重复审批。

**Goal:** 收口物理端点和只读候选契约，消除盘点末尾无预算工作与通知饥饿。

**Architecture:** Registry负责身份/权限/复验；Index负责共享作业/事件；纯Rollup负责有预算合并与排序。候选返回副本，执行仍验证原资产。

**Tech Stack:** PZ42.21.0当前安装Lua/JAR、Kahlua、SP GlobalModData。

**Spec:** [设计](../specs/2026-10-20-warehouse-contracts-design.md)

## Global Constraints

不替换原版动作、不重建物品、不实现MP或预留。原ID和主格记录兼容，最大256容器/20000物品/2048类型，每推进总预算128。通用文案复用原版，新增状态CN/EN成对。

## Review Focus

旧记录无索引/类型；已载对象被移除或同ID重复；通知触发于读取/归并中；消费者关闭或切世界；部分未加载库存不能视作完整可用量。

### 1 物理端点契约

- [x] 在tests/lua/settlement-storage-test.lua增加旧记录、非法索引、旧端点替换与通知定位测试并确认失败。
- [x] ContainerRegistry.lua实现describe(id)、revalidate(endpoint,intent,scopeId)、affected(object)；Work.lua复用复验；resolve不再把缺失副格默认主格。
- [x] 跑现有仓储与Work回归，保留测试替身/实机区别。

### 2 分片汇总与调度

- [x] 新增shared/EmberRoutesProbe/WarehouseRollup.lua：new(ids,results,maxItems,maxTypes)、step(budget)返回spent/state/reason，实例保存rows/counts/byType。
- [x] 测试每步总工作量、重复ID、类型超限、空仓、反序多类型归并排序，并确认旧实现无法满足分片要求。
- [x] Index移除同步materialize，读完贡献后用Rollup；游标找脏项、15/60通知合并、8次中断上限。已发布索引随失效立即清空，关闭释放归并引用。

### 3 统一候选查询与交付

- [x] Index.candidates(actor,id,{fullType,origin?,limit?})：Ledger.view重验，结果含state/revision/coverage/complete/knownCount/sources；每项稳定id/XYZ/count及可选distanceSquared；排序距离相同时按id。
- [x] 增加候选副本隔离、更新中拒绝旧候选、部分完整性、范围拒绝与精确类型索引测试；运行真实Kahlua CN/EN和原Work回归。
- [x] 更新架构、测试、待办、基线证据，构建0.9.0；preflight、release-check、doclink及包源码一致性检查；正常保存重进/帧耗记待实机。

不创建提交：本工作区仍有用户未追踪内容；不为流程自动提交所有文件。设计与计划已自查本轮授权、边界和对应验收。
