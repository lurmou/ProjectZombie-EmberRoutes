# 仓储配送重构：实现与验证证据

日期：2026-10-28。初轮配送执行链重构为 0.29.13 工作区源码阶段；后续已授权 UI 局部重构推进到 0.29.14 并生成本地包，未上传工坊。初轮证据与后续 UI 结果分开记录。

## 基线与查证

- 当前安装 `D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/projectzomboid.jar` SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。
- 只读参考 `D:/Project/ProjectRemnants/NPCFW.jar` SHA256：`5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E`。
- 参考 `NPCFW_PartyInventoryUI.lua` 的 `collectTransferEntries → queueTransfer → performTransferRequest → isTransferableItem → transferItemBetweenOwners`：按接收者 `hasRoomFor` 校验、逐件复验原件。参考用 `ISTransferAction:transferItem`，并非可以直接复制其控制协议。本项目沿已存在的 `WorkTransfer` 适配 `ISInventoryTransferAction`，复用其受控队列、停止和实例后置核验。
- 当前原版 `ISInventoryTransferAction.lua` 的 `new/isValid/perform/transferItem` 已核查；单人实际提交后核验原实例所在容器，不能凭 perform 返回算成功。当前 JAR 的 `javap` 确认 `CanSee(IsoMovingObject)`、`getSpottedList`、`setSneaking`、`isPlayerMoving`、负重观察签名；参考当前根 JAR `TargetSelector` 字节码确有 `IsoPlayer.CanSee` 分支；参考的常规可见性先验 `LosUtil.lineClear`，`CanSee` 为其异常回退之一，不能把这个分支误说成唯一观察链。本项目另以 NPC spotted list 限定已观察候选，再用 CanSee 复验。当前安装版 `IsoGameCharacter.CanSee(IsoMovingObject)` 转入其 IsoObject 重载，以 LosUtil 的阻挡结果判断；不据此单独宣称它含视野角/距离或真实发现效果。未把 `_decompiled` 内旧 JAR 当依据。
- `ProbeNpc.stopMask()`：4 是当前原生动作；移动、寻路及家具/休息位另计。交付开始须全部停稳，自己的 PUT 在执行中允许动作位 4，仍拒绝其余位。
- 旧配送实际为 Boot 独立 tick → 自选空闲工人 → 无 Session 移动/姿态 → 直接修改库存 → 远程返箱。新模块已移除这些执行分支及 tick 挂钩。

## 已接通的链路

`WarehousePage → PublicWork.createDeliveryOrder → hauling provider → 公共目录/选择/唯一领取 → Work.assign(DELIVERY) → HaulAgent → TaskRuntime/TaskController → WorkTransfer`。

- Order 在现有世界根保存纯事实和稳定请求者 ID，最多 128 条；容量满时仅回收无 Job 的最早终态历史。请求 ID 在保留的历史窗口中幂等，变更内容拒绝复用。排队授予身体前即持久发布 Job 并取得共享原件声明；失败或保存不会留下没有 Job 的已分配段。
- 配送作为明确的 `DELIVERY` producer、`PLAYER` manifest policy，仍放在现有 HAUL Job envelope，不假装普通仓储终点。原物流 provider 保留，同 category 不重复注册。
- 按真实剩余负重、原件 ID 和单来源分段；每段最多 30 件。发现有界轮转，阻断订单不饿死后续订单；完成一段但仍有未交数量时，同 Job 空手返仓后结束，确保单配送员仍可经正常派工领取下一批。空手回程义务可暂停/恢复，不靠放弃未结原件维持身体占用。
- 玩家至少停下 0.5 秒、同层、可接近、配送员停稳后逐件原版交付；每次原生 isValid/perform 再验移动、权限、容量与同一实例。背包满时原件留在配送员身上，并提示腾空间；单件超过 NPC 最大负重时明确阻断，不丢地。
- 玩家移动目标有节流重规划，跨楼层不把同 XY 当到达。以现有据点区域边界外 50 格为撤回门限；取消、死亡/目标丢失同样进入原件归还。源仓拒收/不可用时沿现有 HaulRouting 找允许仓储；无容量、路径受阻保留责任等待，不远程返箱。
- 据点外的蹲行只消费本 NPC 当前 spotted list 且 `CanSee` 的活僵尸；500ms 有界观察，不使用全局附近列表。缺 API/列表或观察列表超过 64 时停下并显示观察不可用，保留责任，不把未观察完当安全。姿态经 Session 能力授权，停止和终结清除。
- 已确认的逐件交付/退库回执结清共享声明；UNKNOWN 保留 attempt、原件声明及核对状态，旧 Session/世界回调不能重放。订单只统计玩家端点回执，退库不计收货；退休必须先解除订单对 Job 的引用。
- 正常保存沿既有 TaskBusinessStop/TaskPersistence 屏障；恢复先重建同一原件声明再复验。公共 provider 只恢复既有责任，不另开选人或身体循环。普通暂停和自理前任恢复遵循原协议。
- 复用工单监控的等待、执行、暂停、继续、取消入口；已接受需求与送达分开，失败保留购物车，CN/EN 文案同步。

