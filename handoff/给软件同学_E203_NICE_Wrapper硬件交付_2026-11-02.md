# 给软件同学：E203 NICE Wrapper 硬件交付

日期：2026-11-02
状态：硬件原型已完成本地 mock 仿真；不是 E203/SoC 集成验收

## 本次交付

- Wrapper RTL：[rtl/kwt1_e203_nice_wrapper.sv](../rtl/kwt1_e203_nice_wrapper.sv)
- Wrapper testbench：[tb/kwt1_e203_nice_wrapper_tb.sv](../tb/kwt1_e203_nice_wrapper_tb.sv)
- 编译文件列表：[rtl/files.f](../rtl/files.f)
- 可复现脚本：[scripts/Test-KwtE203NiceWrapper.ps1](../scripts/Test-KwtE203NiceWrapper.ps1)
- NICE wrapper 仿真证据：[evidence/e203_nice_wrapper_2026-11-02/](evidence/e203_nice_wrapper_2026-11-02/)
- 16-bit SRAM/整层集成回归证据：[evidence/sram_16bit_regression_2026-11-02/](evidence/sram_16bit_regression_2026-11-02/)
- E203 公开参考子模块 elaboration 记录与命令：[evidence/e203_reference_2026-11-02/](evidence/e203_reference_2026-11-02/)
- 当前控制接口草案：[control_interface_v2_硬件内部合同_2026-11-01.md](control_interface_v2_硬件内部合同_2026-11-01.md)
- 当前存储布局草案：[memory_layout_v2_硬件内部合同_2026-11-01.md](memory_layout_v2_硬件内部合同_2026-11-01.md)

上述每个证据目录中的 `shared_artifacts_sha256.csv` 校验随仓库提交的证据文件；`source_manifest.csv` 记录仿真源码身份。提交后可通过本文所在的 `hardware` 分支查看这些路径。

## 已验证内容

Icarus Verilog 14.0 (devel) / vvp 14.0 下，`kwt1_e203_nice_wrapper_tb` 编译和仿真退出码均为 0。testbench 检查了配置寄存器读写、START/STATUS/CLEAR、非法 opcode/funct7、未映射/未对齐/超出 8 位寄存器窗口的地址、响应反压保持、忙时读写策略、复位取消未消费响应，以及一项经 wrapper 实际驱动加速器的 1×1 FP32 计算。

该 1×1 任务通过 16-bit System Bus 输入 X=1.0、W=2.0、bias=3.0，输出 5.0；写回检查为 `0x0000`、`0x40a0` 两次半字写入，未发现把 FP32 32 位数据直接接到 16 位 SRAM 的路径。

另有相关回归 9/9 通过，包括 SRAM bridge、16-bit 宏接口计算集成、DMA load、cache streamer、tile 计算、K 分块以及 accelerator top 两个端到端任务；共享 SRAM loader 和 SRAM pin/control 检查通过；顶层异常测试 3 项通过。具体命令、退出码、日志与源文件 SHA-256 见上面的 evidence 目录。

## 本轮硬件暂定选择

以下是为推进独立原型而做的本地决定，不代表软件 ABI 或平台合同已经冻结：

1. NICE 只承载配置、启动和状态控制；矩阵数据继续走现有 16-bit System Bus。NICE ICB memory 请求保持 inactive，`nice_mem_holdup=0`。
2. 默认 opcode=`7'h7b`、funct7=`0`；funct3 `0/1/2/3/4` 暂作 CFG_WRITE/CFG_READ/START/STATUS/CLEAR。它们是可参数化测试编码，需软件确认后才能冻结。
3. CFG 地址是 32-bit `rs1` 中的 byte offset，仅接受 `0x00..0x20` 中已定义的 4-byte 对齐地址；超出该窗口、错位地址返回 wrapper error，不允许高位别名。
4. 忙时 STATUS/配置读取可受理；忙时写、START、CLEAR 立即返回 error。该行为只在 mock 环境验证。
5. START 由 `fp32_accelerator_top` 控制寄存器 bit0 发起；完成/错误经 STATUS 读取，不假设 NICE response 会一直占用到整个计算完成。
6. wrapper 暂按同一 `nice_clk`、低有效 `nice_rst_n` 驱动控制和加速器；复位取消尚未消费的 NICE response，但不清空 SRAM 内容。

## 需要软件侧确认

- 是否接受上述 opcode/funct3 与 `rs1/rs2/rd` 语义；尤其写操作采用“只返回接受/错误”，不返回数据。
- STATUS 位定义与轮询模式是否合适；当前内部状态 bit0=BUSY、bit1=DONE、bit2=ERROR。
- 是否接受 busy 时拒绝写入以及错误的清除方式。
- CPU 侧是否能提供驱动所需的自定义指令编码/编译器发射方式；不能仅凭 opcode 合法就假设软件可发出这些指令。
- 运行真实模型连续多层任务时，需要哪些新的硬件状态/寄存器或中断行为。

## 目前尚未验证

- 没有把本 wrapper 接入真实 E203 NICE 实例，也没有运行 E203/SoC 仿真或 CPU smoke test。
- 没有确认最终服务器中 NICE 指令译码是否会把本原型使用的 funct3/funct7 发给 wrapper。公开参考树 `e203_subsys_nice_core.v` 当前只译码其自带的 `custom3_lbuf/sbuf/rowsum` 示例操作；需确定替换方式或服务器侧译码修改方案。
- 没有验证真实 512 KiB shared SRAM、实际系统总线仲裁/地址窗口/缓存一致性、DMA 与 NICE 并发、超时和总线错误恢复。
- 1×1 wrapper 测试和当前 SRAM 行为模型测试不等于真实 SRAM 宏时序验证；需要综合同学的真实宏模型结果。

## 软件侧下一步

请按上述问题逐项确认或提出修改意见。确认后再冻结 `control_interface_v3` 与驱动合同，并提供一段最小驱动操作序列/预期状态读值，便于硬件加入 CPU-to-wrapper 的联合 testbench。
