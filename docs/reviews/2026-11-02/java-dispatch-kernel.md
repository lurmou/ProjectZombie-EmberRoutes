# 公共调度计算下沉 Java

日期：2026-11-02；基线 phase-3a-consolidation@eb65db6 加本会话0.29.24工作树；候选0.29.25。用户确认Java具有性能优势时由Java承担底层计算，不能以语言替代成本评估。

## 范围与最终决策

- DispatchSelection.choose：Java遍历候选，优先级小者先、评分高者先、稳定key小者先；priority0与allowed非true不参与，返回原候选引用。Lua空候选直接返回，不为零工作跨桥。
- PlanningInvalidation：Java维护容器/作用域/未知版本、捕获与比较观察依赖、跨世界隔离及512观察项裁剪。PlanningWake只接现有事件；revision读取不初始化世界，不读取引擎对象。
- ProbeRuntime.workerDecisionWindow：一次返回最多16人的轮转窗口，减少逐人workerIdAt桥调用。PublicWork仍按实际访问推进cursor，最多评估4个合格成员，领域发现/认领继续通过注册回调。窗口用稳定ID复验；若同帧回调同步改名册，新成员可能留到下一轮，不能据旧索引授权其他NPC。
- TaskDirectory目录索引最终保留Lua：逐项Java目录试验在不同热身阶段结果反向，未证明稳定收益，实验Java类与桥已撤回，不交付第二实现。
- PrecheckQueue最多4条且validate/request.step/complete必须回调领域Lua；搬循环会增加往返，本轮保留。TaskRuntime/TaskController、原件Claims和持久格式不改，不宣称整个运行时已Java化。

参考沿已核对ProjectRemnants的Java批处理分工，不复制其TaskRunner或重建身体权威。此轮是计算位置变化，领域规则不重新集中到Java工种大类。

## 生命周期与闭环

Java观察状态由同一PlanningWake实例拥有，load按root身份清旧版本；没有静态跨世界目录/原件缓存。观察token字段形状保持world/scope/scopeRevision/unknown/ids，不变成Java持久对象。

创建认领仍为PublicWork的Lua directory.claim → provider.claim → 现有Job/Claims。正常释放仍由领域确认效果与义务后调用directory.release；异常withdraw保留已分配责任，UNKNOWN不释放。仲裁Java只返回候选，不提交资产或派动作。

无Java桥的独立宿主保留Lua兼容路径；Java错误不静默换后端重试。PlanningWake在模块初始化选择后端，同一实例不混用版本索引。

## 检查与测量

- public-work-test：78项在原Lua后端通过，78项在Java仲裁/失效桥下通过；目录两轮均使用最终保留的Lua实现。原生身体为替身，不是实机证据。
- DispatchKernelTest最终12项实际Kahlua检查通过：优先级/稳定排序、轮转和人数上限、revision无额外初始化、依赖变化、作用域隔离、世界切换和观察上限。初始22项含实验Java目录，已随撤回删除其10项，不将初始结果混为交付范围。
- 第一组宿主结果：16候选仲裁20000次 Lua230.3701ms / Java89.2224ms；目录upsert/claim/release循环20000次 185.3868 / 110.7474ms；128依赖比较10000次 190.1037 / 48.5516ms。
- 补测：仲裁1/4/16候选各20000次，Lua87.0768/146.3617/188.2313ms，Java65.9247/55.9282/37.5349ms；目录循环变为Lua34.5222ms / Java72.0783ms；128依赖10000次为161.0476 / 40.5132ms。目录结果不稳定且热身后反向，因此否决逐项目录迁移，不能只引用有利样本。
- 宿主为同安装Kahlua VM，Java通过反射JavaFunction接入，不是游戏Exposer；不同JIT阶段结果有波动。它支持大循环下沉的方向，不证明全部规模/实机帧率更快。目录未来如能批量合并再评估，不为本轮强加新接口。
- 最终Java构建、347份Lua普通/Debug编译及CN/EN键集通过；候选包363文件与工作区逐项哈希一致，JAR确认不含已撤回DispatchDirectory实验类；文档引用与git diff whitespace检查通过。仅必要检查，不重跑完整回归、全库LuaLS或preflight。

## 未验证

真实派工时延、多NPC长期负载、游戏桥开销和帧耗时未验证；正常保存重进待用户实机。需完全退出游戏后启动加载新Java。未提交、推送或上传工坊。
