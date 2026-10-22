# 0.7.3 中文排版故障与UI基础整理

日期：2026-10-20。0.7.2用户截图表明中文标签缺失、方框重叠、容器悬停缺字，推翻其“本地检查即可说明显示正常”的隐含假设。0.7.2没有实机通过。代码由主代理实现，Luna仅只读复核；此轮由主代理独立排查、实施与验证，未派子代理。

## 根因与修复

旧UIFlow对字符串使用UTF-8字节gmatch，而安装游戏Kahlua的StringLib按Java字符处理。翻译由Java进入VM后，中文被模式过滤；根分类和物品label成为空串，行高只剩padding，方框高于行高而重叠。直接绘制的标题和三态文本仍能出现，符合截图。相同wrap用于侧栏tooltip，容器中文同样丢失。旧测试用标准Lua、英文键名和假字体度量，不能覆盖这个失配。

使用当前安装JAR内Kahlua、stdlib.lua和Java注入的Unicode翻译字符串，旧算法可重复失败“Chinese label characters were lost”；新Text模块保持字符、显式换行和窄宽文本。多行label设置最小一行高度；原版滚动区可见行短路保留。容器原名保持，只修复追加用途的文字完整性，没有擅自写入/覆盖物理名称。

把排版、相对布局、状态订阅、筛选列表提取为四个职责模块；窗口按row/column相对区域组装，编辑替换状态快照，由订阅局部更新。具体契约和未实现部分见[UI架构](../../ui-architecture.md)，实施依据见[计划](../../superpowers/plans/2026-10-20-ui-foundation-fix.md)。这只是基础开始复用，不能标记整份第11节、据点主面板、BOM或HUD已完成。

全部文案跟随游戏语言；应用/取消复用原版UI_btn_apply/UI_btn_cancel，专属键CN/EN成对，物品名称走原版翻译接口。当前在线文档仍为本日已核查v3.2，SHA256为794B68E2357A42451BA76DED8B266E707B94FD1C390ACAEE47AFF5207A2C9BA4。

## 验证与边界

- 旧算法真实VM失败已归档；修复在真实Kahlua中通过Unicode保留、窄宽与换行。
- 当前CN/EN JSON都通过实际Panel、Tabs和基础模块；窗口19项及容器栏18项交互/逻辑回归，不重复累加嵌套断言。另检查1080p、2K、4K及720p大字体的计算区域、类别非空和行高；状态不变不通知、释放后不通知。
- 标准Lua回归通过；0.7.3构建通过，固定安装JAR基线未变。发布检查28个Lua、2份翻译为0错误/0提示。
- AWT捕获实际组件布局绘制命令，主代理已查看CN/EN预览，未见中文丢失和条目重叠；不是游戏截图。ISUI宿主、字体测量/绘制仍用替身，不能据此声明原生渲染、CleanUI、控制器硬件或性能已验。

实机只需[本轮集中复测](../../testing/single-player-storage-filters.md)：重启0.7.3、原存档打开窗口，滚动分类/物品，检查中文/当前语言与侧栏原名，再验证应用取消和连续派单。不得把0.7.2截图故障标记为用户测试通过。

## 本地证据

[旧算法真实VM失败](probe-0.7.3-kahlua-before.txt)、[CN真实VM回归](probe-0.7.3-kahlua-CN.txt)、[EN真实VM回归](probe-0.7.3-kahlua-EN.txt)、[标准Lua](probe-0.7.3-lua-tests.txt)、[构建](probe-0.7.3-build.txt)、[构建基线](probe-0.7.3-build.json)、[发布检查](probe-0.7.3-release-check.txt)。预览：[CN](probe-0.7.3-preview-CN.png)、[EN](probe-0.7.3-preview-EN.png)；AWT用色块示意勾选纹理，不能视为原版纹理加载成功。

最终包SHA256：36B277C609E2B74A9561EB71E20D5DC65AA1BC37779A2A1114B434862DE4458C。

最终[preflight](probe-0.7.3-preflight.txt)通过，0错误/0警告；[文档检查](probe-0.7.3-doclink.txt)8份文档0错误/0提示。原版ISFluidEmptyAction的0.0f语法仍被工具解析器跳过，不属于本轮检查覆盖。最终包内六个UI入口/组件已与工作区逐字节核对一致。
