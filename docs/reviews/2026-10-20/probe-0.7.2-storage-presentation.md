# 0.7.2 仓储主图标与筛选界面

日期：2026-10-20。用户反馈0.7.1测试还行，作为用户通过反馈记录，没有据此补写独立场景日志。用户要求取消看不清的角标，且确认“按这套方案一起做”。[设计](../../superpowers/specs/2026-10-20-storage-presentation.md)、[计划](../../superpowers/plans/2026-10-20-storage-presentation.md)。在线v3.2重新读取：49255字节，SHA256仍为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4；本地仅进度与证据更新。

## 改动

StorageTabs不再包装render或绘制角标，绑定/配置事件通过原版ISButton:setImage替换主图。单类图、混合仓箱、私有/停用锁、空规则通用柜；允许的具体类型例外可能跨类，保守显示混合。悬停保留容器名，附类别和例外允许/拒绝数量并预换行。未知分类纹理缺失时保留原图。没有配置/不支持对象保持原图。

原版addContainerButton从buttonPool首项取按钮、重置image/tooltip/右键回调后返回；适配器先释放池首项仍属于自己的字段，再调用原函数并捕获新的原版基值，避免相同Texture恰好相等时误恢复旧容器。事件撤销按字段值比较所有权，其他适配器已改的字段不恢复成旧值；同一Texture值无法证明是哪一方最后写入，最终显示仍受补丁加载顺序影响。右键菜单继续链式追加，原选中/点击/渲染及textureOverride锁叠图保持。

StorageFilterPanel保留Editor规则、草稿/提交、权限与原任务边界。列表绘制方框、勾选/半选线及根分类色条，子类缩进，具体类型显示本地化名称及“跟随分类/允许/拒绝”。未知物品回退fullType；fullType保留在行悬停。名称/换行/规则状态只在refreshRows缓存，render不查脚本库、不算规则、不测量。行高由addItem的itemheight逐行提交，符合当前原版列表滚动/点击的变高行契约。失败消息预换行，底部预留三行；超长标签最多显示两行，完整名称在悬停。

原版依据：安装目录media/lua/client/ISUI/ISInventoryPage.lua:addContainerButton，ISButton.lua:setImage/render/updateTooltip，ISScrollingListBox.lua:addItem/prerender，ISTickBox.lua方框与Tickbox_Tick纹理；Pistol原版脚本Icon为HandGun3。CleanUI存在整文件替换ISInventoryPage，已静态确认，实机兼容仍待验。

## 验证

主代理实施/执行检查；GPT-6 Luna只读复核，发现自定义列表漏了原版可视区绘制短路，已修复并补回归。针对性Lua回归：容器栏18项、窗口19项通过，包含池化重绑同图值、第三方改值后释放、无配置恢复、未知纹理、本地化与未知名称、原生命周期/草稿/键盘/手柄、大字体720p留白、多行滚动高度与不可见行不绘制。构建通过，固定PZ42.21.0/ZombieBuddy2.3.4基线未变。preflight通过，0错误0警告；解析器仍跳过原版ISFluidEmptyAction的0.0f语法，该文件不属于本轮覆盖。

本地检查不等于游戏截图或实机验收；实际图标资源加载、锁图叠加、CleanUI、缩放/字体和连续搬运仍按[六项复测](../../testing/single-player-storage-filters.md)验证。业务搬运、持久化、NPC调度未改，不重复宣称完整系统验收。

本地证据：[构建](probe-0.7.2-build.txt)、[基线](probe-0.7.2-build.json)、[容器栏回归](probe-0.7.2-tabs-tests.txt)、[窗口回归](probe-0.7.2-panel-tests.txt)、[发布检查](probe-0.7.2-release-check.txt)、[文档检查](probe-0.7.2-doclink.txt)。最终测试包SHA256为BEFA49B3B0FBCC3312C59386DC0ACFBE5A3EEFE1535934BF1F2D0F800B091A1E，已逐字节核对包内两个修改模块与当前源码一致。

最终[preflight完整输出](probe-0.7.2-preflight.txt)已归档，包含可视区绘制修复后的静态检查结果。
