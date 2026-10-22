# 0.20.1：原版配方结构覆盖补充

用户指出木叉和木勺同构，不能证明通用配方已经成功。本轮按批准范围补充不同原版结构，全部共用现有执行器；最低存量和完整配方浏览器仍后续。

在线需求2026-10-22重新读取，SHA256仍为3A179F1907B8971E0DD13F8FC2FFA300F0661E6F68C7AA0E7EC3E37202499834。安装目录与JAR基线沿用[0.20.0证据](probe-0.20.0-generic-production.md)，构建重新核验依赖哈希。

| 原版配方ID（Base） | 覆盖结构 |
| --- | --- |
| CarveWoodenFork / CarveWoodenSpoon | 原样本；替代材料、雕刻技能及独立知识门槛 |
| CraftSheetRope | 手持、无工具，一张床单变一根床单绳 |
| SawLogs | 手持、锯具保留，一根原木产3木板；目标4件按两批产6件 |
| ChopLog | 平台、斧具保留，一根原木产6柴火与1碎木；两类产物分类交付 |
| MakeTentKit | 手持、无工具，4类材料，数量1/4/2/1，含替代材料 |
| MakeWoodenToolbox | 平台、3类保留工具、3类耗材，数量2/1/1，含替代材料与木工等级1 |

来源为当前安装media/scripts/generated/recipes下recipes.txt、recipes_carving.txt、recipes_carpentry.txt、recipes_camping.txt。制作页增加这些候选，仍逐个调用ProductionRecipe.read过滤，机制不满足时不展示。它们是有限样本，不是完整目录或已实机验收的兼容白名单。原版标签由运行时InputScript解析，业务不硬编码工具类型。

## 检查与限制

[来源提取工具](../../../tools/recipe-coverage.py)从安装脚本提取IO，核对耗材总数、工具数及固定产量，记录各源文件SHA256到build/qa/recipe-coverage.json，生成Lua数据。这是限定结构提取器，不替代原版解析器。原版MakeTwoLogStack回调和SawLongStick动态映射作为源码边界对照。

[定向Kahlua检查](../../../tests/lua/craft-probe-test.lua)采用这些实际脚本的数量、IO顺序、保留标记、替代项、技能和产物结构，复用现有执行器跑两批。手持不传平台；显式替代项分别用首/末选择；全部副产物入库，原工具跨批复用后归还。库存、标签匹配、HandcraftLogic效果、移动仍为替身，不能证明真实引擎解析/动画/效果通过。最终495项检查通过（含原有261项），原始输出build/logs/production-source-0.20.1.txt。

先运行`python tools/recipe-coverage.py`再运行现有craft-probe-test.lua宿主；缺少来源数据明确失败。仅跑相关检查，不重跑历史全套。CN/EN界面宿主检查通过，preflight通过（0错误、3条既有提示），构建及release-check通过；包96文件逐字节与当前模组目录一致。原始输出见build/logs中对应0.20.1文件，包检查见build/qa/probe-0.20.1-package-check.json。包SHA256为B9CA0F9C2C33ED8DA4A169272DD57293BD51184462628E24481DE08A4DB6A390。

新增实机全部未验证。日常优先试SawLogs目标4（应制作/入库6木板），再试ChopLog（柴火与碎木均入库）；方便时试帐篷或三工具木箱。无需一次测完全部，实机结果按具体配方记录，不由一项推断全部成功。
