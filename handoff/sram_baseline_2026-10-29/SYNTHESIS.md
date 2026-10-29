# 给综合同学：PE 试改前固定基线

请使用包含本文件的 `hardware` 提交，源码清单见 [published_source_manifest.csv](published_source_manifest.csv)。主入口是仓库根目录的 `rtl/fp32_accelerator_top.sv` 和 `rtl/files.f`。

固定参数：`ADDR_WIDTH=32`、`DATA_WIDTH=32`、`STRICT_COMPETITION_SHAPES=1`、**`USE_SRAM_MACROS=1`**（源码默认0，必须显式覆盖）。内部 tile8×16、K_TILE32、K_BLOCKS8；所有 System Bus/宏数据端口均16bit。

顶层目前导出24组宏引脚，**没有实例化真实 SRAM 宏**；需要综合侧的平台 wrapper 连接真实128×16宏与时钟，提供 Liberty/LEF 等库信息。RTL 不能凭空代表 SRAM 面积和时序。主 filelist 不含 `rtl/prototype/fp32_bus_fault_guard.sv`；`tb/` 功能模型不得综合为真实存储。

- [宏引脚表、时钟复位、参数和完整 warning 说明](docs/给综合同学_固定RTL与16位SRAM交接材料_2026-10-29.md)
- [探索时钟约束](constraints/fp32_sram_exploratory.sdc)：150 MHz / 6.666667 ns；尚需平台 IO、时钟不确定度、负载和 SRAM 宏 PVT 条件
- [宏模式 lint 日志](evidence/sram_macro_mode_lint_2026-10-29_v1/lint.log)
- [命令](evidence/sram_macro_mode_lint_2026-10-29_v1/command.txt)、[工具版本](evidence/sram_macro_mode_lint_2026-10-29_v1/tool_version.txt)、[退出码](evidence/sram_macro_mode_lint_2026-10-29_v1/exit_code.txt)
- [两完整任务实际仿真日志](evidence/sram_two_layers_verilator_2026-10-29_v1/simulation.log)

宏模式 Verilator lint 退出码1，110 warning：60 WIDTHEXPAND、21 WIDTHTRUNC、14 TIMESCALEMOD、10 PINMISSING、5 MULTIDRIVEN。MULTIDRIVEN 与 DMA sequencer 在 task/always_ff 对同一状态变量赋值有关，仍待前端修正及回归，不能写为综合通过。

当前 PE 8拍乘法和4拍加法仍是功能延迟结构，完整 `fp32_mul/fp32_add` 在第一级结果寄存器前计算；未完成算术内部流水化。综合同学已报告的 K32 单PE Yosys/ABC 成功是其测试范围，未据此扩大为本完整宏模式顶层综合/150MHz通过；当前包没有收到其脚本、网表或目标库 STA。请下一轮记录对应 Git 提交、参数、脚本与工具日志。

当前数值合同和已验收历史用于后续流水化比较。新实现需重新核查 FP32 数值、valid及元数据对齐、逐项累加顺序、跨 K 块与新任务清理，然后重新做综合/时序比较。此提交只固定当前成果，不进行算术流水改写。
