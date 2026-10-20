# 任务一完成总结：单 PE 剩余专项验证

日期：2026-10-20。状态：本地专项验证完成，等待软件负责人独立复核。本轮未 commit、未 push，团队仓库仍为 `9941d8a5981dfdbd851b1e92a0ebc2cdef39f8e8`。

## 一句话结论

我们把原来只证明“两项相乘后累加”的小测试，扩展到了真实的两个 32 项块连续计算，并补测了独立舍入、正负零和极小数。现有 PE 在本轮样本上全部通过，因此没有修改 PE 的计算逻辑；新增的是测试框架、检查程序和真实仿真证据。

这不等于所有 FP32 输入都测完，也不等于阵列、整层、SRAM 保存恢复、E203 或综合通过。

## 1. 三个小任务的实际结果

| 小任务 | 实际验证 | 结果 |
|---|---|---|
| 乘法、加法分别舍入 | 运行软件原始 `rounding_nonfused` 输入；2 个 MAC、1 个 bias | 3 个事件逐位匹配，最终 `0x00000000`（正零）。错误融合第二次乘加会留下非零负数，因此本例能区分两种计算方式 |
| K=64 分成两个 K=32 块 | PE 实际参数 K=32；第一个块完成后等待，再送第二块；64 个 MAC、1 个 bias | 65 个事件逐位匹配。第一个块末尾 +2，第二块继承 +2，首项加 -3 后变 -1，最终加一次 +0.25，得到 -0.75 |
| 正负零、极小数等边界 | 新增 32 行×8 列逻辑输出，由单个物理 PE 顺序计算；另用软件整数参考检查加法/乘法 | 256 个输出、768 个真实事件逐位匹配；24,713 组输入均通过，每组各检查一次加法和乘法 |

作为测试框架的基线，还重新运行了软件 `hand_2x2`：12 个事件逐位匹配。四组共 848 个真实事件，全部为 19 列，比较时显式启用 `--compare-tile-id`。

比较器输出名称保留为 `BIT-EXACT-CANDIDATE`。这是本地使用固定软件工具的结果，不冒充软件负责人已经独立验收。

## 2. 最重要的跨块证据

| 实际事件 | 周期 | 位模式/含义 |
|---|---|---|
| 第 31 项（第一块最后一项）提交 | 209 | 累加结果 `0x40000000`，即 +2 |
| 等待期间 | 两块之间 | 9 个 enable=0 的时钟，累加寄存器保持 +2；没有复位、清零、提前输出或 bias |
| 第 32 项（第二块第一项）接受 | 219 | 来自第二个真实块，块内 k 从 0 开始 |
| 第 32 项提交 | 271 | `acc_before=0x40000000`，`acc_after=0xbf800000`，即 +2 加 -3 得到 -1 |
| 最终 bias | 全部 64 项之后 | 只提交一次，结果 `0xbf400000`，即 -0.75 |

`trace_k` 是 DUT 的块内索引；测试框架结合实际驱动的块编号导出全局 k，并核对接受、乘法、加法及提交次序。不是把一次连续 64 项计算在 CSV 中简单贴成两个 tile。

这次跨块结果保存在 **PE 的累加寄存器**。没有进行 SRAM 部分和保存/读回/恢复，不能把两者混为一谈。

## 3. 文件在哪里

完整材料包：[pe_special_validation_2026-10-20](pe_special_validation_2026-10-20/README.md)。

| 材料 | 本地路径 |
|---|---|
| 非融合舍入真实 19 列 CSV | [rounding_nonfused/pe_trace.csv](pe_special_validation_2026-10-20/replay/rounding_nonfused/pe_trace.csv) |
| K=64 两块真实 19 列 CSV | [k32_boundary/pe_trace.csv](pe_special_validation_2026-10-20/replay/k32_boundary/pe_trace.csv) |
| 跨块和周期检查报告 | [timing_and_boundary_report.json](pe_special_validation_2026-10-20/replay/k32_boundary/timing_and_boundary_report.json) |
| 跨块完整仿真日志 | [simulation.log](pe_special_validation_2026-10-20/replay/k32_boundary/simulation.log) |
| 跨块周期级辅助信号 | [signal_trace.csv](pe_special_validation_2026-10-20/replay/k32_boundary/signal_trace.csv) |
| 新增边界真实 CSV | [finite_boundaries_hardware_added/pe_trace.csv](pe_special_validation_2026-10-20/replay/finite_boundaries_hardware_added/pe_trace.csv) |
| 原始软件输入 | [inputs/manifest.json](pe_special_validation_2026-10-20/inputs/manifest.json) |
| 硬件新增输入，单独标明身份和哈希 | [boundary_inputs/manifest.json](pe_special_validation_2026-10-20/boundary_inputs/manifest.json) |
| 各用例、维度、输入与黄金哈希 | [cases.json](pe_special_validation_2026-10-20/cases.json) |
| 源码快照、基线和 dirty 原因 | [provenance.json](pe_special_validation_2026-10-20/provenance.json) |
| 编译文件清单 | [filelist.f](pe_special_validation_2026-10-20/filelist.f) |
| 实际命令、工作目录和日志位置 | [commands.json](pe_special_validation_2026-10-20/replay/commands.json) |
| 总结果及未验证范围 | [run_report.json](pe_special_validation_2026-10-20/replay/run_report.json) |
| 数值样本覆盖统计 | [boundary_vector_coverage.json](pe_special_validation_2026-10-20/boundary_vector_coverage.json) |
| 逐文件哈希 | [SHA256SUMS.txt](pe_special_validation_2026-10-20/SHA256SUMS.txt) |

