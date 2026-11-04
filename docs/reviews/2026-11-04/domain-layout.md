# 搬运目录迁移与 Java 桥表面审计

基线：phase-3a-consolidation / 991c933；[设计](../../superpowers/specs/2026-11-04-domain-layout-design.md)与[计划](../../superpowers/plans/2026-11-04-domain-layout.md)。

## 搬运执行领域

client 8 个、shared 2 个 Haul* 模块迁入各自 EmberRoutesProbe/Hauling，原名不变，无旧路径转发。调用方同步更新。特殊动态路径：BuiltinJobContracts 的 record('Hauling/HaulJobRecord')、BusinessJobs 测试的 stub('Hauling/HaulManifest')。Boot 的 tickHaul 采样名和 HAUL providerType 不是模块路径，保持不变。

等价检查：43 个被修改/移动的现有文件，逆向替换字面与动态路径后逐字节（仅归一 CRLF）等于基线；启动文件的其他会话医疗调试 require 单独排除并保留。全生产/测试/工具/Java 文本旧模块路径残留为零，client/shared 模块名大小写折叠无重复。详细本地报告 build/domain-layout-equivalence.json。

创建/认领仍为 client/EmberRoutesProbe/Hauling/HaulJobs.lua 的 claim；正常 settle/finish 保留活动尝试/未结原件守卫；暂停仍为 HaulAgent.pause，恢复为 HaulJobs.prepareRecovery 与 HaulJobRecovery.restore。未改任务格式、声明、数量/容量或物理动作，不实现混装多目标搬运。

迁移前后相同安装版 Kahlua 命令（--java-labor --java-dispatch --java-job-data --keep-going）：haul-test、haul-source-backoff、hauling-provider、dec003-haul-migration、dec003-haul-recovery-boundary、labor-capacity-commit 通过；haul-routing、logistics、delivery-service 均在迁移前已由 multi-worker/work 宿主夹具失败，迁移后同样失败。9 套中 6 通过，不能写成全部通过。日志 build/domain-layout-before.log、domain-layout-after.log。modscan 扫描 358 个 Lua，与已安装模组整文件覆盖冲突 0。

首轮替换遗漏动态 record 路径曾引起 3 个新增失败，补齐后失败集合恢复基线；记录此检查的作用，不以文本扫描代替真实路径加载。真实游戏加载、动作、磁盘恢复与性能未验证。

## Java 与最终交付

待完成：公开日志收回、无引用树格检查转发删除、94 个正式桥名称反射检查、实际依赖构建与最终门禁。未完成项不计作通过。
