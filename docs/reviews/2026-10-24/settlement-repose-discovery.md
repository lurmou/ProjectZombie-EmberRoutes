# 所属据点共享选床：0.25.1

日期：2026-10-24。用户要求消除“附近10格、同一楼层”的选床限制。本轮只收口设施发现与准备资格，未扩大睡眠上下文或宣称P2/P3整组验收。

## 来源和当前工作区核查

在线唯一需求已通过主机网络重读，标题v3.2，相关床位/休息正文与本轮范围一致。实施从属于唯一架构5.3及[本轮计划](../../superpowers/plans/2026-10-24-settlement-repose-discovery.md)。

- 安装游戏JAR SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。`javap`核查IsoCell.getChunkForGridSquare的8格chunk定位及IsoChunk.getMinLevel/getMaxLevel；负楼层来自已加载chunk的实际范围，不写死只扫0层或NPC当前层。
- 用户所说参考模组对应本机`D:/Project/ProjectRemnants`。当前根NPCFW.jar SHA256：`5229EB5A6871514DE274FEB91E8DB353FDBDE8FB42FD9741493D40CDE85BA19E`。其SafehouseLeisureIndex有共享世界观察、仓储/世界签名分离与区域/楼层遍历；当前JAR的javap输出保留在`build/logs/settlement-repose-reference-javap.txt`。旧v2反编译仅作机制导航，不把其全部实现认作本项目证据。
- 本项目独立实现增量索引，不迁入第三方代码。没有将其同步全区扫描照搬到每个NPC。
- 本轮开始时SelfCareFurniture已经正确解包`body.move`的授权结果与动作字符串，执行夹具也覆盖该分支。此前BACKLOG仍写“待修”已过期；本轮保留该修正，没有把别处已有改动算成本轮新增修复。

## 实际实现

`SettlementFacilities.lua`维护world/settlement/revision隔离的派生观察，遍历据点全部areas，重叠chunk只扫一次，读取加载chunk实际楼层范围，再增量观察格子和对象。该缓存只存运行期原对象引用，不保存userdata，不登记家具身份或取得声明；已有Job保存的稳定家具ID/部件证明不依赖缓存存活。

全局推进复用SelfCare服务，每帧最多64个观察推进步；各请求还可在已有8步扫描额度内分摊推进与选择。每格对象最多64、每chunk候选最多256、每据点候选最多2048，缓存最多32个据点；60秒未被请求的据点停止后台推进。容量/楼层观察异常保留不完整状态，不能据此宣称无床。上述为工程初值，未做真实游戏耗时或NPC规模实测。

LoadGridsquare、OnObjectAdded、OnObjectAboutToBeRemoved只使涉及的chunk置脏；对象事件可能不完整，因此完成一轮后15秒再进行有界复验。增量扫描跨tick时核对chunk对象身份；区域/版本变更重建派生观察，跨世界清缓存。对象拆除/替换仍由ReposeSites按原对象和稳定ID重验，旧观察不能授权新家具。

ReposeSites从当前唯一所属据点的共享观察选取设施，不再建立每NPC的10格方形扫描，也移除了prepare中的距离/同层门禁。只比较已确认候选：本人专属优先、之后床质量和距离（含层差的近似距离）；不是对未加载区域作全局最优承诺。禁止NPC、专属他人、玩家占用和其他任务声明继续被过滤。

选择不取得预约。prepare仍重验真实对象、整件部件、策略版本、所属据点与占用；到位及开始睡眠继续走resolve、原生寻路和统一身体Session。不会因为跨层发现而跳过楼梯、可达性、到位或预约检查。

未扫完/未加载/达到观察上限与完整观察无可用床分开：有已确认候选即可使用；没有确认候选时前者返回待观察，不触发“已确认无床”的地面回退。未加载区域通过加载事件或分散复验重新激活，不能在未加载世界中凭空创建床或传送NPC。

## 实际检查

- 定向Kahlua：新增15项（80格外楼上床、跨层prepare、共享观察、专属与公共排序、其他据点拒绝、负楼层、未加载/重加载、范围修订、重叠去重、闲置停止推进与缓存上限）通过。
- 既有家具身份/策略/占用24项、真实家具个人树/声明/停止15项、个人服务11项、原生休息观察10项、身体控制33项通过。均为安装版Kahlua加模拟世界/原生身体，不是游戏运行证据。
- 0.25.1构建通过，包含安装基线及相关Java检查、13项安装保存编解码、30项原生库存读取检查；未修改Java业务实现。
- preflight全部通过，LuaLS为0 Error；最终源码追加Lua lint及结构复核通过。release-check为0错误/76条提示；相关六份文档doclink为0断链/错误。保留信息性告警与原版单文件解析缺口，不记作零告警或全部原版文件均受检。
- 原始日志：`build/logs/settlement-repose-kahlua.txt`、`settlement-repose-final-kahlua.txt`、`settlement-repose-preflight.txt`、`settlement-repose-lint-final.txt`、`settlement-repose-structure-final.txt`、`settlement-repose-build.txt`、`settlement-repose-release.txt`。本轮交付包为`build/packages/EmberRoutesProbe-0.25.1.zip`。

## 未验证边界

真实跨层寻路、绕楼梯、到床边后原生睡眠/疲劳效果、重进保存及多NPC性能仍未运行，沿用[一份P2集中验收](../../testing/p2-runtime-acceptance.md)，增加远床/楼上/地下和加载切换场景。

发现范围覆盖全部据点不等于可以使用未加载或不可达的床。原生动作驱动仍有已存在的单次自主移动256格与180秒超时边界，本轮不扩大或绕过该控制协议；失败按原有冷却尝试其他目标。特别大的分散据点、阻断楼梯或全未加载区域需要实际场景核对，不承诺任意范围立即找到并睡下。
