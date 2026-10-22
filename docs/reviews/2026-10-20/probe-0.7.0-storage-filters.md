# 0.7.0 多选存储过滤实现与验证

日期：2026-10-20。实现、本地验证；游戏实机未运行。依据[在线v3.2变更记录](requirements-update.md)、[设计](../../superpowers/specs/2026-10-20-storage-filter-design.md)、[计划](../../superpowers/plans/2026-10-20-storage-filter.md)。不编辑远程需求，进度继续本地。

StorageFilter提供分类树/适配规则注册、版本化有界配置、隐私与匹配、旧标签映射；FilterEditor只处理草稿/三态类型例外；StorageFilterPanel原版生命周期与字体相对布局；UIFlow在创建时缓存UTF8文本布局；StorageTabs包装原版已加载按钮的右键/绘制并保存旧链，角标只绘制缓存。ContainerRegistry只提交经权限/加载/距离验证的配置；Work在规划及原版效果边界检查目标接纳。过滤为存入规则，读权限由启用/隐私决定，没有职业锁，允许整理误放物品。

扩展接口：StorageFilter.registerCategory(id,parent,color)、registerClassifier(id,fn)。类别最多128、树深16；配置groups/types各最多256条；面板最多扫描主格2000个实例，列128种当前类型和已有例外。回调与物品类型只在规划/动作验证或打开面板时求值；角标刷新来自配置事件/按钮重绑，render不扫描世界、库存或分类。没有真实帧耗时测量，不能称零CPU。

## 原版与兼容查证

当前安装ISInventoryPage.addContainerButton返回按钮并每次重设onRightMouseDown、inventory，且使用buttonPool；原右键通过ISContextMenu.get创建菜单，追加必须用getPlayerContextMenu，不能再次get清空旧选项。ISButton原绘制保留，再画缓存小图标。图标路径来自当前Definitions/ContainerButtonIcons.lua。ISCollapsableWindow必须调父类initialise/createChildren/prerender；ISScrollingListBox原手柄导航会调用鼠标选择回调，因此本实例方向键覆盖为仅移动选中，A/空格才切换。

分类依据当前InventoryItem.getCategory/getDisplayCategory/isFood/getOffAgeMax、武器isRanged；当前InventoryItem默认offAgeMax=1000000000表示无腐坏上限。识别不了的DisplayCategory不猜测，进入other；明确fullType例外优先。未知/错误版本配置拒绝，非布尔规则不以Lua真值授予权限。

modscan确认CleanUI替换ISInventoryPage，故不覆盖原版文件，只接运行时公开方法并保留旧链；已核查原版及CleanUI现有文件结构，真实CleanUI和切换模式仍待实测。无法取得原版按钮契约时保留世界菜单，不伪称兼容。仅主容器，副格明确排除。

本地替身覆盖分类/树继承/具体例外、隐私、无效配置、未知模组和注册扩展；实际Work规划/效果前修改过滤及续工；编辑器隔离、原生父类委托、字体布局、键盘手柄编排；菜单不清空、原返回值保留、按钮复用不叠钩、原生render保留且不查询库存。不能据此宣称真实动画、UI、保存恢复或模组兼容通过，须按[集中测试](../../testing/single-player-storage-filters.md)验收。

## 最终本地结果

[构建](probe-0.7.0-build.txt)、[Lua回归](probe-0.7.0-lua-tests.txt)、[preflight](probe-0.7.0-preflight.txt)、[发布检查](probe-0.7.0-release-check.txt)、[文档检查](probe-0.7.0-doclink.txt)、[冲突扫描](probe-0.7.0-modscan.txt)通过；最终LuaLS零错误/警告。见[验证元数据](probe-0.7.0-verification.json)、[构建元数据](probe-0.7.0-build.json)、[在线来源元数据](online-v3.2-source.json)。本轮未运行实际游戏，不增加实机通过结论。

初次沙箱内JDK构建出现Cannot close compiler resources，同一构建在沙箱外通过，未因此改引擎代码。界面自定义字段已补类型契约，空列表行已防护。仅对明确且经源码核查的两种提示做单行豁免：保留原调用链的addContainerButton方法包装，以及当前原版仍使用的setJoypadFocus(player,nil)关闭路径；没有关闭整类类型检查。知识库仍提示原版ISFluidEmptyAction.lua的0.0f解析缺口，专用EOL检查因架构不适用跳过。
