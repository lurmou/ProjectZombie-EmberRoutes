# 资源与记录提交Java试验及0.29.26接线

基线：phase-3a-consolidation，eb65db6之上的累计工作树；本轮不清理此前改动。安装JAR仍按build-probe.ps1固定SHA256核对。用户批准分阶段迁移、只做必要检查，实际游戏验收由用户执行。

## 最终范围与取舍

公共内核继续只处理通用协调。LaborJobCommit.lua:60按同一Claims.tokensByTaskId中的资源数量选择后端：至少4个资源且命令包含capacity时调用ProbeRuntime.laborMutate；其余提交继续既有Lua。门槛不是新的领域规则，两个后端的校验与状态语义相同。创建/恢复、JobStore通用CAS、领域契约与通知仍为Lua；JobData有界复制沿用已有Java能力。

LaborCommitKernel操作传入的同一owners/capacity/token；没有静态缓存、Java镜像账本或新的持久字段。ClaimsKernel仅提供该粗粒度提交所用的集合/容量操作；未保留逐项公共桥。registered Contracts.get继续决定capacityMutable，Java不识别具体工种。

曾试验的完整JobUpdateKernel与逐项Claims桥已删除：桥接回调成本使普通小型制作提交变慢。不能由“Java通常更快”推出全部框架搬迁都有收益。本轮不迁TaskRuntime/TaskController、Job创建/加载、目录和预检回调；这些仍须分别评估。

## 创建、释放与异常闭环

- 创建/认领：LaborJobCommit.lua:5的createClaimedJob仍先分配权威claimId，acquireNew、容量预约、store:create；任一步失败沿原顺序释放并返回原错误。没有新增创建路径。
- 正常提交/释放：Java LaborCommitKernel.mutate:26先取当前detached Job与运行token，校验集合/声明/领域允许的容量命令，变更容量后调用原Lua store.update。成功才shrink；:97只有已被JobStore接受的DONE/CANCELLED才release+cleanToken。小型路径仍在LaborJobCommit.lua:230执行同一清理。
- 异常：容量拒绝恢复此前承诺；:87之后CAS失败恢复容量并经原store.update标记RECONCILE_REQUIRED/UNKNOWN；:93之后提交后缩减失败隔离原件并标记UNKNOWN。不绕过被包裹的store.update。读档仍由HaulJobRecovery及领域恢复契约重建未结责任；缺失会话不被视为结清。
- 引擎/VM：ProbeRuntime.java:38使用安装LuaManager.thread进行同步Lua回调。实际Kahlua中验证嵌套读取、原update故障包裹及通知；游戏Exposer本身尚未实机验收。未增加原生资产效果、动作或会话入口。

## 成本证据与启用边界

脚本tests/lua/java-labor-cost.lua：当前真实CRAFT格式4和HAUL格式3，调用真实LaborStore.mutateJob/JobStore，包含领域校验、detached复制和容量前后处理。每场景热身2000次、计时10000次。Lua基线亦启用原有Java JobData，避免把旧收益算给本轮。宿主用安装Kahlua和反射JavaFunction，不是游戏Exposer；结果包含JIT/进程噪声。

| 试验 | Lua ms | Java ms | 判断 |
| --- | ---: | ---: | --- |
| 首轮完整迁移，小制作 | 635.7422 | 814.8064 | 不保留全量迁移 |
| 首轮完整迁移，30件容量提交 | 6999.3668 | 5020.2493 | 粗粒度批量有收益 |
| 单独通用JobUpdate，30件 | 6999.3668 | 7715.511 | 否决并删除 |
| 最终粗粒度路径，30件复测 | 6912.5958 | 5250.8358 | 宿主约减少24%成本 |
| 粗粒度路径，1件 | 835.9764 | 1013.81 | 小批量保留Lua |
| 粗粒度路径，4件 | 1769.7634 | 1181.3068 | 从4个既有资源起启用 |

普通制作最终仍是同一Lua提交路径，不宣称制作性能提升。4不是已证明的全场景最优交点；不为门槛增加扫描，读取已有token.resources长度即可。尚未测游戏帧率、多NPC主线程尖峰和真实游戏桥成本。原始日志位于build/logs/java-labor-cost-*.txt；试验日志不等于最终包行为，最终1件走Lua。

## 必要检查

- 原型完整路径：JobStore35项及注册扩展、搬运路线30项、制作运行100项连同依赖夹具通过；之后按测量撤回通用更新/逐项桥，没有把这些原型成绩描述为最终全部Java化。
- 最终容量提交边界：labor-capacity-commit-test在原Lua16项和Java桥17项下通过，检查目标切换不足、CAS回滚、提交后所有权变化、终态释放和通知嵌套读取；Java额外断言实际调用入口次数。
- 原phase3a-stage-b-test及其482项证据/恢复/只读检查通过。原宿主缺io.stdout导致失败，本轮--evidence-userdata只补一个真实Java userdata供不合法证据样例使用；生产代码及测试期望未放宽。此为表重建/替身恢复，不是真实磁盘保存。
- 未重跑全量Lua回归、全库LuaLS或preflight；未做实机、强退、游戏性能验收。

最终搬运路线30项、配送55项在最终JAR的Java接线下通过；347份Lua普通/Debug编译、Java构建检查及CN/EN键集通过。候选包363文件逐项SHA256匹配工作区，确认包含ClaimsKernel/LaborCommitKernel/KernelValues且不含已撤回的JobUpdateKernel/DispatchDirectory；git diff whitespace与新增文档链接检查通过。

交付：build/packages/EmberRoutesProbe-0.29.26.zip；SHA256 844DC3D37DB8F7B1E09D4C8CF4CC6E143DAEE2E90DCAC04D8AEF2A32F1B7CD3D。Java需完全退出游戏后重新启动加载。未提交、推送或发布工坊。
