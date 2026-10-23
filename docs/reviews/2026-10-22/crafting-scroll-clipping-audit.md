# 制作草稿滚动裁剪核查

日期：2026-10-22。代码截点：experiment/modern-ae2-ui / 9e73e17；版本0.21.1。

## 用户实机证据

用户截图显示制作草稿底部的“维护”技能条件文字越过列表边界，覆盖平台选择区域。60ed243的滚动范围修正没有解决该现象；不得沿用“彻底封堵”的验收表述。

## 已核实

- CraftingDraft.lua的style.draw由CachedList.doDrawItem转入原版ISScrollingListBox.prerender。技能条件也是这一路径；未找到技能条件在清除裁剪后另画的代码。
- 当前安装版ISScrollingListBox.lua:505在逐行绘制前设置setStencilRect，541清除；部分可见行继续提交绘制本身符合此契约，不能把它单独认定为根因。
- 当前JAR的UIElement.DrawText通过TextManager绘制；setStencilRect使用绝对控件坐标，不加控件自身yScroll；文字绘制加yScroll。此处两者属于视口和内容坐标的正常区别，不应直接给裁剪框加滚动量。
- 原版嵌套裁剪在需要时使用clearStencilRect和repaintStencilRect恢复父级遮罩。该API存在不代表给当前列表再包一层就能修复。
- 现有settlement-tabs-test.lua将drawText、drawRect置空，不能验证OpenGL遮罩效果。未运行真实游戏修复验证。

## 运行环境差异

本次console.txt在15:09:48启动，早于核查、晚于上述提交。日志确认启用PZ Optimization，并报告IsoPlayer来自pzopt/aot/pzopt.jar。该JAR还包含UIElement替换，字节码在UIElement.render中加入UiRetained.replayChild/childBegin/freshEnd。不能只依据原版JAR断言实际图形路径相同，也不能据此直接断言PZ Optimization是根因。

SHA256：

- projectzomboid.jar：E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33
- pzopt/aot/pzopt.jar：BCE7EA210FC5C5392CA691A14345D90131B1D664D4D8A1876600A1AC46FD1D3D

核查原始输出保存在本地build/logs的uielement-scroll-inspection.txt、uielement-pzopt-scroll.txt、textmanager-scroll-inspection.txt、font-scroll-inspection.txt、uiretained-scroll.txt、indiegl-pzopt-scroll.txt和pzopt-config-scroll.txt。它们是字节码检查输出，不是实机绘制验证。

## 下一步与边界

先在相同窗口、配方和列表位置，对比关闭PZ Optimization界面缓存后的结果。Config字节码存在uiRetained、uiRetainedChildren配置，默认开启；尚未执行关闭对照，也未修改用户配置。若关闭缓存仍复现，再进一步隔离原版列表与自定义行绘制；若不复现，定位缓存/遮罩状态的兼容路径。均需保留原版自然裁剪，不先以整行隐藏掩盖故障。

本轮仅核查和记录，未修改运行代码、未发布新包、未宣称已修复。

## 后续：0.22.2 修复工序卡横向文字重叠

用户明确授权修复紧凑工序卡“长配方名覆盖平台标签及右边界”。本次只调整CraftingDraft工序行的横向布局：按实际宽度分配步骤徽标、配方名、平台徽标，两侧徽标限制为可用内容宽度的三分之一以内，名称使用余下空间；三者和第二行产出说明均复用Text.wrapLimited按测量宽度省略。极窄列不足一个字形时不绘制该文字。面板宽度改变时重新准备该行布局，避免缓存旧宽度。

新增crafting-chain-width-test.lua，沿用实际Lua组件及安装Kahlua。旧代码先复现横向越界失败；修复后中文/英文各182项宽度、重叠、缩窄后放大检查通过，覆盖17/20/24字号、485/260/160宽度和长中英文名称。所复用的526项页面宿主检查也通过。它们不是游戏渲染验收。

版本0.22.2构建成功。静态检查原始输出在build/logs/crafting-chain-width-preflight.txt，发布检查在同目录crafting-chain-width-release-check.txt；preflight全部通过，LuaLS为0错误、4条信息性警告；发布检查0错误、7条既有硬编码中文提示。已核对压缩包内CraftingDraft.lua与工作区源码一致。当前游戏JAR仍为上述哈希，未改原版UI或渲染配置。

这项修复只解决已复现的横向布局问题，不证明原来纵向裁剪的引擎根因已确认，也不把Java2D预览称为实机截图。现有纵向边界防护保持原样，游戏内显示仍未验证。

## 后续：0.22.3 恢复边缘自然裁剪

用户确认提前消失后，移除CraftingDraft文字和图标必须完整落在视口内才绘制的条件，改为与视口相交即提交绘制。完全离开视口的行仍跳过；CachedList保留原版prerender，原版ISScrollingListBox.lua:475-541设置并清除stencil。未修改滚动钳制、渲染缓存或原有横向列宽修复。

crafting-edge-visibility-test.lua先在旧代码复现底部部分可见文字未提交；修复后CN/EN各27项通过，覆盖17/20/24字号、顶部/底部、非零滚动、文字/图标和完全不可见行；长名称各182项仍通过。宿主只验证绘制提交，不验证GPU裁剪。静态输出：build/logs/crafting-edge-preflight.txt。实机和PZ Optimization缓存兼容仍未验证。

0.22.3构建及包内源码一致性通过；preflight全部通过（LuaLS 0错误/4条信息性警告），release-check为0错误/7条既有提示。
