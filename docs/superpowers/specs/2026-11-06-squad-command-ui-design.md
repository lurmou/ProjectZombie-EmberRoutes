# 最小小队 HUD 与指挥轮盘设计

状态：执行用户确认的“小队 HUD、轮盘先行”范围；单人、最多三名、用户实机。

## 目标与契约
HUD 常驻左上，展示三名同伴的姓名/头像、生命、宏观命令、实际活动、阻碍与本次命令回执；单选、Shift 多选、全选。按钮与原版 ISRadialMenu 接入 FOLLOW、WAIT、RETURN、单人槽位选择、移出小队。没有选中成员时明确以全队为目标。无成员显示加入提示，不加入未实现的战斗/载具按钮。

成员行新增成对 `squadLeaderId/squadSlot(0..2)`：FOLLOW 提交写入；WAIT、RETURN、自理保留；DISMISS 提交变 WAIT 并清除小队字段，保留据点归属与资产责任。活动 `leaderId/followSlot` 仍仅 FOLLOW 存在。持久名单占槽，pending FOLLOW 预约新槽；只按显式槽排序。旧 FOLLOW 缺新字段只拒绝保留，不迁移、不升 format、不动检查点。无小队字段的 WAIT/SETTLEMENT 合法。

新增 DISMISS 沿用 MembershipService.request/advance 及 MembershipRuntime 的停止、原件交接流程，不能由 UI 直接释放身体或责任。创建认领在 MembershipService.advance 与 TaskController.attachDriver；正常释放经 TaskController.stopOnce；异常退出经 MembershipRuntime 与 MembershipService.retire。派生 UI 缓存允许最终一致，身体独占维持当前契约。

## 结构与生命周期
MembershipService 是唯一持久权威；SquadService 返回最多三人的展示快照与逐人请求结果。复用 LaborSignals，活动视口每500ms补读无事件的实际活动/生命；脏事件最快100ms补读，隐藏停止刷新。名单索引仅成员改变/换世界重建。PersonnelService 的头像缓存共享，但小队访问单独校验名单权限，不放宽原据点查询。
SquadHUD 复用 Theme/CardPanel/PageLifecycle，渲染只读预投影文本和布局，无实体扫描、测量、拼接或 table 分配。每次显示建立 activation scope；隐藏、死亡、换世界释放订阅、头像 ownership 与轮盘。命令目标捕获稳定 ID/版本/槽位；过期反馈拒绝，群令独立成功或失败，不伪装原子操作。

轮盘用自有 ISRadialMenu 实例，按钮点击选择或按住键松开执行当前扇区；释放一次、过期 token 无效、不清原版共享轮盘。默认句号 Period（原在线需求 R 与原版装填冲突，当前阶段用可配置原生键位）；右键 EmberRoutes 菜单可重新显示 HUD。首版不支持手柄/分屏。

## 参考与战斗研究边界
在线唯一需求 2026-11-06 已读取：§7.7 指挥、§11.3 三人 HUD。参考 NPCFW_PartyRadial/PartyCommands 的目标快照、重验、按键与轮盘占用；不迁入独立控制器。
已追踪当前 NPCFW.jar 的 NPCBehaviorTreeBuilder、IsoNPC.tickAI、MeleeCombatNode、RangedCombatNode、CQBMode，以及 Lua NPCFW_RangedActions.requestFire 的实际攻击与效果调用。参考有目标认领和装填掩护，但缺少同场景效果/性能证据，不能称最佳。后续战斗先近战完整闭环，再远程射击/装填，再协同；Stance 与 ROE 正交；继续由现有身体会话仲裁。当前 FOLLOW_ACTION_BUSY 与移动停止语义必须在战斗设计中单独处理，不用 UI 暗示战斗已实现。

## 验收
定向逻辑：WAIT/RETURN名单保留、占槽/预约、取消、移出与原件阻断、读档不修复、群令部分拒绝、旧目标过期、隐藏清理及松键单发。构建与 CN/EN 对称。实机由用户测三人选择、转命令、自理交接、保存重进、轮盘与原版共存、字体缩放；静态/替身检查不代替实机。

实现与静态/替身证据见[验收记录](../../reviews/2026-11-06/squad-hud-foundation.md)，实机仍开放。

## 基础 HUD 补全（用户于2026-11-06批准）
对照NPCFW_PartyUI/PartyPortrait完整交互，补充：HUD拖动与归一化位置保存；显示顺序拖排保存（不改squadSlot/followSlot）；布局缩放与按钮尺寸各自选档；窗口/字体/分辨率改变时重新布局与屏幕限界，小屏卡片区滚动；悬停完整姓名/命令/状态、hover高亮；呼号编辑/清空保存；高/中/低血量语义色；最多两个原版状态徽章及完整tooltip；卡片右键接现有指挥命令及呼号。基础菜单提供恢复默认布局。
偏好放角色ModData.EmberRoutesSquadHUD，format=1，只有显示参数/order/callsigns，不是业务权威。不迁移旧格式，未知偏好格式保留并拒绝写入；默认只读视图可用。列表只存稳定NPC ID；离队卡片移除时清理选择/拖动/提示，拖排不发Membership命令。状态按现有500ms观察读取九种Moodle、显示前两个，其余保留tooltip；不每帧扫描。
HUD拥有tooltip、contextmenu与呼号dialog，activation失效/关闭/换世界全部清理；保存呼号与菜单回调也受token门禁。复用Theme、CardPanel、SemanticBadge、Viewport、TooltipManager；原生ISContextMenu和ISTextBox。只读render，不在render测量、拼接、构造表或观察角色。UI尚未实机验收。

基础补全的实施和验收边界见[0.29.53记录](../../reviews/2026-11-06/squad-hud-foundation.md)及[实施计划](../plans/2026-11-06-squad-hud-foundation.md)。
