# P3 人员详情与实体书研习：0.25.0 开发证据

日期：2026-10-24。状态：核心代码与开发侧检查已接通，P3未完整验收，不能标记整个阶段完成。

## 需求与基线

本轮经主机网络成功读取[在线唯一需求](https://docs.google.com/document/d/1aTOBrzZvh_iCDkv045HNAV13i7vNf7OHk6E_sE7TWNM/edit)的TXT导出，标题v3.2；读取第4节、10节及11.3等有关正文。临时文件不是第二份需求源。在线旧MP优先级仍被用户单人优先决定覆盖。

- 安装`projectzomboid.jar` SHA256：`E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33`。
- 安装`media/lua/shared/TimedActions/ISReadABook.lua` SHA256：`AC7606335AC26D09C8E2C6BC3F8489E5298D71468E6AF79D0AB26FBE2348228C`。
- `javap -c`核对`IsoGameCharacter.isRecipeKnown(CraftRecipe,boolean)`、`ReadLiterature`、`Literature`构造与`ItemCodeOnCreate.onCreateRecipeMagazine`。
- Lua/签名查询记录来自工具链`ask ISReadABook.new`及`ask Events.LevelPerk`；索引只作导航，实际契约核对安装文件。

## 代码实际接入

1. `LibraryIndex`按据点共享观察已登记STORAGE容器的书籍，接受通过该容器过滤器的实体书。书架或任意箱子须先通过既有容器配置登记为可用仓储；本轮没有自动取得未登记家具的物品权限。
2. `StudyService`没有独立tick/派工器。PublicWork评估本轮没有可执行工作时才提供个人闲暇机会；技能合格但缺配方的工单提供关联研习目标，不预认领制作Order。已存在工作、过期机会、新工单及本人策略变化均有重验。
3. STUDY复用SELF_CARE Job、LaborStore个人原件声明、TaskRuntime唯一身体及SelfCareCustody借还。记录包含具体itemId、来源/归还端点、attemptId、效果、借还责任及阅读事实。停稳后归还；原来源无效尝试已有授权归还路径，不能定位/不能归还则保留责任。
4. `StudyActions`只代理原版ISReadABook的方法，不自行写配方、页数或经验。完整学习后唤醒有关NPC的工作评估；重新认领仍通过原版知识、技能、材料与平台门禁。原件被移走、完成效果不一致或未确认的开始进入UNKNOWN，禁止自动重放。
5. 有页数书籍每秒最多记录一次变化的原生页数；每30秒在安全停止点让出身体、归还并重评工作。无页数配方杂志沿用原版整段时长，不套用该分段以免每次重读却永远无法完成。新命令和生活需求仍能中断。
6. `StudyRelief`在归还等待时保留书籍声明，可在同一身体授权下使用本人主库存的吃喝物资或原生休息。切到跟随的借阅者可短暂自理后恢复该次跟随意图；跟随期间不回仓库还书、不开始长睡。此异常路径对嵌套背包物资暂未扩大适配，不宣称全场景自理覆盖。
7. `PersonnelService`按所选NPC懒读技能、知识、特质及经验倍率，升级/阅读结束失效；知识32条分页，原生列表读取有上限（技能128、知识4096、特质128）。人员页新增状态/技能/知识切换和单人优先级菜单，与全员矩阵走同一版本化命令。显示需求、情绪及借阅状态，关闭释放选中缓存。床位只保留现有世界家具配置入口提示；未假造完整绑定/岗位/区域后端。

发现/选择使用现有个人服务共享预算：每帧nodes16、scan32、paths1、containers4，发现服务每200ms轮转最多4名NPC；每名研习候选最多使用8扫描额度和1容器额度，避免前两人耗尽后两人的资源。索引最多256本书，观察上限/未加载与无书分开。预算是初值，不是多NPC实测性能结论。

## 原版差异：不能照旧文档假定页数

当前JAR中Literature默认页数为-1。原版CookingMag1、ElectronicsMag4等脚本不指定正数页数；其OnCreate给原件写`literatureTitle`，不是需要排除的非法状态。此类杂志通过ISReadABook的原版完整时长与complete→ReadLiterature学习，而不是人为补页数。UI对此显示阶段，不显示虚假页数。

有页数技能书的`getDuration`从当前角色阅读记录恢复物品页数；传阅不能继承上一个读者的物品进度。`checkMultiplier`实际每10%进度递增倍率，继续沿用该实现。`isRecipeKnown`接受名称、metaRecipe、翻译名称三种知识键，研习候选按书籍实际教授的键匹配。`ReadLiterature`会消费带CONSUME_ON_READ标签的物品，因此本轮耐用图书候选明确排除该标签及printMedia特殊阅读UI。

## 实际检查与日志

- 新P3定向Kahlua：共享图书/学习回调/资格/取消及策略代次24项，人员缓存/借书期间自理12项，通过。
- 关联个人消费13项、个人BT借还20项、个人服务11项、个人恢复27项、休息10项、公共派工57项，通过。含新增“缺配方只产生个人研习目标”“借书恢复只可打断随从、不得抢普通工作”和保留借书责任恢复跟随的宿主检查。
- CN/EN人员所在页面最终回归各711项、关联物流页面各33项通过。工作区已有并行UI调整，本轮保留，计数以最终原始输出为准。均为模拟ISUI宿主，不是游戏渲染或完整输入设备验收。
- 最终preflight模组根检查全部通过，扫描工作区160份Lua；结构/不变量/索引检查通过，LuaLS为0 Error；信息性Warning保留原始输出。原版`Fluids/ISFluidEmptyAction.lua`的`0.0f`造成知识库单文件解析失败，不计为已检查该原版文件。
- 0.25.0构建通过，包含固定安装基线、相关Java测试、13项安装版保存编解码和30项库存原生读取检查；不是载体真实保存/阅读运行证据。
- release-check为0错误/76条提示（含工作区已有硬编码文案等）；doclink六份相关文档0断链/错误，不把提示省略成无问题。
- 最初误把整个仓库传给preflight，扫描到tests/build替身中的`package`等测试全局并失败；保留`build/logs/p3-preflight.txt`，不记通过。正式产品门禁目标为`Contents/mods/EmberRoutesProbe`。

日志入口：`build/logs/p3-study-kahlua.txt`、`p3-final-kahlua.txt`、`p3-follow-resume-kahlua.txt`、`p3-ui-cn.txt`、`p3-ui-en.txt`、`p3-preflight-final.txt`、`p3-build-final.txt`。对应交付包为`build/packages/EmberRoutesProbe-0.25.0.zip`。

## 尚未验证与剩余P3

本轮没有运行游戏内原生阅读、读完真实解锁与倍率、双NPC传阅、强制中断、真实存档重进、路径失败恢复、多NPC负载、强退或MP。宿主回归不能替代这些证据，按[集中P3验收](../../testing/p3-runtime-acceptance.md)成组验证。

P3剩余功能：完整床位/居所绑定与重新指定视图、岗位/区域的真实后端与人员投影、已实现能力对应的宏观快捷指令及完整输入设备/布局验收。未实施的农业、医疗、守卫等工种不启用伪矩阵列；自主锻炼、休闲小说/视听/社交需要另行按在线需求形成从属实施细化，本轮没有实现。
