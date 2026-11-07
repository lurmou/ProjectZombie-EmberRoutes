# 日程与社区活动领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
ActivityService管理活动配置/偏好上下文，ActivityAttendance核对参与准入，场景/个人动作仍由各自会话执行。

## 2. 数据权威
ActivityStore保存活动数据；参与Job的ActivityRecord保存eventId/controlEpoch/participantEpoch及step。活动配置、参与事实与身体Session互相分离。

## 3. 现行生命周期
参与记录step为INVITED/WAITING/FREE/PERSONAL/LEAVING/SETTLED；FREE上下文可在短到达会话退出后继续，不把活动结束等同于强制结束一切个人责任。

## 4. 真实接口入口
- `ActivityService.preview(actor,args,deferred,current) / start(actor,args,token)`
- `ActivityService.update(actor,id,expected,args,token) / cancel(actor,id,expected)`
- `ActivityAttendance.inspect(actor,id,ref,careId) / request(actor,binding,ref) / blocksOrdinary(id)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Activity/ActivityService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Activity/ActivityService.lua)
- [client/EmberRoutesProbe/Activity/ActivityAttendance.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Activity/ActivityAttendance.lua)
- [client/EmberRoutesProbe/Activity/ActivityStore.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Activity/ActivityStore.lua)
- [shared/EmberRoutesProbe/Activity/ActivityRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Activity/ActivityRecord.lua)

## 7. 验证入口
运行activity相关准入、epoch、暂停/结束定向Kahlua。

## 8. 易错边界
不虚构getCurrentPhase/triggerEvent/isExempted/findSocialPartner接口或已验证的全员战斗避难能力。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
