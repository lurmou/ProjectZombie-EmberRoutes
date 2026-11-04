# UI 视觉 Slice 2：需求现场简报与工单行动档案

基线：`phase-3a-consolidation` / `4b85839` / `0.29.38`。本轮工作树实施，不提交、不打包、不改版本。执行来源为用户指定 `ui-visual-slice2-brief.md`；只实施其视觉范围，不把整体设计草案当新增业务授权。现代感按下面可检查项验收；尚无游戏内观感验收。

## 范围与分组

保留 Slice 1 的主导航、默认叶页面、组内记忆及 stable ID 上下文定位。DemandPage 继续继承 OrderMonitorPage 的独立 Service、事实和生命周期；没有新路由、页面工厂、Store、Watch 总线、手动指派或共同工单。工作调度、命令参数、权限守卫、存档均不变。

索引采用既有 Layout 旁的有界 split：目标宽度 24%，最小 14h、最大 22h，主区至少 28h；容不下时沿现有索引/详情切换模式，两个视口均保留全宽。未使用 split 的 axis 调用保持原行为。筛选在索引上方，以同一个 FilterChips 的 dossier 变体分行排布；创建和刷新在索引下方；没有主区顶栏按钮排。

## Hero 与显示口径

需求：问题 Medium 标题 → Medium 待处理事实量（沿现有 demandSummary，无可靠分母时不画数量条）→ 一行影响范围 → 缓存头像、姓名与一个当前动作（无人为待分配）→ 仅异常时的独立受阻/UNKNOWN 区 → 工具原件紧凑格子 → 展开后的覆盖、坐标、托管责任。

工单：标题 → 已产出/目标及已入库/目标分别显示；搬运仅已交付/目标；分母缺失时只显示已知数，不画百分比 → 人物与当前动作 → 原件/材料格子 → 展开业务步骤和技术说明 → 低位操作。已取出、携带、入队均不进入成果分子。多个独立 Job 默认只显示人员摘要，展开才出现各自当前动作；没有共同完成率。折叠的人员摘要不发起无用途的多人头像请求。

正常只显示 Service 已允许的暂停或恢复之一；次要展开操作在下方，取消/归还仅展开后可见，仍走原确认弹窗及 stop/resume/return 命令。隐藏按钮不改变生产守卫，也不代表责任已释放。用户暂停说明收进详情，不能涂成受阻警报。责任摘要和技术轨迹默认折叠，UNKNOWN 仍显著保留。

## 载体与携带事实修复

按 `ui-visual-slice2-carrier-fix-brief.md` 恢复两项遗漏，仅修改展示投影、定向测试与本段文档，保留视觉层级与业务守卫。

- 载体不可用：旧事实来自基线 `4b85839` 的 `UI/OrderMonitorCards.lua:390`（子处理者）及 `:396`（单人工单）。新位置为当前同文件 `:416–422`，主行或任一子处理者 `carrierAvailable==false` 时，在处理者之后的 alert 区独立显示现有 `Monitor_carrierMissing` 文本；聚合为一条，折叠/展开均显示，不依赖其他受阻原因。
- 携带数：旧事实来自基线同文件 `:395`。新位置为当前同文件 `:462`，主行 `cargoHeld>0` 时使用现有 `detail_carrying` 文本进入展开详情 notes，与 membership/coverage 同区。成果 produced/delivered/target 及分子不变。
- 本次复跑：ui-visual-slice2 100 PASS（新增 14 项覆盖主/子载体缺失、去重、可用时无警报、空/零携带、正数携带位于 notes、成果口径不变）；导航 191、需求 65、工单 23、生命周期 194、活动 22 全通过，personnel-enrich 通过。工作树 15 份新增/改动 Lua 逐份 `luac -p` 通过，CN/EN JSON 解析通过，`git diff --check` 通过。宿主及实机边界同下；未运行游戏。本补丁没有新增 Markdown 链接，未运行缺失的 doclink 工具。

## 公共增量与颜色角色