## 实际检查

- 安装版 Kahlua + 原生替身：配送 46 项、公共派工 77 项、既有搬运 R1 26 项通过。配送覆盖容量、三批配送、跨层/移动门禁、观察蹲行、超距/取消返仓、容量受阻唤醒、纯事实新根恢复、排队授予撤回后恢复、迟到回调和 UNKNOWN 留责；公共派工补验证配送与物流同时贡献候选且走同一 provider。
- UI/控制接缝：购物车 42 项、工单监控 26 项、既有控制器 33 项通过。监控验证未分配配送可见、陈旧取消拒绝及退库回执不算收货。
- 原始输出：[业务回归](../../../build/logs/delivery-rebuild-kahlua.txt)、[UI/控制](../../../build/logs/delivery-rebuild-ui-control.txt)、[新增监控](../../../build/logs/delivery-rebuild-monitor.txt)。测试夹具的移动、原版动作和世界对象是替身，不能据此声称游戏内通过。
- 首轮完整 preflight 通过：239 份 Lua，语法 0 错误/4 警告，LuaLS 0 错误/38 警告；无原版整文件替换冲突。末轮完整 preflight 同样通过（239 份 Lua；语法 0 错误/4 警告，LuaLS 0 错误/37 警告），见[完整输出](../../../build/logs/delivery-rebuild-preflight-verified.txt)。随后补改排队授予失效后的 pending 清理、监控 RETURN 阶段映射及下单数值边界（沿用公共下单 9999 总件上限，类型上限 256，与每段 30 原件分开）；对应三份文件定向语法检查零错误/警告，相关业务回归再次通过。CN/EN 1124 键对齐、无重复键。

默认 Git whitespace 检查还将项目现有空格缩进报告为 indent-with-spaces；未批量重排其他改动。仅启用行尾空白/文件尾空白/空格后制表符规则的检查通过（LF/CRLF 提示保留）。

## 尚未验证与旧现场边界

真实跨楼层寻路、动态玩家接近、原版交付动画/声音、蹲行表现、危险抢占、死亡后恢复、正常磁盘保存重进、强退一致性及规模性能未在游戏中验证。不承诺联机、零损失或特定 NPC/尸潮规模。

旧 DeliveryService 只保存内存 userdata，没有可恢复的稳定订单/原件责任记录；此次不提供热迁移或自动认领未知旧携货。物理原件不被删除、重建或远程挪走。无法逐 ID 识别的旧现场仍需核对，不能把新链路通过当作旧现场已修复。


## 0.29.14：配送 UI 局部重构

用户在本会话选择“局部重构：重做清单与反馈，保留现有仓储和工单入口”。[从属设计](../../superpowers/specs/2026-10-28-delivery-ui-design.md)记录范围；在线需求 v4.0 本轮通过 Google Drive 读取，未修改需求。

