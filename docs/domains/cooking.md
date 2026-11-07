# 烹饪与厨房领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
烹饪Provider发现/认领/推进COOKING任务，服务组合食材、厨房、水源与交付；UI不驱动物理效果。

## 2. 数据权威
CookingRecord验证统一Job的payload/claims/assets/attempt；不是厨房设施登记表。CookingBudget从同一root.taskJobs.byId派生pending/blocked并经LaborStore准入，没有第二份持久配额账本。厨房/水源以原生实体与当前观察为准。

## 3. 现行生命周期
payload.phase真实值包括PREPARING/FETCHING/FILLING/ADDING/SEASONING/HEATING/UNLOADING/DELIVERING/RETURNING/SETTLED/RECONCILE；不能用通用画图顺序代替Record验证。效果和设施监管可超出某次身体Session，失败不自动承诺食材全退或紧急灭火。

## 4. 真实接口入口
- `CookingService.discover(env) / claim(selected,npcId,jobId,env) / advance(env) / reconcile()`
- `CookingService.command(actor,scopeId,jobId,action)`
- `CookingSupplyService.observe(entry,now,hours,budget)`
- `CookingSupplyService.reserve(entry,job,snapshot,minimum,now,hours)`
- `CookingBudget.open(root,jobs):view(scope) / reserve(job,supply)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Cooking/CookingService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Cooking/CookingService.lua)
- [client/EmberRoutesProbe/Cooking/CookingSupplyService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Cooking/CookingSupplyService.lua)
- [client/EmberRoutesProbe/Cooking/CookingBudget.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Cooking/CookingBudget.lua)
- [shared/EmberRoutesProbe/Cooking/CookingRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Cooking/CookingRecord.lua)

## 7. 验证入口
KahluaLaborTest指定cooking-foundation、cooking-task及对应水源/恢复用例；具体用例名称先核当前tests/lua。

## 8. 易错边界
没有requestBatch/getAvailableStove/getAvailableMeals/getWaterSource这些正式接口。先检查对应服务真实API，不将设计愿景写成已实现能力。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
