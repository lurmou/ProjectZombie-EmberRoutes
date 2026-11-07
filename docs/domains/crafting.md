# 制造与递归生产领域

> 更新：2026-11-06｜状态：active｜以当前源码校准。此页是导航与现行契约，不是未来能力承诺；功能完成度见BACKLOG。

## 1. 职责与非职责
提供配方事实、工位/材料能力、制造Session及依赖规划；玩家配方UI接入属于Integration，生产执行不能依赖UI。

## 2. 数据权威
CraftRecord/CraftJobRecord与统一Job保留执行与原件事实；ProductionChainPlan是纯规划，运行中Chain对象不是第二份物品库存。工位租约由CraftStations核对。

## 3. 现行生命周期
CraftingService观察/预览/提交现行命令，ProductionChain适配原版配方与库存，执行/停止/恢复仍经Production与TaskRuntime。不能仅凭BOM存在就宣称自动补全所有缺料，工具中断也不承诺自动换新。

## 4. 真实接口入口
- `CraftingService.preview(actor,id,npcId,recipeId,quantity,surfaceId,callback,preferences)`
- `CraftingService.command(actor,id,npcId,action,surfaceId,recipeId,quantity)`
- `ProductionChain.new(actor,npc,entry,recipeId,quantity,object,taskId,knownMissing,preferences,options)`
- `CraftStations.search(entry,facts,accept) / reserve(c,object,facts) / release(c,stopped,expectedLease)`

参数和返回细节以链接中的生产调用方/定义为准；这里不定义第二套API，也不为手册示例添加兼容别名。

## 5. 依赖边界
业务模块不引用UI；原版UI接入由Integration负责。shared只依赖实际存在的shared模块；客户端执行/账本组合放client。跨业务调用须经当前公开服务，已有组合依赖不等于所有内部文件都能任意引用。身体只通过TaskRuntime/TaskController/Driver当前授权链执行。

## 6. 源码地图
- [client/EmberRoutesProbe/Crafting/CraftingService.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Crafting/CraftingService.lua)
- [client/EmberRoutesProbe/Crafting/ProductionChain.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Crafting/ProductionChain.lua)
- [client/EmberRoutesProbe/Crafting/CraftStations.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Crafting/CraftStations.lua)
- [shared/EmberRoutesProbe/Crafting/CraftJobRecord.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/shared/EmberRoutesProbe/Crafting/CraftJobRecord.lua)
- [client/EmberRoutesProbe/Integration/RecipeOrderEntry.lua](../../Contents/mods/EmberRoutesProbe/42/media/lua/client/EmberRoutesProbe/Integration/RecipeOrderEntry.lua)

## 7. 验证入口
按修改点运行crafting相关Kahlua与Production/工位边界用例，新增原版配方/动作按当前安装版源码核对。

## 8. 易错边界
无requestCraft/findAvailableStation/decomposeBOM/getRecipeInfo这组虚构门面；原版动作存在不代表NPC可执行。

自动化、原生替身、实机、磁盘恢复与性能分开记录；源码存在和构建通过不等于玩法已验收。
