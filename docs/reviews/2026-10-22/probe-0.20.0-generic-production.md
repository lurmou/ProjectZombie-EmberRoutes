# 0.20.0 通用物品配方与按量生产

> 日期：2026-10-22｜状态：已实施，新增实机待确认。

## 结果与范围

用户批准先做通用配方、多材料/工具/产量与多件工单，后续再接完整搜索界面和最低存量。已新增ProductionRecipe、ProductionSupply、ProductionActions、Production四个职责模块，正常制作页显式提交recipeId和数量；不复制每个配方执行器。页面先开放木叉、木勺两个同机制样本，执行API按配方结构工作。完整配方目录、递归BOM、最低存量、专用台、液体/能量、特殊回调制作与跨NPC交接均未实现。

固定物品输入按实际IO索引匹配，支持多个材料、多个保留工具和固定产物数量；工具在父单内持续认领复用，最后归入既有分类箱。按原版一批一批串行制作，每批入库后再取下一批，保留父单目标、已制作和已入库独立计数；目标按主产物每批产量向上取整，页面显示实际计划数。已知完整交付的旧批次资源才可释放，工具和台始终保留认领；候选匹配完成后不继续寻找替换物品。

格式3记录保存材料/工具向量、当前批次的实际产物ID与交付标记。旧格式1/2不强行迁移未结算资产，原恢复与诊断入口保留；新正式页面走通用执行器，共用Work预算、生命周期及LaborStore权威。普通保存成功后下一正常tick有界恢复，失败不自动续工，手动暂停和读档显式继续；原工具丢失不能自动以同类型工具代替。缺料保留工单，补齐后显式继续。未知制作结果禁止重放；归还已知原件也不能抹除未知结算。

## 安装基线与接口证据

- 在线需求2026-10-22重新读取：SHA256为3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834；关注第5.0、5.2、5.3与11节。当前单人范围仍遵循用户后续决定。
- 安装projectzomboid.jar为E1A69EB743EDE60B213A0FE7F8B83D4FCAB773036D256CC4543A336F3B058A33，ZombieBuddy为EB79B9876332010733A8E0D7CE4FE0377846059A9E28859029E2A0FB449F6CF2。原版shared/Entity/TimedActions/ISHandcraftAction.lua沿用原生start/performRecipe，手选输入启动后不再重复规划，避免把自身耗材算入队列占用。
- 当前JAR的CraftRecipe.LuaCall枚举未对Lua暴露，新增Java只读元数据桥用于回调检测。所有回调暂拒绝，不把模组配方可读取当成动作已验证。
- 固定物品产物也使用OutputMapper，不能以mapper非空拒绝；只拒绝getEntrees非空的输入相关分支，再核对单一确定类型、固定数量与概率1。真实元数据类测试覆盖固定默认项和条件项的区别。
- InputScript.isReplace与OutputScript.isReplaceInput在当前JAR中恒false；OutputScript.isCreateUses对Item返回true，不能用于判定特殊“次数产物”。已移除这三个过时判断；使用实际资源类型、部分物品使用、createTo/consumeFrom和固定IO契约检测。
- Lua/JSON读取的Unicode路径不同；玩家翻译由原版翻译系统提供，数量连接符用ASCII，避免Kahlua源码字面量在预览中出现方框。

## 验证

制作相关最终261项检查通过，含既有173项兼容检查和新生产场景；输出build/logs/production-contract-final-0.20.0.txt。覆盖多件、多个IO索引/材料/工具、单次产量2的目标取整、缺料再继续、输入搬运中保存、制成后保存、同父单原件、工具缺失不替换、未知提交不重放、归还后继续阻断、资源替换失败不影响旧owner，以及SP权限边界。安装版Kahlua和原版动作Lua真实运行，原生制作逻辑、物品、移动、世界和保存宿主仍为替身。

保存编排35项、启动暂停15项通过，见build/logs/production-targeted-0.20.0.txt；保存夹具复用动作16项/搬运54项准备断言，未跑历史全套。CN/EN页签宿主各385项、物流页33项通过，见build/logs/production-ui-CN.txt与production-ui-EN.txt；覆盖显式recipeId/数量、无效数量门禁、状态图、不同字体/屏幕、渲染不测量与隐藏释放。预览build/qa/settlement-visual-crafting-{CN,EN}.png为真实Lua布局和AWT替身绘制，不是游戏截图。

版本构建、固定JAR、真实CraftRecipe回调枚举及OutputMapper元数据边界检查通过，见build/logs/build-0.20.0.txt。最终preflight通过：89个Lua语法零错误/警告，LuaLS零错误、仅余既有3条信息提示（调试链重复字段2、旧容器控件构造1），见build/logs/preflight-final-0.20.0.txt。发布检查零错误/提示，见build/logs/release-check-0.20.0.txt；相关Markdown链接检查通过。最终包核对见build/qa/probe-0.20.0-package-check.json。新增功能实机未验证，不宣称任意原版/模组配方全兼容，也不宣称跨文件崩溃事务或性能规模已验收。

[设计](../../superpowers/specs/2026-10-22-generic-production.md)；[计划](../../superpowers/plans/2026-10-22-generic-production.md)；[简短使用](../../testing/single-player-generic-production.md)。
