# UI 导航分组 Slice 1：实施与验证

2026-11-04；基线 phase-3a-consolidation / b9da0f2 / 0.29.38，接手工作树干净。只实施用户指定简报 Slice 1；未实施整体 UI 设计的后续切片。字段归属见[唯一段表](../../superpowers/specs/2026-11-04-ui-field-authority.md)。未重新读取或宣称同步在线需求，本轮依据用户明确批准的执行简报。

| 主组 | 组内页面 | 首次进入默认 |
|---|---|---|
| 据点 settlement | activities、defense | activities |
| 仓储 warehouse | warehouse | warehouse |
| 人员 personnel | personnel | personnel |
| 工作 work | demands、orders、policies | demands |

logistics、crafting 保持 `parentTab=orders`、`isTab=false`，group 明确为 work，按父页归组。仍可从既有业务入口直达；工单按钮保持父级高亮。

## 导航与生命周期契约

- 顶栏改为组行＋当前组页行。`isTab=true` 现在表示组内页按钮，不再表示七个全局平级入口。activity-page-test 的 first-class 断言有意改为据点组内页断言，未删除用例。
- 新窗口未指定 tab 时仍默认仓储；明确 tabId 优先，不被组默认覆盖。工作组首次进入需求；窗口内每组记忆最近成功激活的叶页，包括物流／制作子视图。关闭不持久化这些记忆。
- 同窗无 tab 的重新打开保留当前页（原为强制仓储），明确 tab 则直达。PageUp/PageDown 有意改为当前组内循环；子视图先返回 orders。组切换使用组行按钮。
- `selectTab(id, context)` 返回成功布尔或失败原因；`open(actor, settlementId, tabId, context)` 透传定位，失败不返回成功面板。context 本刀只允许一个非空字符串或数值稳定标识：npcId、orderId、problemId、itemId、zoneId，不接受实体与命令参数。后两类未实现定位，不据此宣称能力已闭合。
- 先经只读 Service 快照核对目标，再沿旧切页顺序 deactivate / hide → activate / show。激活后从实际 Store 快照选中，不改任何 ID。目标在激活时消失则 deactivate 目标、重新激活原页，组记忆不被失败目标覆盖；不静默跳到其他条目。
- 异常不自动强制切组；没有通过清空页面选择掩盖监听残留。没有新增生命周期、后台刷新或渲染投影。

代码定位（客户端根为 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/`）：

| 环节 | 位置与数据契约 |
|---|---|
| 分组与上下文白名单 | UI/PageRegistry.lua:83–115；每个注册项 group，子视图沿 parentTab 查组 |
| 创建与激活 | SettlementDashboard.lua:134–170；pages[id] 仍为窗口拥有的惰性页面，activeTab 唯一 |
| 正常切出与关闭 | SettlementDashboard.lua:158–161、231 起；旧页 deactivate，关闭逐页 dispose 并释放两行按钮 Tooltip |
| 异常打断 | SettlementDashboard.lua:171–176；激活关闭门禁及目标消失回退；PageLifecycle 的 activation token 保持原实现 |
| 人员定位 | UI/PersonnelPage.lua:302–321；Crafting.status workers[].id → 激活后的 enriched workers[].id → Store.selected / 矩阵选中 |
| 工单／需求定位 | UI/OrderMonitorPage.lua:133–156；orderId → 现有行 id，或 problemId → 需求行 id；Store.selection，必要时切换已有过滤器以展示目标 |
| 原有释放 | UI/PersonnelPage.lua:339、347；UI/OrderMonitorPage.lua:280、289；PageLifecycle 不改 |

## 上下文闭合与 open 项

已闭合：人员 `npcId`；工单 `orderId`（覆盖现有行键与工单 ID 不同的情况）；需求 `problemId` 精确匹配 DemandMonitorService 已提供的问题行 id。使用现有选择与滚动接口，无手动指派。

Open：仓储按实例 itemId、区域按 zoneId 无对应现成选择机制；需求按 npcId／orderId／itemId／zoneId 的关联解析也未提供，不猜测或构造问题关联。没有接入新的跨页业务按钮。失败返回 `CONTEXT_UNSUPPORTED` 或 `TARGET_NOT_FOUND`，保留原页；未知页、隐藏页、非法上下文也明确拒绝。

## 定向验证

宿主为标准 Lua 5.4.8，执行时 `unpack=table.unpack` 适配旧 Lua 全局；LUA_PATH 指向本仓库 client/shared。ISUI 与业务服务为替身，生产 Dashboard、Registry、页面、Store、PageLifecycle 实际执行。demand-page / 新定向测试使用 `ER_PZ_ROOT=/home/hatch/workspace/repos/pzserver/steamapps/downloading/380870` 下原版 ISTickBox；不是游戏运行。

| 检查 | 结果与范围 |
|---|---|
| ui-nav-grouping-test | 191 PASS：9 项映射、单叶激活／可见、旧页 token 失效与过期通知拒绝、工作默认需求、组内记忆（含子视图）、人员／工单／问题定位、失败留页、目标消失回退、显式打开及同窗重开 |
| demand-page-test | 65 PASS：需求／工单独立订阅、只读需求、切页释放及绘制缓存回归 |
| order-monitor-view-test | 23 PASS：原监控事实投影 |
| page-lifecycle-integration-test | 194 PASS：真实页面／抽屉释放与重复激活 |
| activity-page-test | 22 PASS：新组内导航契约及既有活动交互 |
| luac -p | 所有本轮改动 Lua（生产与测试）通过 |
| git diff --check | 通过 |
| CN/EN JSON | 解析通过，两项新增组标题成对 |

首轮失败均保留说明：Lua 5.4 无旧全局 unpack，改为执行器注入；demand-page 硬编码 Windows 安装路径不存在，测试宿主新增可选 ER_PZ_ROOT，默认路径不变；activity-page 的按钮替身缺 setX/setY/setWidth/setHeight，按原版控件契约补齐。以上为调用／环境适配，不放宽生产守卫。最终上述测试无失败；未跑其他整套回归。

实机、Java 编译、真实桥、字体纹理、Kahlua 实际 UI 与性能均**未验证**；不据宿主通过宣称视觉验收、性能提升或完整游戏能力完成。共享工具入口 `.workbuddy/tools/pz.mjs` 在本环境缺失，未运行其 doclink；两份新增文档相互链接，本轮以本地链接存在性检查替代，不等价于该工具通过。遵循本次交付文件范围，不改 BACKLOG/INDEX 或追加版本流水。