### 根因与改动

- 当前安装版 `UIManager.updateMouseButtons → UIElement.onConsumeMouseButtonDown` 对中键调用额外鼠标入口；该入口只向 Lua 传按钮号，而且没有对子控件递归派发。给嵌套 Grid/CachedList 设置 wantExtraMouseEvents 不等于能收到事件。此前直接调用加购方法、甚至直接调用 Grid 回调的替身测试都没有覆盖真实分发链；本轮明确补齐这个验证缺口。
- 当前页 update 只读中键状态并检测上升沿，再通过库存控件的原生 isMouseOver/getMouseX/getMouseY、网格 cellAt 或原版列表 rowAt 定位。遮挡/隐藏/弹窗/菜单/滚动条不加购；按住、从外拖入、切页时不重复触发，不注册永久全局回调。不把 JAR 静态分支当成真实鼠标已验收。
- 旧清单加号的绘制与点击区域不一致，按钮只判断 X；长名未使用已计算宽度，容量条被底栏按钮挤压。新清单作为右侧完整面板，左侧分页/刷新独立保留；打开时隐藏详情及重复清单入口，返回后恢复。每行图标/名称与数量/重量分层，绘制和点击共用矩形，纵向命中及滚动偏移一起核对。长名预裁剪，增减后保留选择和滚动位置。
- 移除包裹 emoji、装饰灯和拥挤容量条；沿既有 Theme/字体/Layout。加购即时展开，数量上限、库存核查中及提交失败明确反馈。失败文案优先于容量提示，保留草稿/请求 ID；详情和菜单的“移出”移除整类，Shift+中键仍按步长减少。背包不足不禁下单，继续沿已确认的持货等待规则；结果复用工单监控。
- 版本号、Lua/Java 日志与 mod.info 对齐 0.29.14。Java 业务实现未改；既有构建生成该版本的 BuildInfo/JAR。本地包是当前工作区整体快照，保留已有改动，未发布工坊。

### 实际检查及差额

- 68 项配送 UI 接缝断言通过：活动页输入上升沿、无坐标回调依赖、网格/列表、按住/外拖/遮挡/滚动条、按钮二维命中、数量边界、面板显隐、失败幂等与容量错误优先。原生 UI 和鼠标仍为替身，[输出](../../../build/logs/delivery-ui-input-test.txt)。
- CN/EN 实际安装 Kahlua + AWT 布局预览已生成并逐图查看，包含长名称和容量不足；多字号行布局边界同时检查。预览使用假世界数据与图标占位，不能等同游戏截图：[中文](../../../build/qa/settlement-visual-warehouse-CN.png)、[英文](../../../build/qa/settlement-visual-warehouse-EN.png)。
- 尝试既有完整页签预览夹具时，在人员页的 Public.categories 替身缺口处失败（非本轮配送路径）；未修改该业务页面来掩盖失败，也不宣称完整页签套件通过。配送预览复用其宿主前置夹具并只加载仓储页，见 [原始失败](../../../build/logs/delivery-ui-preview-CN.txt) 与 [独立预览](../../../build/logs/delivery-ui-focused-preview-CN.txt)。
- 既有构建通过，包括基础/载体权威/检查点/安装版编解码等检查；日志明确游戏引擎未运行。[构建输出](../../../build/logs/delivery-ui-build.txt)。完整 preflight 通过，后续输入滚动条门禁及失败提示优先的三个窄改另补定向语法检查与 UI 回归。[preflight](../../../build/logs/delivery-ui-preflight.txt)、[窄改检查](../../../build/logs/delivery-ui-final-lint.txt)。
- release-check 0 错误/7 提示；CN/EN 1138 键一致。最终本地 ZIP 的 254 个文件逐字节与工作区模组目录一致。真实游戏中键、游戏字体/裁剪/图标、不同分辨率及配送动作与保存重进仍未实机验收。
