---
name: verify-codebase
description: Select proportionate EmberRoutes checks and report static, mocked, build and in-game evidence separately.
---

# 工程验证手册

更新：2026-11-06｜状态：active。遵循[AGENTS](../../../AGENTS.md)的最少必要验证、生产契约与证据边界。

| 检查 | 命令/入口 | 能证明什么 |
|---|---|---|
| 翻译 | python tools/check-i18n.py | CN/EN键对称、字面量/已登记动态域；必需源码缺失也失败 |
| 静态模块边界 | python tools/check-architecture.py | 按实际模块索引查字面量require和pcall(require,...)、shared到client、业务到UI、直接ModData写入；动态模块和别名数据流不在证明范围 |
| 身体调用点 | node tools/audit-npc-control.mjs --changed | 只读文本清单，需逐项人工追踪控制权；exit0不是无越权证明 |
| 逻辑接缝 | java --class-path 'D:/Software/GameApp/steam/steamapps/common/ProjectZomboid/*' tests/java/KahluaLaborTest.java <test-file.lua...> | 安装版Kahlua VM执行指定用例；原生替身不能证明实机 |
| UI文本 | powershell -ExecutionPolicy Bypass -File tools/test-ui-kahlua.ps1 | 脚本所选文本/UI用例，不代表所有业务回归 |
| 构建 | tools/build-probe.ps1 | 固定安装JAR编译、Java/Lua相关构建检查和包；写JAR前确认游戏关闭，保留同期源码 |

根据实际修改选择定向测试；文档/工具校准不要求无理由启动游戏或每次跑全库。工具本身变更需运行反例/回归测试，不能只看当前仓库全绿。

交付分别写通过、失败、未运行；静态结果、宿主替身、构建、磁盘恢复、实机效果和性能分开。保留失败用例，不修改生产守卫迎合替身。涉及当前源码在并发变化时，构建候选必须核对所用快照与最终工作目录，不能覆盖他人变更。
