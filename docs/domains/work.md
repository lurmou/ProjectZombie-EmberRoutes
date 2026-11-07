# 公共工作与工种调度

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
PublicWork负责资格、候选发现/选择、目录认领与Provider组合；领域负责内部物理步骤/效果/原件，不把所有工种塞进同一通用状态机。

## 2. 数据权威
原件与资源声明由client/Work/LaborStore及领域记录管理；JobStore/TaskJobs统一Job封包，TaskDirectory只是可重建候选。没有独立EmberRoutes_LaborSchedule存档键这一约定，实际配置由PublicWork.data等源码定义。

## 3. 现行生命周期
PublicWork构造envDiscover并调用discover；选择候选后自己生成jobId并directory:claim，再调用领域claim。QUEUED/STARTED接手，拒绝在未接手分支处理；领域持续推进/核对并凭KNOWN且义务清偿证明释放目录。未知效果、死亡或会话消失留责而非无条件release。

## 4. 真实接口入口
- `PublicWorkProviders.register(def) / get(category) / all()`
- `provider.discover(envDiscover)`
- `provider.claim(selected,npcId,jobId,env)`
- `provider.advance(env) / reconcile() / hasWork()`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Work/PublicWork.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/PublicWork.lua)
- [client/EmberRoutesProbe/Work/PublicWorkProviders.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/PublicWorkProviders.lua)
- [client/EmberRoutesProbe/Work/LaborStore.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Work/LaborStore.lua)
- [client/EmberRoutesProbe/Field/FarmingProvider.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Field/FarmingProvider.lua)
- [client/EmberRoutesProbe/Hauling/HaulingProvider.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Hauling/HaulingProvider.lua)
- [shared/EmberRoutesProbe/Kernel/TaskDirectory.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Kernel/TaskDirectory.lua)

## 7. 验证入口
KahluaLaborTest指定public-work、multi-worker、tool-return及相应Provider用例；类别中英文成对，运行check-i18n/check-architecture。测试所需原版依赖替身必须符合生产契约。

## 8. 易错边界
注册表只校验category/defaultPriority，没有强制五个统一桩全部实现。discover通过env发布而非返回候选数组；不能把reconcile(jobId,outcome)或无条件目录释放写成正式协议。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
