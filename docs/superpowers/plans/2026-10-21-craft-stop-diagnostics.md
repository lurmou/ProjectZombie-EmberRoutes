# 制作启动停止：定向排障计划

> 2026-10-21｜用户已批准补齐具体原因并修复已确认输入框错误；主代理独立执行。

**Goal:** 把实机的NATIVE_ACTION_STOPPED定位到具体动作和拒绝条件，不凭平台附近的位置猜测根因。

**Architecture:** 保留现有分类仓储、认领和恢复协议；在原有动作适配边界记录阶段及首次拒绝原因。原版配方拒绝与输入实例不匹配分开；仅在停止时记录原件、位置和容量，不每帧输出。不放宽原版检查、不强制制作。

**Tech Stack:** 当前PZ42.21.0安装Lua/JAR，既有Kahlua定向夹具。

- [x] CraftRecipeAdapter返回输入检查失败的具体原因；CraftProbe区分转移/制作、记录首次拒绝与有限诊断快照。
- [x] 按当前ISTextBox签名修复NpcDebugMenu参数：target传actor，player传actor:getPlayerNum()，param1传npc。
- [x] 仅运行制作相关检查及必要preflight，核对新诊断日志；更新接力、版本和包。

历史实机证据：console.txt中17:14:21及17:15:18均NATIVE_ACTION_STOPPED、uncertain=false，无COMMITTING；该证据不能单独证明距离、原版配方或动画哪项拒绝。新诊断仍需下一次实机触发，不能宣称停工根因已修复。
