# 据点、成员与小队领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
负责据点几何/区域、成员宏观意图、床位与小队行为接线；具体公共工种由Work/领域Provider执行，HUD绘制由UI负责。

## 2. 数据权威
`SettlementLedger.data()`使用`EmberRoutes/Settlements/v1`；成员事实在`ContainerRegistry.data().npcMembership.byNpc`，由MembershipService独写。`leaderId/followSlot`是活动FOLLOW授权；`squadLeaderId/squadSlot`是持久小队名单。SquadPreferences仅角色ModData.EmberRoutesSquadHUD的布局/显示排序/缩放/呼号，不保存编队、战斗配置或业务事实。SquadService只是展示会话与命令提交门面。

## 3. 现行生命周期
成员context为WAIT/FOLLOW/RETURN/SETTLEMENT；request按revision接受pendingCommand，MembershipRuntime停止当前身体、核对原件义务后advance提交。WAIT/RETURN/自理保留小队名单，DISMISS变WAIT并退出小队但保留据点/原件责任。RETURN只有实际抵达才转SETTLEMENT。退休清会话名单，未结责任不因死亡清除；不虚构STRANGER/INVITED/inSquad状态或战斗最高抢占权。

## 4. 真实接口入口
- `MembershipService.view(id)`
- `MembershipService.request(actor,id,command)`
- `MembershipService.advance(id,actor,obligations,bodyOwned)`
- `MembershipService.squad(actor)`
- `MembershipService.followSlot(id,actor,expected)`
- `MembershipService.configureBed(actor,object,current,mode,npcId)`
- `SettlementZones.list(scope) / get(id) / save(actor,scope,id,expected,proposal)`
- `SquadService.new(actor,owner) -> session:refresh(now), targets(selected), command(targets,kind,slot), close()`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Settlement/MembershipService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Settlement/MembershipService.lua)
- [client/EmberRoutesProbe/Settlement/MembershipRuntime.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Settlement/MembershipRuntime.lua)
- [client/EmberRoutesProbe/Settlement/MembershipBeds.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Settlement/MembershipBeds.lua)
- [client/EmberRoutesProbe/Settlement/SettlementLedger.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Settlement/SettlementLedger.lua)
- [client/EmberRoutesProbe/Settlement/SquadPreferences.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Settlement/SquadPreferences.lua)
- [client/EmberRoutesProbe/Settlement/SquadService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Settlement/SquadService.lua)
- [shared/EmberRoutesProbe/Settlement/MembershipPolicy.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Settlement/MembershipPolicy.lua)

## 7. 验证入口
KahluaLaborTest指定membership-command、membership-runtime、membership-slot-menu、membership-save-lifecycle、squad-command-ui、squad-preferences及companion-handoff用例。

## 8. 易错边界
显示排序不是编队槽位；命令接受不等于执行完成；床位由MembershipBeds观察/认领/释放，Lifecycle负责安装事件，不是床位状态的第二权威。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
