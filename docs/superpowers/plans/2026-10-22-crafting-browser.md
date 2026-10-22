# 制作浏览与条件适配实施计划

用户已批准[设计](../specs/2026-10-22-crafting-browser-design.md)并指定主代理直接实施；不派生代理，不重复设计审批。使用writing-plans、pz-modding与既有ISUI约束。目标版本0.21.0，单人优先；不更改制作原生效果、旧单原件恢复或认领权威。

## 文件与接口

- ProductionRecipe：描述增加原物品类型、全部替代项与分类，保留现有执行机制门禁。
- CraftingCatalog：getScriptManager:getAllCraftRecipes分片枚举，稳定ID和分页查询；描述缓存与库存完全分开。默认只显示当前支持的机制，可切换查看未支持信息。
- CraftingPreview：request/cancel/step只读当前选择预检，复用ProductionSupply；世界/选择代次隔离，隐藏取消，库存/认领变更失效。数量较大超出有界匹配预算时明确未知，不假报完整库存。
- CraftingService：目录、预检和原命令桥接；保持现有按NPC身份的工单状态。
- UI/RecipeGrid、CraftingDraft、CraftingOrders、CraftingPage：分页图标浏览、动态条件与物品槽、独立工单及外层生命周期。复用Layout/State/CachedList/Theme/ItemPresentation。

## 步骤与验证

- [x] 核查当前JAR/API与原版目录用法；扩展只读描述、分片目录。
- [x] 只读有界预检；验证无资产领取、重复替代匹配、数量/工具恒定、旧结果取消、失效与缺平台。
- [x] 图标网格和下单草稿：搜索分类、目标/整批预览、替代项展开、条件与仓储跳转；手持不占设施行。
- [x] 独立工单视图，保持原工单动作和视图状态，隐藏时取消查询/释放全部弹层和订阅。
- [x] CN/EN必要宿主、逻辑和布局检查；preflight、版本构建、release-check、doclink和包一致性。仅相关检查，实机未运行则明确记录。

重点复查：大目录首次加载/空结果区别，当前库存与总仓储不同，已锁工具不可用，未加载箱子不等于0，输入变更的旧请求不覆盖新选择，已有工单不污染草稿，无工具/无平台控件省略，窗口小尺寸与大字体不会挤掉主操作。