- Theme 注册 dossier background、panel、control、separator、gold、alert、text、muted、active；classic 与 AE2 的档案区域均使用同一克制映射，其他页面预设保持原样。背景 `0.045/0.055/0.06`，面板 `0.065/0.08/0.085`，细线 `0.30/0.34/0.36 @ 0.35`，金 `0.81/0.72/0.46`，主字 `0.91/0.93/0.91`，次字 `0.59/0.66/0.68`，警报 `1/0.50/0.40`，普通数量条为 muted 绿。页面没有新增 RGB。
- CardPanel 增加 plain 底部分隔线；Hero 仍走已有 briefing 四角 tick 与登记的 control 背景。非 Hero 不嵌套 CardPanel；整框仅保留原确认弹窗。StatMeter 仅增可选 plain/trough，旧调用默认行为不变。
- CachedList.reconcile 仅增加可选 cacheRevision，使主题通知能够重建同一事实对象的缓存，保留选择和滚动锚点；旧调用缺省行为不变。
- InfoList 仅 dossier 可选变体使用上述组合，保留其他消费者的卡片/原件路径。普通原件展示先投影为 UI 行，再在 InfoList 缓存阶段按宽度排一列/两列 ItemSlot；没有合并仓储、配方业务。
- 唯一新增公共 Widget 为 ItemSlot。prepare 只接受 icon/name/countText/status/selected 与 bounds/revision；绘制和 hit 共用准备的矩形。列表绘制的 offsetY 是行坐标平移，命中坐标应由列表换回行内坐标；不查询 InventoryItem、容器或生成原件。名称、数量宽度和状态文案都在 prepare 缓存。
- 头像服务最多缓存 16 个 stable npcId 快照，按消费者释放引用；成功头像不按秒重取。仅当前可见选中处理者的失败快照每秒重试；失效事件在更新路径取图。纹理由引擎拥有，页面不销毁。无纹理时用职业图标，姓名仍由人物行保留。
- Avatar3DView 的 Java 取图已移出 prerender，新增 detached snapshot 绘制接口。人员页只修原全局头像监听的生命周期：改为 activation scope 注册、匹配当前人物、切出移除与清引用；不改变人员页布局或样式。原头像 RGB 移入 Theme 的 legacy 角色，保留原外观。

## 所有权闭环与代码入口

以下路径以 `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/` 为根：

| 资源 | 创建/认领 | 正常释放 | 异常与迟到回调 |
|---|---|---|---|
| 两页订阅/主题通知 | `UI/OrderMonitorPage.lua:155` activate，沿 Lifecycle.mount 与 scope:watch | 同文件 deactivate → Lifecycle.unmount；scope defer 清头像引用与详情缓存 | PageLifecycle 的 wrapCallback/isCurrent；定向测试切页后调用旧 token 包装回调，被拒绝 |
| 档案头像 | `PersonnelService.lua` portrait，只读 Ledger 授权与 Driver 绑定，登记 owner；不认领业务资产 | releasePortrait 最后 owner 清缓存；OrderMonitorPage 选择切换和 scope defer 调用 | watchPortrait 通知经 activation token 门禁；失败重试仅 active 可见；缓存最多 16 项 |
| 人员页原头像监听 | `UI/PersonnelPage.lua:309` activate 内登记装备/衣物通知 | 同 scope defer 对称 Remove 并 setCharacter(nil,nil) | scope 包装拒绝旧通知；Avatar update 必须拥有 current scope 才重试 |

本轮不修改业务任务/资产创建、交付、归还或异常恢复链；展示释放不能证明资产结清。Theme 缓存由激活期通知重建，没有在绘制阶段检测 revision 后投影；Store 驱动投影后未手动重复 project。

## 现代感逐项自查

以下勾选代表源码和宿主检查，不能代替游戏截图审美验收。

