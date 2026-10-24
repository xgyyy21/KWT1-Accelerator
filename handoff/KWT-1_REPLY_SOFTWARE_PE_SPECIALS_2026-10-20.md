# KWT-1 硬件回复：单 PE 专项验证新增材料

日期：2026-10-20。对应本轮单 PE 专项任务。全部 GitHub 地址固定到硬件提交 `abe7e167ea62041a48fd8935ca3d8a9d224cc731`，不随分支变化。仓库为私有，请登录团队账号查看。

软件同学好：这次在原 `hand_2x2` 正式 19 列材料之外，新增了真实的非融合舍入测试、K=64 实际两块 K=32 测试，以及正负零/次正规数等边界测试。PE 运算 RTL 没有修改；新增了 testbench、可复现脚本、证据和检查程序。下面区分软件原有向量与硬件侧新增向量，便于独立验收。

## 一、入口和结果概览

- [完整新增材料包](https://github.com/xgyyy21/KWT1-Accelerator/tree/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20)
- [README 和复现说明](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/README.md)
- [总报告：逐例结果和未覆盖范围](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/run_report.json)
- [硬件侧任务总结](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/PE_SPECIAL_VALIDATION_SUMMARY_2026-10-20.md)
- [所有用例、维度、输入和黄金哈希](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/cases.json)

固定比较器把全部软件原有用例逐事件比较为 `BIT-EXACT-CANDIDATE`，本地没有差异；K=64 两块用例产生 64 个 MAC 加 1 个 bias。`rounding_nonfused` 产生 2 个 MAC 加 1 个 bias。所有新增真实 CSV 均为 19 列。这里的本地比较不替代软件侧独立验收。

## 二、逐项交付

### 1. 软件原有 `rounding_nonfused`

| 材料 | GitHub |
|---|---|
| 正式 19 列真实 RTL CSV | [pe_trace.csv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/rounding_nonfused/pe_trace.csv) |
| 软件原版比较报告 | [compare_report.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/rounding_nonfused/compare_report.json) |
| 比较器完整输出 | [compare.log](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/rounding_nonfused/compare.log) |
| 完整仿真记录 | [simulation.log](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/rounding_nonfused/simulation.log) |
| 周期级信号 | [signal_trace.csv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/rounding_nonfused/signal_trace.csv) |
| 用例输入与软件 manifest | [rounding 输入目录](https://github.com/xgyyy21/KWT1-Accelerator/tree/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/inputs) |
| 实际加载输入校验 | [input_validation.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/rounding_nonfused/input_validation.json) |

这还是软件提供的原用例。预期区分点是每次乘法和加法分别舍入，最终结果为正零；不会将 FMA 路径误当成本合同结果。

### 2. 软件原有 K=64 `k32_boundary`

| 材料 | GitHub |
|---|---|
| 正式 19 列真实 RTL CSV | [pe_trace.csv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/k32_boundary/pe_trace.csv) |
| 跨块、周期和累加保持报告 | [timing_and_boundary_report.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/k32_boundary/timing_and_boundary_report.json) |
| 软件原版比较报告 | [compare_report.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/k32_boundary/compare_report.json) |
| 周期级有效信号、块号与累加器记录 | [signal_trace.csv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/k32_boundary/signal_trace.csv) |
| 完整仿真日志 | [simulation.log](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/k32_boundary/simulation.log) |
| 实际加载输入校验 | [input_validation.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/k32_boundary/input_validation.json) |
| 软件原有 K=64 输入及 golden | [inputs 目录](https://github.com/xgyyy21/KWT1-Accelerator/tree/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/inputs) |

验证的是同一个物理 PE 容量 K=32，实际接收两块、总 K=64；第二块重新使用块内 `trace_k=0..31`，CSV 全局 k 由实测块编号与块内 k 合成并检查，`tile_id=global_k//32`。第一块 k=31 提交的部分和为 `0x40000000`（+2）；块间等待 9 个 enable=0 时钟，不复位、不清零，期间累加器保持 +2；第二块 k=32 的 `acc_before` 仍为 +2，加入 -3 后 `acc_after=0xbf800000`（-1）；全部 64 项之后 bias 只提交一次，最终 `0xbf400000`（-0.75）。

这是 PE 累加寄存器跨块保持证据，不是 SRAM 部分和保存、读回、恢复证据。

### 3. 正负零、极小数专项（硬件侧新增向量）

| 材料 | GitHub |
|---|---|
| 真实 RTL 19 列 CSV | [pe_trace.csv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/finite_boundaries_hardware_added/pe_trace.csv) |
| 比较报告 | [compare_report.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/finite_boundaries_hardware_added/compare_report.json) |
| 实际加载输入校验 | [input_validation.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/finite_boundaries_hardware_added/input_validation.json) |
| 新增向量独立 manifest | [boundary_inputs/manifest.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/boundary_inputs/manifest.json) |
| 新增向量黄金轨迹 | [boundary_inputs/expected_traces.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/boundary_inputs/expected_traces.json) |
| 样本覆盖统计 | [boundary_vector_coverage.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/boundary_vector_coverage.json) |

这是硬件侧新增的有限值向量，黄金由随包固定的原版软件整数参考生成，不是软件已有 case，也尚未经软件负责人单独接受。该用例共 256 个逻辑输出，单 PE 顺序计算；比较为 512 MAC、256 bias 事件。另有 24,713 组定向与固定种子有限值输入对，每组各检查一次 RTL FP32 加法及乘法。统计含次正规数输入/结果及正负零，具体见覆盖报告。此为样本测试，非穷举证明。

### 4. 源码、来源、命令、工具和哈希

| 材料 | GitHub |
|---|---|
| 正式 PE 专项 testbench | [fp32_pe_special_tb.sv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/tb/fp32_pe_special_tb.sv) |
| FP32 边界 testbench | [fp32_math_boundary_tb.sv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/tb/fp32_math_boundary_tb.sv) |
| 实际编译 PE 源码快照 | [sources/rtl/fp32_pe_mac.sv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/sources/rtl/fp32_pe_mac.sv) |
| 实际编译数学实现快照 | [sources/rtl/fp32_math_pkg.sv](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/sources/rtl/fp32_math_pkg.sv) |
| 两个实际编译 testbench 快照 | [sources/tb](https://github.com/xgyyy21/KWT1-Accelerator/tree/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/sources/tb) |
| 编译文件列表 | [filelist.f](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/filelist.f) |
| 基线、dirty 原因、所有编译源码哈希 | [provenance.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/provenance.json) |
| 每条实际命令和运行目录 | [commands.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/commands.json) |
| Icarus 版本 | [iverilog_version.log](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/iverilog_version.log) |
| vvp 版本 | [vvp_version.log](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/vvp_version.log) |
| Python 版本 | [python_version.json](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/python_version.json) |
| 全包逐文件 SHA-256 | [SHA256SUMS.txt](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/SHA256SUMS.txt) |
| 可移植复现脚本 | [Replay-Special.py](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/Replay-Special.py) |
| 本地使用的组包/复现脚本 | [Run-PeSpecialValidation.py](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/scripts/Run-PeSpecialValidation.py) |

来源信息如实记录为硬件基线 `9941d8a5981dfdbd851b1e92a0ebc2cdef39f8e8+dirty`：生成轨迹时新测试尚未提交，包中带有编译所用源文件快照及 SHA-256；PE 数学 RTL 与该基线一致。本次归档提交不回写 CSV 的历史运行来源字段。

### 5. 测试程序自检与旧 PE 冒烟测试

- [14 项验证器自测日志](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/validator_tests.log)：对错误 tile/global-k、丢失部分和、块间 reset/clear、重复 bias、错误 valid/周期/延迟等人工破坏副本均检查为拒绝。这些是检查脚本的负向测试，不是额外硬件实测。
- [6 项旧 PE/小阵列定向回归汇总](https://github.com/xgyyy21/KWT1-Accelerator/blob/abe7e167ea62041a48fd8935ca3d8a9d224cc731/handoff/pe_special_validation_2026-10-20/replay/legacy_pe_sanity/run_report.json)：PE trace、旧 K-block、hand_2x2、MAC boundary、2×2 和 K64 小阵列测试通过。每项编译及仿真日志均在同目录。该汇总不是整个项目 49/50 项回归，也不是新软件边界向量的阵列验收。

从包目录复现需 Python 3.10+ 与 Icarus Verilog，无需 NumPy 或联网。输出到一个新目录，不覆盖归档包：

```powershell
python -B .\Replay-Special.py --replay --output D:\your_work\pe_special_replay_new `
  --iverilog C:\your_tools\iverilog.exe --vvp C:\your_tools\vvp.exe
```

## 三、边界和请软件侧回传

目前只有**单 PE 功能仿真**证据；对软件现有向量的本地工具状态为 `BIT-EXACT-CANDIDATE`。请软件侧独立复跑/核对，并回传使用的软件提交、命令、期望与实际事件数、逐位比较结果和首个差异（若有）。硬件新增 `finite_boundaries_hardware_added` 向量请单独确认是否采用联合验收。

本轮没有验证 SRAM 存储/读回/恢复、完整 8×16 阵列、新向量的阵列行为、完整矩阵层、E203/SoC 实接或 150 MHz 物理时序。NaN、Inf、溢出仍是当前 FP32 合同范围外；有限值样本测试也不构成对全部 2³² 位模式的穷举保证。

上一轮 `hand_2x2` 19 列材料仍在 [旧单 PE 交付包](https://github.com/xgyyy21/KWT1-Accelerator/tree/c280b5e0200a59d23c1bf67a9beac0f901770efd/handoff/pe_hand_2x2_formal_2026-10-20)，本次没有覆盖或改写它。
