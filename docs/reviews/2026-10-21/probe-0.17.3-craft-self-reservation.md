# 0.17.3：制作启动后把自身原料算作已占用

> 2026-10-21｜定向复现、修复及必要门禁完成；新增实机未验证。

## 根因与修复

0.17.2实机ACTION_REJECTED：CRAFT/step3、started=true；两个输入均在NPC主包且materialAllowed/toolAllowed均true，瑞士军刀Base.Handiknife耐久10、锋利度1，appliedIds恰好为这两个原件；随后NATIVE_RECIPE_REJECTED，无COMMITTING。

当前安装JAR的CraftRecipeManager.itemGetQueuedAmount遍历ISTimedActionQueue.queues[character].queue。isCurrentCraftActionPending只跳过当前且craftStarted尚未为true的动作；启动后，该动作本身也参与排队用量，整件耗材返回Float.MAX_VALUE。CraftRecipeData.consumeInputFromItems在testOnly=true时查询该排队用量并拒绝已被占用的输入。原版ISHandcraftAction.start在craftStarted=false时执行两次canPerformCurrentRecipe并填充已应用输入，最后才设craftStarted=true。

我们的CraftRecipeAdapter.applied错误地在start之后再次调用canPerformCurrentRecipe，且在perform、performRecipe及停止诊断中重复调用，把本单SmallHandle算成排队占用，导致动作启动后被适配器立即停止。这解释了“到了平台、物品和工具都有效但不制作”。不是配方不存在，也没有证据指向瑞士军刀或等级。

修复：applied只读取原版已经填充的getAllInputItems，核对数量及两个原件实例，不再重跑规划。仍要求原版start成功/craftStarted=true；原版启动失败仍记录NATIVE_RECIPE_REJECTED。提交前继续核对身份、位置、平台、技能、知识、认领及容量；HandcraftLogic.performCurrentRecipe仍走原版CraftRecipeData.perform，重新验证配方及实际输入；非testOnly消耗路径不扣减排队量。没有force标志，没有绕过原版启动或提交校验，也不改仓储/认领/恢复协议。

## 证据与验证

安装基线沿用[基线记录](crafting/baseline.json)，版本构建重验JAR哈希。相关JAR片段见[队列证据](crafting/0.17.3-native-queue-evidence.txt)。此前替身没有模拟该队列规则，无法发现此问题。

定向夹具现在模拟同一动作craftStarted前后不同的排队占用。修复前在正常路径复现craft action not reached；修复后104项制作相关检查通过，包括启动后规划返回false但合法原件可正常提交、分类交付、工具归还，以及真正原版拒绝/替换输入仍阻断。原版ISHandcraftAction为实际安装Lua；原生队列、逻辑和世界仍为替身。见[修复前](crafting/0.17.3-before.txt)和[修复后](crafting/0.17.3-after.txt)。未运行全历史Lua测试或启动游戏。

实机只需重启加载0.17.3，旧暂停单先显式归还，再制作一次。期待日志CRAFT_STARTED→COMMITTING→CONFIRMED→DONE。该新增实机仍待用户确认。

## 实施计划与自审

- [x] 定位原版队列扣量分支，以对应替身规则复现旧代码失败。
- [x] 删除启动后重复规划，保留原版启动、提交验证及原件身份检查；明确原版启动失败原因。
- [x] 仅跑制作相关定向检查，构建0.17.3。
- [x] 完成必要门禁和包核对，记录结果。

最终preflight通过，release-check零错误/提示，相关Markdown链接检查通过。构建输出build/logs/build-0.17.3.txt；门禁输出build/logs/preflight-0.17.3.txt。发布包86个文件与当前模组目录逐字节一致，见build/qa/probe-0.17.3-package-check.json；上述检查均不代表实机已经复测。

[前一诊断版](probe-0.17.2-craft-stop-diagnostics.md)；[简短实测](../../testing/single-player-native-crafting.md)。