- [x] 不对称主次：24% 目标索引，有 14h/22h 与主区 28h 约束；12/20/32 字高，极窄、窄、宽、超宽分支均有边界断言。
- [x] 主角第一层：Medium 标题及 Medium 真实成果量；清洁无可靠总量时不造百分比。
- [x] 主区无密集表格；人物、异常、物资按层级排列。
- [x] 无嵌套框；Hero 仅四角 tick，其他分区仅 1px 细线与留白。
- [x] 无整框列表行；绘制定向检查中主详情与索引没有 drawRectBorder 调用。
- [x] 顶栏无一排挤满按钮；筛选、创建、刷新归索引，操作在主区低位。
- [x] 同一屏金色仅两类：选中指示（含筛选/索引）与成果大数字；主操作不另用金色。
- [x] 说明文字 Small muted，坐标/覆盖/责任/技术轨迹收进展开详情；第一层不堆长说明。
- [x] 正常状态不使用强色；暂停和无人不画警报；受阻、缺料、UNKNOWN 独立保留。
- [x] AE2 档案区不引入亮蓝色；其他页面没有顺带换肤。

## 验证结果

宿主为标准 Lua 5.4.8，运行时提供 `unpack=table.unpack` 兼容别名。`ER_PZ_ROOT` 指向本环境只读原版 Lua 路径 `/home/hatch/workspace/repos/pzserver/steamapps/downloading/380870`；ISUI、桥、纹理为测试替身，不是实际游戏运行。

| 检查 | 结果与范围 |
|---|---|
| ui-visual-slice2 | 100 PASS（原 86 项保留，新增 14 项事实恢复断言）：split 三种字号/六种宽度；生产/搬运/无分母清洁；受阻、UNKNOWN、无人、缺料、部分成果、暂停、部分交付；ItemSlot 绘制/命中；绘制禁止测字与桥调用；主题重建、token 拒绝、头像缓存/重试/释放/16项上限 |
| ui-nav-grouping | 191 PASS |
| demand-page | 65 PASS |
| order-monitor-view | 23 PASS；仅补 Theme dossier 替身角色，不删除用例或改变业务预期 |
| page-lifecycle-integration | 194 PASS |
| activity-page | 22 PASS |
| personnel-enrich | PASS，缓存及职业翻译/回退边界 |
| luac -p | 15 个新增/改动 Lua 文件通过 |
| git diff --check | PASS |
| CN/EN JSON | 两份可解析；新增 handlers 一键成对 |
| 扩展 settlement-tabs | FAIL：第295行访问 nil itemList；原提交4b85839独立导出复跑同样失败，未删测试、未扩展修改该页面 |

本轮没有修改业务 Service 命令、守卫或存档字段。测试新增样本补齐实际行的稳定 id/generation，不放宽生产守卫。初跑环境缺少默认 Windows 原版路径/标准 Lua 缺 unpack 别名已通过运行参数处理；定向样本初期缺 id 导致主题重建断言失败，修正样本契约后通过。初查发现暂停误用警报与索引旧数量条整框，均已修正并复跑。

## Open 项

1. 游戏内视觉验收未验证：CN/EN 长名、真实字体放大、窗口窄化、头像裁剪、纹理就绪与鼠标/手柄体验；宿主通过不能证明实际观感已达标。
2. Java 编译、真实桥、字体纹理实测、实机、性能全部未验证；本轮未改 Java，不宣称帧率提升。
3. 受支持装备/衣物事件之外的外观失效通知覆盖仍需真实引擎验证；不存在头像时保留职业图标/姓名，失败只对当前可见对象节拍重试，不增加全员轮询。
4. 原有 settlement-tabs 的 itemList 契约失败尚未修复；本刀不改其他页面。基线复跑同样失败。
5. 共享 `pz.mjs doclink` 工具在此环境未找到；本段文档没有新增 Markdown 链接，采用本地路径存在性检查；不声称运行了该工具。

## 改动文件清单

- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/PersonnelService.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Avatar3DView.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CachedList.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/CardPanel.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/FilterChips.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/InfoList.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/ItemSlot.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Layout.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/OrderMonitorCards.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/OrderMonitorPage.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/PersonnelPage.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/StatMeter.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/UI/Theme.lua`
- `Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/CN/IG_UI.json`
- `Contents/mods/EmberRoutesProbe/42/media/lua/shared/Translate/EN/IG_UI.json`
- `docs/reviews/2026-11-04/ui-visual-slice2.md`
- `tests/lua/order-monitor-view-test.lua`
- `tests/lua/ui-visual-slice2-test.lua`