每个 PE 用例目录均包含实际输入校验、编译日志、仿真日志、软件比较日志与报告。工具版本在包内 `replay/iverilog_version.log`、`vvp_version.log`、`python_version.json`。

本轮 CSV 仍如实记录 `9941d8a5981dfdbd851b1e92a0ebc2cdef39f8e8+dirty`：新增测试尚未提交。实际编译的 RTL 和 TB 快照、哈希已保存。两个计算 RTL 文件与该基线 Git blob 相同，没有为通过测试偷偷更改计算算法。

## 4. 检查测试程序本身，以及复跑

- 对跨块检查程序执行 14 项测试，其中包含正确材料及人为破坏复制品的测试。错误全局 k、tile、丢失部分和、块间复位/清零、重复 bias、错误有效信号和周期等均被拒绝。此类人为破坏不是新增硬件测量证据。日志：[validator_tests.log](pe_special_validation_2026-10-20/replay/validator_tests.log)。
- 从包内源码向独立目录 `build/pe_special_independent_replay_2026-10-20/` 重新编译、仿真、比较、检查周期。四份正式 CSV 与原始交付逐字节相同。
- 已验证包内 131 个文件的 SHA-256；旧 K=2 交付包没有修改。
- 原有六项 PE/小阵列相关测试也实际运行通过：`fp32_pe_trace_tb`、`fp32_pe_kblock_tb`、`fp32_pe_hand_2x2_tb`、`fp32_mac_boundary_tb`、`fp32_pe_array_2x2_tb`、`fp32_pe_array_k64_tb`。日志和报告已一并归档于 [legacy_pe_sanity](pe_special_validation_2026-10-20/replay/legacy_pe_sanity/)。这是六项针对性检查，不是全项目回归，也不是新增软件向量的阵列正式验收。
- 编译器关于 RTL 中 `$fatal` 不能综合的警告原样保留在编译日志；本轮不据此声称综合成功。

新增源码：

- `tb/fp32_pe_special_tb.sv`：可配置维度、真实 K=32 分块、文件输入和实际信号采集。
- `tb/fp32_math_boundary_tb.sv`：独立软件整数参考产生的定向/随机数值检查。
- `scripts/Run-PeSpecialValidation.py`：组包、运行、校验和报告；不 commit、不 push。
- `scripts/Test-PeSpecialValidator.py`：对检查程序进行负向测试。

完整材料包可脱离原始工作目录复现。Python 3.10+、Icarus Verilog，无需 NumPy、无需网络。从包目录执行，工具路径按实际环境替换，输出目录必须尚不存在：

```powershell
python -B .\Replay-Special.py --replay --output D:\your_work\pe_special_replay_new `
  --iverilog C:\your_tools\iverilog.exe --vvp C:\your_tools\vvp.exe
```

## 5. 边界说明与下一步

数值专项含 10,061 组次正规数输入、1,797 个次正规加法结果、1,986 个次正规乘法结果、4,177 个负零乘法结果，以及负零加负零等定向检查。这只是样本覆盖；不宣称全部有限 FP32 都正确。NaN、Inf、溢出仍在双方当前数值合同之外，本轮不把它们算成通过。

硬件新增边界向量使用自己的 manifest 和黄金 JSON 哈希，明确区分于软件原有三组向量。它们由固定软件参考生成，但是否纳入正式联合验收，需要软件负责人独立确认。

这轮已达到任务一的本地完成标准。接下来：

1. 软件侧独立复核本轮的非融合舍入与 K=32 跨块材料，并确认新增边界向量；仍未对外推送这批新材料。
2. 硬件继续任务三，用软件向量验证 8×16 阵列和多块运算，不把已有小阵列测试自动扩大为正式验收。
3. 后续再完成整层、真实平台及综合。8/4 拍仍只是功能边界，不证明 150 MHz 物理时序已经满足。
