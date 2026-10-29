# P3.5 闲暇重构实施计划

本会话直接执行，不启用子代理。用户已审阅路线并连续要求开始，按当前授权完成设计、计划、实现与必要验证。

**Goal:** 在0.27.0驻扎契约上交付可靠的闲暇启动、有界选择、退避、真实姿态和可见原因。

**Architecture:** Membership提供资格，PublicWork提供短期只读工作观察，SelfCare共享预算仲裁，统一TaskRuntime独占身体；不另建调度器或资产账本。

**Spec:** [P3.5设计1.2](../specs/2026-10-24-p3.5-leisure-social-fitness-design.md)，[唯一架构](../specs/2026-10-22-npc-behavior-architecture-design.md)，[成员接口](../specs/2026-10-25-npc-settlement-membership-design.md)。

## 约束与重点

保留所有混合工作区修改；不改驻扎身份语义；动作停止、原件责任、UNKNOWN、保存屏障不可绕过。观察未知时只允许原地无资源短活动。命令/成员版本失效仍立即拦截。SIT需同时通过记录校验、原件预约与真实姿态，不以候选日志认定启动。未实机不能宣称玩法通过。不扩展多人聚会、坐姿阅读或宏观离线。

## 执行组

- [x] 1. 修记录准入并增加真实Record验证的SIT回归；建立独立工作观察/闲暇诊断接口，PublicWork发布READY/IDLE/OBSERVING，SelfCare不再等待offer。
- [x] 2. LeisureService收集有限候选，慢发现不阻断；Policy比较距离/收益/最近活动，冷却按活动区分，目标失败退避；Study未完成不阻塞低成本观察。更新旧链序金样本，保留版本/预算验证。
- [x] 3. 工作启动失败退避与workReady防抖；社交只接受当前可用者，选择其他活动撤销广告/闲置配对；启动失败原因进入投影。
- [x] 4. 查当前原版ISRestAction/路径原语，接同Session姿态适配及退出停稳掩码；观察/散步合理时长；成对翻译与人员/监控投影。
- [x] 5. 运行受影响Kahlua、CN/EN UI、Java构建、preflight、doclink；按实际风险补测；递增版本、证据、BACKLOG及单份验收，不宣称实机与性能通过。（结果见[开发证据](../../reviews/2026-10-25/p35-leisure-refactor.md)）

## 主要接口与文件

LeisureService.workState(id,entry,state)只接收工作观察，status(id)返回标量副本；candidate仍返回候选/done/reason。候选携带membershipRevision/settlementRevision及目标身份。PublicWork只在真实预检可用时请求收束；失败执行在原重试表内退避。SelfCare记录拒绝/启动/结束，不建新持久化当前活动。

修改LeisureService/Policy/Config、SelfCare/Record/Execution、PublicWork、SocialCoordinator/Actions、PersonnelService/OrderMonitor投影；姿态新LeisurePosture复用Java控制桥。测试在tests/lua/p35-*及public-work等相关夹具，输出build/logs/p35-refactor-*。

验证命令沿用java --class-path 安装目录/* tests/java/KahluaLaborTest.java；node ../.workbuddy/tools/pz.mjs preflight Contents/mods/EmberRoutesProbe；tools/build-probe.ps1（实际入口开工时核对）。初始在线v3.3本轮成功读取，未写在线需求。实施计划作为续接步骤，不另建需求来源。
