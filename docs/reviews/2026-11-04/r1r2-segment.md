# R1 + R2：IDLE 回退与轮转座位窗口

基线：`phase-3a-consolidation` / `d04c6f9`，编辑前 `git status --short` 为空。授权来源：本轮 `r1r2-brief.md` 与用户已决定的 open question 1 修订；沿用 [NPC 架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)。本轮是既有批准范围实施，未重新同步在线需求。不提交、不推送。

## 实现与已决问题

R1：普通 IDLE 无候选时，顺序为 SIT → STROLL → ambient OBSERVE。SIT 原入口与准备路径保持。SIT 未返回候选后，才尝试本决策尚未检查的四个 cardinal 2-tile 点，每点最多一次，至多返回一个 STROLL。正常随机方向即使不可站立或目标被禁用/blocked，也记录为已检查；共享 scan 已耗尽时，fallback 可从四方向开始。

这是 **fallback-only 的既有 2-tile 构造扩展**，不是 normal selection 行为变更：正常选择仍只取一个随机方向、消耗一次 scan，权重、冷却、时长均不变。fallback 的额外检查上限为四点（已有普通方向时至多三点），不消耗或增加普通共享扫描预算。每个 fallback 候选仍要求 Policy.allowed('STROLL')、STROLL cooling、moveAfter、目标 zone rule、standable、blocked targetKey 全通过；decision pause、needs/safety、IDLE 与非 gathering 门禁在外层生效。不能救回 cooling-blocked、needs/safety-blocked 或 all-directions-unstandable 的情况。复用原 STROLL 的移动加 strollMinutes 等待，无动作链重启或漫游循环；结束后仍交还正常仲裁。

R2 / open question 2：选用数值 `offer.ambientSit.offset`（下次起始槽位，默认 1）。同时沿用该状态的 `stamp`、`retryAt`，没有持久迭代器或新缓存。每次实际 SIT attempt 最多检查八条记录（false 墓碑槽位同样占预算），尾窗口到尾部即结束，下次从 1 开始；缩短列表时 modulo 归一化。`ReposeSites.step` 第四返回值提供下次 offset，fallback 保存标量后丢弃 iterator；普通 SIT 未传 offset/indexedOnly，仍保留原跨轮 iterator 行为。

依据：`SettlementFacilities.lua:58–88` 的 commit 保留对象槽位、复用 free 槽位，并在每次发布后递增 row.version。不存在无版本通知的槽位重排，因此不需要 record-key 遍历。`LeisureService.lua:293–311` 以 facility.version / seatEpoch / floor(x):floor(y):z 组成 stamp，变化时重置 cursor，并沿用原有 retry 唤醒；位置 stamp 不是每个亚格位移。持续设施变更可能反复重置，故仅承诺稳定 stamp 下逐窗口覆盖，不保证任意动态缓存下的发现延迟。

Open question 3：失败 SIT 仍设置 `now + Config.seatRetryMs`（60000 ms）。STROLL / OBSERVE 不清空、不推进该时钟或游标；期限前 seekSit 直接返回，期限后实际扫描下个窗口。stamp 变化仍按原逻辑提前唤醒。STROLL 的真实移动若改变位置 stamp，会按要求重置窗口；这不是新设的时钟。offer 属于世界内观测状态，标量跨决策保留，不代表新增磁盘持久化。

同层、四格、seatingOnly/excludeBeds、占用/专属/声明、Sites.prepare 与 REST keys 均保持。未改 job submission、commitment、settlement、lifecycle、HAUL、其他 DEC-003 领域、DEC-004、商队、Java、resumeHint 或社交代码。

## 代码闭环证据

路径前缀：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`；均为本次 diff 的源码位置，未改的调用方只作证据。

- 创建/准备：`LeisureService.lua:689–700` SIT-first；`:702–720` fresh-point fallback；`:312–322` 继续 `Sites.prepare` 与 `Sites.keys(proof,'REST')`。proof 为 id/partId/revision/parts/key/settlementId 标量记录，不持有新身体控制权。`ReposeSites.lua:209–221` 在准备时重验对象、权限、成员、占用。
- 认领：`SelfCare.lua:316–324` 既有 `Store.claimPersonal(job)`，没有旁路新声明路径。`ReposeSites.lua:223–313` 仅发现候选并输出下窗游标。
- 正常结束：`LeisureActions.lua:84–107` 仍为现有 move + timed wait；SIT 仍在 `:10–12` 使用家具移动/LeisureSit。`SelfCareExecution.lua:130–155` 仅在已知效果、义务结清且持久成功后 finishPersonal 释放。STROLL 不声明座位。
- 异常打断：`SelfCareExecution.lua:251–282` 的 persistFailure/stopAdapter 仍停止树、清理身体并观察事实，再进入相同 finish；未知效果不会被本轮视为完成。`LeisureService.workReady` 原有停 Job 路径不变。真实已认领座位的第二 NPC 拒绝、准备后中断释放及重新可用由原 idle-sit 定向回归验证；不等同于动画播放中的实机起立验收。

## 实际验证

以下脚本运行前均设置：

```sh
export LUA_PATH='Contents/mods/EmberRoutesProbe/42/media/lua/client/?.lua;Contents/mods/EmberRoutesProbe/42/media/lua/shared/?.lua;;'
lua5.4 tests/lua/r1r2-fallback-test.lua
lua5.4 tests/lua/idle-sit-boundary-test.lua
lua5.4 tests/lua/p35-sit-test.lua
lua5.4 tests/lua/p35-social-test.lua
lua5.4 tests/lua/seated-social-segment-test.lua
```

- 新增 R1/R2 定向：69 项，通过；复用家具夹具另 26 项。
- idle-sit：原文件未改，52 项 + 家具 26 项，通过。
- p35-sit、p35-social：两脚本通过（原脚本未输出断言总数）。
- seated-social：138 项 + 家具 26 项，通过。
- 三份新增/修改 Lua 逐份 `luac -p`、`git diff --check` 通过。没有跑全量回归。
- 新定向覆盖顺序、新点救回原方向不可站立/blocked/zone-zero、每点最多一次、冷却/需求/安全/移动/暂停/区域/工作门禁、全方向失败、后窗座位、60 秒边界、STROLL/OBSERVE 不绕过重试、回绕/缩短与三种 stamp 重置。
- 项目 `.workbuddy/tools/pz.mjs` 在本环境不可用，项目 doclink 未运行；本轮 Markdown 相对链接另作存在性检查。

UNVERIFIED：游戏内 STROLL 移动与原生寻路、坐姿动画与到座原生寻路、真实磁盘 mid-STROLL / mid-sit 保存重载、游戏性能、社交频率。宿主替身结果不代替这些验证；未测量性能收益。没有停止的实现 blocker。
