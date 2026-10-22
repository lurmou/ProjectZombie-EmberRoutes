# 0.8.0 据点范围与只读仓储

日期：2026-10-20；状态：已实现，本地验证，实机待验。用户反馈0.7.3“没什么问题”，作为该轮UI用户通过反馈，不扩展为全部界面/硬件/性能通过。用户选择本阶段“据点范围+只读仓储汇总/搜索+首版管理面板”，并重申基础性能、可扩展和维护优先；本轮主代理独立实施，未派子代理。

唯一在线文档已重读，v3.2，49255字节，SHA256仍为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4。[设计](../../superpowers/specs/2026-10-20-settlement-storage-design.md)、[计划](../../superpowers/plans/2026-10-20-settlement-storage.md)、[架构契约](../../settlement-storage-architecture.md)。未修改远程需求。

## 交付

独立版本账本/稳定据点与SP世界阵营ID；多矩形并集、重命名和扩展；原版式世界框选与边界预览，不创建SafeHouse/畜牧区/围栏。读取副本与写入命令分开，改UI副本不能写持久账本。按登记坐标建立空间桶，候选只返回稳定容器ID。

有消费者才推进的共享盘点；每次128读取/启动单位，每箱2000、一次20000件/2048类型上限；按变更源失效并合并通知、取消旧作业、明确未加载/私有/失效/超限，重复ID失败不发布错误合计。快照只含标量，无userdata，不是可支出资产。最后订阅关闭取消，跨世界立即清除旧可见库存，旧释放句柄不能取消新请求。观察者故障日志化隔离，不否决已经核对的真实转移。

面板使用Layout/Text/State和新CachedList组装物品/来源两栏；当前语言名称、缓存搜索和类别过滤、60项分页、键盘/手柄基本导航、来源自定义名/原版译名与XYZ。NPC搬运核对原实例成功后发布变更；玩家/第三方变更保留显式刷新。第一版只覆盖主容器直接物品，不包含嵌套、BOM、自动分拣或多NPC预留。

## 原版依据与技术限制

- 当前安装42.21.0的ISAddDesignationAnimalZoneUI:pickSquare/highlightSquareAtMousePointer使用screenToIsoX/Y、addAreaHighlightForPlayer；只复用交互原语，不复用addZone及createSurroundingFence业务。
- 实际IngameState字节码触发OnTickEvenPaused，盘点因此支持暂停期间推进。OnContainerUpdate原版ISInventoryPage只标renderDirty，不能凭事件名字断言每次物品变化覆盖。
- 当前ItemContainer JAR实际提供getDisplayType/getCustomName，原版ISInventoryPage也读取；安装Umbrella漏getDisplayType，用窄类型补充已验证签名，未全局关闭诊断。
- IsoPlayer:getIndex是实例UI索引，getPlayerNum实际代理它；getPlayerIndex()是静态全局，不可混作实例身份。这里只作本地交互校验，不作长期据点所有者。
- 不做未加载库存结算、自动防刷新、领地保护或可信联机账户认证；系统城镇边界仅有校验接口，未生成真实NPC城镇，也未实现两个账本合并/解散迁移。

## 本地验证

真实安装Kahlua+stdlib及实际CN/EN JSON运行：据点/仓储38项、面板交互/生命周期19项；另保留原过滤窗口/侧栏回归。标准Lua覆盖同一范围，原搬运69项相关回归通过；嵌套动作/夹具断言不重复累加。覆盖坐标边界、重叠、只读副本、归属拒绝、隐私、跨楼层、卸载中断、重复ID、读取预算、查询分页、共享消费者、取消、世界切换、失败观察者释放。

Java65项及检查点42项、安装文件哈希/真实override类来源冒烟和0.8.0构建通过；没有启动PZ渲染器或新增实机。CN/EN面板与框选窗口用实际组件绘制命令生成AWT预览，主代理已查看；预览包含示例物品，原版纹理/字体/UI宿主仍替代，不能称游戏截图或硬件通过。

实机及原版世界存取按[九步集中测试](../../testing/single-player-settlement-storage.md)。预算是代码工作量上限，不是毫秒或NPC规模压测结果。

最终preflight为0错误/0警告；发布检查37份Lua、2份翻译为0错误/0提示；文档检查10份0错误/0提示。解析器仍跳过原版ISFluidEmptyAction的0.0f语法，该文件不计为已验证。最终包的代码/翻译/元信息/JAR逐字节匹配工作区，包哈希见[验证摘要](probe-0.8.0-verification.json)。

原始证据：[构建](probe-0.8.0-build.txt)、[基线](probe-0.8.0-build.json)、[preflight](probe-0.8.0-preflight.txt)、[CN真实VM](probe-0.8.0-kahlua-CN.txt)、[EN真实VM](probe-0.8.0-kahlua-EN.txt)、[据点回归](probe-0.8.0-settlement-tests.txt)、[面板回归](probe-0.8.0-ui-tests.txt)、[原搬运回归](probe-0.8.0-work-tests.txt)、[发布检查](probe-0.8.0-release-check.txt)、[文档检查](probe-0.8.0-doclink.txt)。

布局预览（非游戏截图）：[仓储CN](probe-0.8.0-warehouse-CN.png)、[仓储EN](probe-0.8.0-warehouse-EN.png)、[框选CN](probe-0.8.0-selector-CN.png)、[框选EN](probe-0.8.0-selector-EN.png)。预览示例数据不是真实游戏库存。
