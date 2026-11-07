# 农林、清洁与采集领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
FieldProviders组合cleaning/farming/lumberjack/forager真实作业；工具返还由现有归还服务处理，不把所有领域约束强行写成同一业务步骤。

## 2. 数据权威
FieldRecord验证providerType=FIELD_WORK的Job，payload包含target/claims/assets/phase等；不是农田规划数据库。原生对象/植物/物品与工具托管记录分别保留各自事实。

## 3. 现行生命周期
正式phase为PREPARE/WORK/COLLECT/DELIVER/SETTLED，具体动作及是否产生原件由领域目标决定。ToolCustody与工具返还独立，动作结束或退队不等于托管解除。

## 4. 真实接口入口
- `FieldProviders.get(category)`
- `FarmingProvider.discover(env) / claim(...) / advance(env) / reconcile() / hasWork()`
- `FieldWork.advance(env)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Field/FieldProviders.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/FieldProviders.lua)
- [client/EmberRoutesProbe/Field/FieldOperations.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/FieldOperations.lua)
- [client/EmberRoutesProbe/Field/FieldWork.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/FieldWork.lua)
- [client/EmberRoutesProbe/Field/FarmingProvider.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/FarmingProvider.lua)
- [shared/EmberRoutesProbe/Field/FieldRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Field/FieldRecord.lua)
- [shared/EmberRoutesProbe/Field/ToolCustodyRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Field/ToolCustodyRecord.lua)

## 7. 验证入口
按动作选field相关测试及tool-return/public-work接缝；真实种植/液量/产物/交付需原版和实机证据。

## 8. 易错边界
forager类别拼写以FieldRecord为准，不写成foraging；缺工具/原件证据拒绝或留责，不靠背包重造补齐。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
