# 国际化与双语翻译闭环铁律 (I18N & Bilingual Parity Invariants)

> 适用范围：全库文本翻译与本地化资产（`shared/Translate/`）  
> 层级定位：Layer 5 自动化构建门禁（由 `tools/check-i18n.py` 强校验）

在设计、新增、重构或修复任何业务逻辑、工种服务、状态枚举及用户界面（UI）时，所有 AI 助手必须严格遵守以下四大硬性限制：

## 1. 零裸键容忍与静默降级拒绝 (Zero Raw Key Leakage)
- **严禁裸键泄露**：游戏界面绝不允许向玩家展示未翻译的原始键名（如 `IGUI_EmberRoutesProbe_Public_toolReturn`、`IGUI_EmberRoutesProbe_Activity_advancedDrawer` 等）；
- **拒绝依赖静默降级**：Project Zomboid 原生 `getText(key)` 在找不到翻译时会静默返回原始键名字符串而不报错。严禁将“界面能打开、控制台没红字”作为翻译已完成的依据。

## 2. 动态拼装键的成对前置注册 (Dynamic Key Binding Contract)
许多业务与 UI 模块采用动态前缀拼接（如 `pubText(category)` 拼接为 `'IGUI_EmberRoutesProbe_Public_' .. category`）。**在后端或服务中新增任何注册项时，必须同时在 `Translate/CN/IG_UI.json` 和 `Translate/EN/IG_UI.json` 中登记对应的拼装键**，绝不允许“后端已就绪、UI 拼接却裸奔”：

| 领域 / 注册源 | 拼接前缀与规则 | 必须注册的翻译键示例 |
|---|---|---|
| **PublicWork 工种类别** (`category = 'xxx'`) | `IGUI_EmberRoutesProbe_Public_<cat>`<br>`IGUI_EmberRoutesProbe_Personnel_<cat>` | `IGUI_EmberRoutesProbe_Public_toolReturn`<br>`IGUI_EmberRoutesProbe_Personnel_toolReturn` |
| **据点仪表盘标签页** (`id = 'xxx'`) | `IGUI_EmberRoutesProbe_Settlement_tab_<id>` | `IGUI_EmberRoutesProbe_Settlement_tab_warehouse` |
| **工种策略标题** (`titleKey = 'xxx'`) | 显式全键名 | 对应 `titleKey` 的完整键名 |
| **成员职责/拒绝原因** (`T.reason('XXX')`) | `IGUI_EmberRoutesProbe_Membership_<CODE>` | `IGUI_EmberRoutesProbe_Membership_NO_MEMBERSHIP` |
| **局部 Helper 函数** (`text('key')` / `pubText('key')`) | 对应文件定义的常量前缀 + 后缀 | `IGUI_EmberRoutesProbe_Activity_advancedDrawer` |

## 3. 中英双语绝对对称 (100% CN/EN Key Symmetry)
- **严禁单语言提交**：任何翻译键的增加、删除或重命名，必须在 `Translate/CN/IG_UI.json` 与 `Translate/EN/IG_UI.json`（或 `Sandbox.json`）中**同步成对变更**；
- **键名集合完全一致**：禁止 CN 存在但 EN 缺失，或 EN 存在但 CN 缺失。

## 5. 百分号转义（PZ 42.20.2 %% 规则）
- **字面 `%` 必须写 `%%`**：翻译值里要显示 `%`（如 `-2%`、`负荷 42%`）必须写成 `%%`；裸 `%` 目前只靠引擎临时兼容才显示，未来版本会被移除。已实测：`benefitAppliedValues` 的尾部裸 `%` 在当前安装版引擎里已导致显示损坏（`%3$s` 泄漏为 `-6$s`），改成 `%%` 后恢复正常。
- **占位符 `%1`~`%9` 不变**，`%2x%3`（尺寸 `宽x高`）读作占位符 `%2` + 字面 `x` + 占位符 `%3`，不是格式动词。
- **Lua `string.format` 动词（`%d`/`%s`/`%.1f`）只允许白名单键**：见 `tools/check-i18n.py` 的 `FORMAT_VERB_ALLOWLIST`（10 个键，均经 `getTextOrNull` 无参取回原文后在 Lua 里 `string.format`）。新文案优先用 `getText` 的 `%1`~`%9` 参数；新增格式动词必须进白名单并注明调用点，否则 `tools/check-i18n.py`（第 8 节）直接报错。

## 6. 构建与验证硬性门禁 (Automated CI & Build Gate)
- **校验工具**：项目根目录已配备自动化静态审计工具 `python tools/check-i18n.py`；
- **构建拦截**：`tools/build-probe.ps1` 已将 `tools/check-i18n.py` 接入核心流水线。只要存在以下任何情况，构建将立即中断（Exit Code 1）：
  1. CN 与 EN 键集不对称；
  2. Lua 源码中存在未在字典中注册的静态 `getText('IGUI_...')` 或 `text('...')`；
  3. 已注册的工种类别、标签页、策略缺少对应的动态装配键。
- **提交报告铁律**：凡涉及新增/修改工种、状态枚举或界面的任务，AI 提交报告中必须明确说明已执行 `tools/check-i18n.py` 且通过 0 错误验证。
