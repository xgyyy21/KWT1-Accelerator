# KWT-1 硬件侧交付包：无 E203 条件下的可复现材料

日期：2026-10-20

本包用于软件侧继续编写驱动和验收脚本。它固定了当前硬件内部原型、阵列轨迹、SRAM 检查点实验和可复现仿真证据，但**没有把内部原型冒充成正式 E203 平台接口**。

本目录的 GitHub 版本保留源码、CSV、文档和日志；原始 ZIP 归档因仓库忽略规则未上传，完整归档仍保留在本地 `D:\competition\handoff`，其 SHA-256 记录在本地交付包中。

## 交付结论

### 已实现

- 8×16 FP32 PE 阵列，PE 坐标、K 分块、边界补零和 bias 事件可记录。
- 跨 K 块部分和默认由 PE accumulator 寄存器保持，最终值进入 `result_stage`。
- 16 位字地址、FP32 低半字优先、X/W/bias/Y 行主序的内部布局。
- 阵列级 SRAM checkpoint 实验：保存、复位、读回、恢复并继续计算。
- 协议中立的 NICE 控制面和 System-Bus 数据面原型。

### 已实际仿真通过

- 四组阵列轨迹：共 13,531 个事件；软件侧已逐事件核验 13,531/13,531。
- 单 PE 特殊值、K 边界、8×16 阵列、K=64、K=256 八块计算。
- 8×16 阵列 checkpoint：512 次写、512 次读请求、512 次读响应，恢复 128 个 PE 后继续计算，128 个结果均为 `0x42c20000`。
- checkpoint 还输出了 128 个 PE 的逐项实际结果：`evidence/checkpoint_result_per_pe.csv`，每个 `(row,column)` 一行。
- 协议中立接口三次小任务：输出 9 个，DONE 晚于最后写握手，背压检查通过。
- 单个 8×16 tile、K=64 的完整顶层路径已实际仿真通过；输出 128 个、写回 256 个半字。
- `fp32_competition_ffn1_tb.sv` 已编译；全尺寸顶层仿真在 Icarus 下运行过慢，本轮未产生 PASS，故不列为通过。

## 本包包含

- `docs/memory_layout_v1_internal.md`：内部存储布局和平台待确认项。
- `docs/control_interface_v1_internal.md`：内部控制寄存器、握手和 DONE/ERROR 原型。
- `docs/special_value_and_error_policy_v1.md`：NaN/Inf/溢出、总线错误和恢复的当前建议。
- `docs/test_and_acceptance_matrix.md`：已通过、软件侧核验、未通过和待平台确认的清单。
- `rtl/`、`tb/`：本轮实际使用的 RTL 与 testbench 快照。
- `evidence/array_pe_trace_2026-10-20_v2.zip`：19 列阵列轨迹证据包。
- `evidence/partial_sum_checkpoint_2026-10-20_v4.zip`：阵列级 SRAM checkpoint 证据包。
- `evidence/interface_v1_evidence_2026-10-20_run2.zip`：协议中立接口和读回证据包。
- `evidence/pe_trace.csv`、`evidence/word_readback.csv`：软件侧最小回传文件。
- `evidence/checkpoint_result_per_pe.csv`：128 个 PE 的逐项 checkpoint 恢复后结果。
- `evidence/checkpoint_per_pe/`：该 CSV 的编译日志、实际仿真日志和输入来源说明。
- `evidence/one_tile_k64/`：单 tile 完整路径的编译日志、PASS 日志和 testbench。
- `evidence/regression_20261020/`：本轮关键 testbench 的编译与仿真日志。
- `SHA256SUMS.txt`：本包全部文件的 SHA-256。

## 明确不在本包中冻结的内容

真实 E203 NICE 指令编码、真实 NICE 握手、System Bus 物理地址窗口、CPU 字节地址转换、Cache/写缓冲 drain/fence、平台 SRAM 宏时序以及 SoC 级端到端结果仍需平台负责人提供或确认。NaN、Inf 和溢出是否禁止、饱和还是置 ERROR，也需要双方签字确认。

## 复现入口

在 `D:\competition` 下使用项目自带 Icarus：

```powershell
& 'D:\competition\.tools\iverilog\bin\iverilog.exe' -g2012 -s fp32_pe_array_8x16_tb -o build\check.vvp -f rtl\files.f tb\fp32_pe_array_8x16_tb.sv
& 'D:\competition\.tools\iverilog\bin\vvp.exe' build\check.vvp
```

全尺寸第一层 testbench 是 `tb/fp32_competition_ffn1_tb.sv`。它当前只证明了可编译，因 Icarus 运行时间过长未得到 PASS；请勿把它写入正式通过数。
