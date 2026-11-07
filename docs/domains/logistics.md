# 仓储、搬运与配送领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
Warehouse观察真实容器与过滤规则；Logistics管理配送意图/订单；Hauling执行真实物品转移。三者并非共享一个虚拟库存。

## 2. 数据权威
物品以原生容器内实例为权威，登记/策略由ContainerRegistry及StorageFilter处理；HaulJobRecord/Manifest保留业务事实，具体存储入口见各data方法，不虚构全局EmberRoutes_StorageFilters键。

## 3. 现行生命周期
配送订单发现候选、认领后经搬运执行、观察实际到达与交付。载货中取消/容器变化继续按现有业务保留或返还原件；记录缺失不证明清偿。HaulingProvider.reconcile展示正常释放与缺记录留责两个分支。

## 4. 真实接口入口
- `DeliveryService.createOrder(actor,scope,items,requestId,destinationId)`
- `DeliveryService.cancel(actor,id,revision)`
- `LogisticsService.publicOffer(actor,entry,npc)`
- `StorageFilter.matches(config,item)`
- `WarehouseQuery.new():page(rows,search,category,page,sort,anchor)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Warehouse/ContainerRegistry.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Warehouse/ContainerRegistry.lua)
- [shared/EmberRoutesProbe/Warehouse/StorageFilter.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Warehouse/StorageFilter.lua)
- [shared/EmberRoutesProbe/Warehouse/WarehouseQuery.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Warehouse/WarehouseQuery.lua)
- [client/EmberRoutesProbe/Logistics/DeliveryService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Logistics/DeliveryService.lua)
- [client/EmberRoutesProbe/Hauling/HaulingProvider.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Hauling/HaulingProvider.lua)
- [shared/EmberRoutesProbe/Hauling/HaulJobRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Hauling/HaulJobRecord.lua)

## 7. 验证入口
指定delivery、batch、storage-panel、warehouse与搬运原件用例；只读UI缓存与实际转移效果分开验收。

## 8. 易错边界
WarehouseQuery是展示行筛选/分页，不是findAvailableItem认领服务；没有requestDelivery/matchesFilter这组门面。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
