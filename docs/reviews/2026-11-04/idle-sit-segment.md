# Idle fallback sit-first segment

基线：`phase-3a-consolidation` / `59c7944`。授权：用户本轮指令及 `~/workspace/goals/emberroutes-npc-realism/files/idle-sit-brief.md`。在线唯一需求读取失败，未宣称同步。沿用 [NPC 唯一架构](../../superpowers/specs/2026-10-22-npc-behavior-architecture-design.md)，不改变身体/资产权威；未提交、未推送。

## 行为与预算

仅普通 IDLE、无候选选中时，在原 ambient OBSERVE 前尝试现有 seekSit。决策暂停、非 IDLE 的 brief OBSERVE、活动出席和 cut-2 resumeHint 均保持原路径。

普通 SIT seek 使用调用方共享扫描预算，允许推进共享设施发现，并跨轮保留比较迭代器。新增回退使用独立 `scan=8`、独立 offer.ambientSit 状态；复用 ReposeSites.new 的 indexedOnly 选项，只检查缓存索引前至多 8 条记录，不调用 Facilities.advance，不保留未完成迭代器。限定同层、4 格距离、seatingOnly/excludeBeds；选择本次有界比较中的最佳座位。不是穷尽周边座位的保证：索引未发现、前八条均较远或近座位位于更后记录时，立即保留 OBSERVE。失败沿用 seatRetryMs（60 秒）与设施版本/位置/seatEpoch 唤醒，不逐 idle tick 全设施扫描。

入口仍核对安全/需求、成员/据点资格、SIT Policy.allowed、SIT cooldown、原点区域与 standable、moveAfter，准备后核对座位目标区域。返回普通 SIT，没有 ambient 标志，沿用正常冷却、seatPreference、移动间隔与释放语义。标记 moving=true，因为该回退经家具移动适配器到位；无传送，无新家具或搜索系统。

## 代码闭环证据

以下路径均相对仓库根目录：

- 创建/准备：`Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/LeisureService.lua:635–646` 独立回退环境；`:271–274` 仍由 `Sites.prepare` 生成标量 proof（id/partId/revision/parts/key/settlementId）和 `Sites.keys(...,'REST')` 声明键。prepare 本身不取得声明，普通 SelfCare 接受候选后仍由既有 claimPersonal 仲裁。
- 座位权限：同目录 `ReposeSites.lua:169–182` 检查真实占用和资源 owner；`:226–243` prepare 重验原对象/策略/成员，再 resolve；`:305` 预算结束立即返回本段比较结果。普通扫描未设置 indexedOnly，行为不变。
- 执行：同目录 `LeisureActions.lua:10–12` 仍为 SelfCareFurniture.move(c,'REST') + LeisureSit.new(c)，原生到位和姿态不新增旁路。
- 正常与异常释放：同目录 `SelfCareExecution.lua:112–158` 的 finish 在效果已知、义务结清及持久化成功后通过 Store.finishPersonal 释放；`:257` 起 stopAdapter 负责请求停止、观察停止与持久事实。LeisureService.finished 继续维护正常 SIT 的记忆/偏好；身体未知不能被本轮回退直接释放。

## 定向验证

`lua tests/lua/idle-sit-boundary-test.lua`：通过 52 项本段检查，复用家具夹具另通过 26 项。脚本自带仓库 client/shared package.path；真实 LeisureService、ReposeSites、Policy、TaskJobs、LaborStore、SelfCareExecution，游戏身体与共享设施观察为替身。

覆盖普通预算为零仍返回正常 SIT、有效序列化 proof/claim key、实际 claimPersonal 认领、第二 NPC 拒绝、已准备但尚未启动身体动作的 SIT 在需求中断收尾后释放、释放后可重新选座；无座、超过八条索引上限、距离/层、床、占用、专属策略、SIT Policy/cooldown、moveAfter、安全、非 IDLE、原点不可站立及区域禁用回退。此项停止测试不冒充正在播放坐姿动画的原生起身验收。

变更 Lua 逐份 `luac -p` 和 `git diff --check` 通过。未跑全量回归。工作区没有 `.workbuddy/tools/pz.mjs` 文档检查入口，未运行项目 doclink。

## 社交取舍与未验证

cut-3 仍为 idle-only、OBSERVE-only：SIT 不满足 SocialCoordinator.available()，更多 NPC 坐下可能降低可配对人数与形成频率。本段不扩大 seated social，不改形成逻辑；扩大范围需要单独用户决定。

UNVERIFIED：游戏内坐姿动画、原生到座寻路、真实磁盘 mid-sit 保存/重载、游戏性能、实际社交频率变化。没有实现阻塞；有界缓存前缀可能漏掉附近可用座位是明确接受的即时 OBSERVE 回退限制，不承诺完整邻域发现。
