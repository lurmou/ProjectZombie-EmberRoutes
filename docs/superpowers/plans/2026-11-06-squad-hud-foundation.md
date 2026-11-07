# Squad HUD Foundation Implementation Plan

**Goal:** 补齐用户批准的ProjectRemnants基础HUD交互。
**Architecture:** 角色显示偏好与成员业务分离；Service观察原版状态；纯Presentation与token拥有的HUD资源。
**Spec:** [已批准的基础补全设计](../specs/2026-11-06-squad-command-ui-design.md)
**Constraints:** 不改队伍/编队契约、不兼容旧偏好格式、不实现接管/物品转移/战斗；保留同期改动。

- [x] SquadPreferences：归一化位置、显示顺序、缩放、呼号；持久化当前format，拒绝未知格式写入。
- [x] SquadService与SquadPresentation：Moodle快照、状态徽章、完整提示、血量语义色。
- [x] SquadHUD与SquadHUDMenus：拖动、排序、滚动、hover、边界、配置菜单、右键命令、呼号dialog与对称清理。
- [x] SquadUI：分辨率/字体刷新；CN/EN成对翻译与门禁。
- [x] 偏好/实际HUD交互/生命周期/纯渲染定向Kahlua、必要构建；证据与BACKLOG原位更新，用户实机待验。

结果：[0.29.53实现与检查](../../reviews/2026-11-06/squad-hud-foundation.md)。代码/构建完成，全部实机由用户测试。
