# 硬件阶段性进度与软件联调回传说明

- 日期：2026-10-17
- 对象：软件负责人
- 当前硬件分支：`hardware`
- 当前基线提交：`6e0bd881b6acde166ea86636307ac5c69207a57d`

## 结论

目前**无法整体交付软件联调所需的两份 CSV**。

- `word_readback.csv` 已生成并通过针对性缓存读回测试，但测试范围仅覆盖缓存管理器，不代表 DMA、AI engine 或 E203 SoC 的端到端读回。
- `pe_trace.csv` 尚未生成。FP32 PE 的逐步计算 testbench、软件参考结果逐项比对和 trace 验证尚未完成。

因此，现有 `word_readback.csv` 只能作为单项阶段性记录，不能替代完整的成对联调交付。

## 已完成

1. 盘点了硬件工作区，并记录了 RTL/TB 文件及快照校验信息；本次代码、测试和交接材料将作为一个硬件阶段增量固定到 `hardware` 分支。
2. 现有工程包含 FSM、寄存器接口、缓存管理、分块调度、tile 数据流、结果收集、PE/脉冲阵列及相应模块级 testbench。
3. 增加了 FP32 PE 计算模型草稿，以及 PE/阵列层的 bias 和 trace 信号接口。该部分目前**尚未独立验证**。现有代码用寄存器模拟 8 拍乘法加 4 拍加法延迟，算术函数仍在寄存器前组合计算，不能视为已完成真实 FP32 运算流水线。
4. 生成了 [word_readback.csv](word_readback.csv)：共 144 条数据记录，包含软件样例的矩阵缓存读回信息。测试确认 16-bit 低、高字读回与 FP32 32-bit 数据重组匹配；对应的 9 份 `.mem` 与 `.bin` 输入也已核对一致。
5. 针对当前硬件快照重新运行 `word_readback_tb`，结果为 `PASS rows=145`（含表头行，144 条数据）。当前 RTL/TB 快照 SHA-256：`075343d2eedcf39baf237ca73b1bad7ca2f6113a51a32002e7f0262d8b532c93`；CSV SHA-256：`61adcaf0e057e060a945e5dca11c11746221950809013805988261674c46272b`。
6. 修复 `systolic_array_stress_tb` 未连接新增 bias 端口的问题，并调整回归脚本：无外部样例参数时将 `word_readback_tb` 明确记为跳过。随后全量回归结果为 26 个 testbench 中 25 项通过、0 项失败、1 项跳过（需要外部样例参数的 `word_readback_tb`）；SoC adapter elaboration 通过。`word_readback_tb` 已另行带参数运行并通过。

## 尚未完成及限制

- 没有 `pe_trace.csv`，也没有完成记录每个 K 步骤的 X、W、乘积、累加前值/后值、bias 和最终输出的验证。
- bias 尚未贯通完整计算路径：当前 `systolic_tile_engine` 对阵列提供的是零 bias。
- 全量回归已在当前改动后重跑：26 个 testbench 中 25 项通过、0 项失败、1 项跳过（`word_readback_tb` 在未传入外部样例参数时跳过）；随后该读回测试已带样例参数独立通过。FP32 PE 本身仍无专用计算 trace testbench，因此不应将回归结果解读为 FP32 PE 算术已验证。
- 缓存读回 testbench 直接操作 `matrix_cache_manager`，没有经过 DMA、engine 调度或 SoC 总线；它验证的是局部存储读回，不是完整系统联调。
- 教师方案中的 `X[99,64] × W[64,256] + b[256]` 全层分块计算、结果写回、12 层参数复用及 E203 接入尚未形成经完整验证的端到端实现。

## 两份 CSV 的交付条件

要成对交付，至少还需完成以下工作：

1. 确认软件侧逐步 trace 的运算约定，包括累加顺序、bias 时机、舍入/融合行为及列字段格式。
2. 完成 FP32 PE 专用 testbench，并使用软件提供的向量逐步比对结果，覆盖手算样例、舍入边界和 K 分块边界等用例。
3. 修通 bias 路径，检查 PE/阵列接口及关联 testbench，然后重跑全量回归并修复失败项。
4. 在固定 RTL 快照上重新生成两份 CSV，附上输入与 RTL 指纹、运行命令和测试日志。

两份 CSV 本身可以在完成独立模块级验证后、E203 整机联调之前生成；但若软件侧要求证明 DMA/engine/SoC 端到端数据路径，则还需另行完成相应集成验证。请确认 `word_readback.csv` 的局部缓存读回范围是否符合最小回传要求，以及 PE trace 的字段和浮点运算约定。

## 当前交接材料

- 缓存读回记录：`handoff/word_readback.csv`
- 硬件工作区及源文件指纹：`handoff/hardware_worktree_inventory_2026-10-17.md`
- 当前状态：可提供单份缓存读回阶段记录；完整两份 CSV 暂不可交付。
