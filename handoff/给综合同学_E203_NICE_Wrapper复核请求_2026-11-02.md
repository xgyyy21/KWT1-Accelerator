# 给综合同学：E203 NICE Wrapper 复核与下一步接口请求

日期：2026-11-02
状态：请求复核固定 RTL 的结构、综合可接受性和 E203 接入边界

## 请复核的材料

- NICE wrapper：[rtl/kwt1_e203_nice_wrapper.sv](../rtl/kwt1_e203_nice_wrapper.sv)
- 被包装的加速器顶层：[rtl/fp32_accelerator_top.sv](../rtl/fp32_accelerator_top.sv)
- 文件列表：[rtl/files.f](../rtl/files.f)
- NICE wrapper testbench：[tb/kwt1_e203_nice_wrapper_tb.sv](../tb/kwt1_e203_nice_wrapper_tb.sv)
- 可复现脚本：[scripts/Test-KwtE203NiceWrapper.ps1](../scripts/Test-KwtE203NiceWrapper.ps1)
- 仿真与哈希证据：[evidence/e203_nice_wrapper_2026-11-02/](evidence/e203_nice_wrapper_2026-11-02/)
- SRAM/整层回归日志：[evidence/sram_16bit_regression_2026-11-02/](evidence/sram_16bit_regression_2026-11-02/)
- E203 公开参考子模块 elaboration 证据：[evidence/e203_reference_2026-11-02/](evidence/e203_reference_2026-11-02/)
- 公开 E203 参考源码核对记录（本地 checkout：`riscv-mcu/e203_hbirdv2`, branch `master`, HEAD `9f3e34f`）：[E203 NICE core source](https://github.com/riscv-mcu/e203_hbirdv2/blob/9f3e34f/rtl/e203/subsys/e203_subsys_nice_core.v)、[E203 CPU instance](https://github.com/riscv-mcu/e203_hbirdv2/blob/9f3e34f/rtl/e203/core/e203_cpu.v)。此链接是公开参考树，不等价于比赛服务器快照。
- 本地源码核查和子模块 elaboration 结果：[E203参考树核查记录](E203参考树核查_2026-11-02.md)。

## 本地已运行结果

- NICE wrapper mock：PASS，Icarus/vvp 14.0，编译及仿真退出码 0。
- 16-bit SRAM/宏引脚及顶层行为回归：通过，其中 SRAM/compute integration 9/9；顶层异常 3 项通过。
- `fp32_accelerator_top_tb` 的两组端到端任务通过。
- 本轮没有对 FP32 算术进行修改；没有跑综合/STA，也没有使用比赛工艺库或真实 SRAM timing model。

请不要把以上结果表述为 E203 集成、真实 SRAM 宏时序或 PPA 通过。

## 本轮硬件设计决定（待评审）

1. `nice_clk`/低有效 `nice_rst_n` 暂直接驱动整个 accelerator；对公开参考树而言其 `e203_cpu.v` 示例连接到 `clk_aon`/`rst_aon`。比赛服务器时钟/复位网络需你提供实际核对结果。
2. NICE 用于配置/启动/状态，矩阵 payload 用 accelerator 独立 16-bit System Bus master；NICE ICB memory 通道禁用。若平台架构要求 NICE ICB 承担内存请求，需另行做 ICB 到 16-bit shared SRAM 的桥接方案，而不能让现有 wrapper 两条数据路径同时发起。
3. 目前自定义指令默认 `opcode=7'h7b/funct7=0`，funct3 `0..4` 为本地原型编码。公开 E203 示例只识别 funct3=2/funct7=1、funct3=2/funct7=2、funct3=6/funct7=6 三类指令，因此当前代码不能直接假设接到未经修改的示例译码就能工作。请建议服务器中替换、扩展译码还是其他集成边界。
4. 寄存器偏移按 byte offset 处理，必须 4-byte 对齐并严格落在现有 `0x00..0x20` 窗口内；System Bus 请求载荷仍为 16 bit，FP32 通过低/高半字分两次传输。
5. 忙时允许状态/配置读；写和启动/清除返回错误。START 接受与任务完成分离，软件通过 STATUS 轮询。

## 请综合侧提供/确认

- 比赛服务器 `e203_subsys_nice_core` 的真实实例位置与最终连接策略：替换官方示例还是服务器顶层加入 KWT wrapper。
- 服务器构建入口的 filelist、include 搜索路径、宏定义，确认 `E203_HAS_NICE` 在最终比赛配置生效；若可提供准确的可复制编译命令更好。
- `nice_clk/nice_rst_n` 实际连接网络，accelerator 数据时钟是否同域；如异步，需指定 CDC/复位同步责任边界。
- NICE `nice_active`、`nice_mem_holdup` 在比赛 integration 中的使用语义；当前 wrapper 把前者定义为控制事务活动，后者固定为 0。
- 加速器独立 System Bus master 接入共享 SRAM 的真实端口、仲裁、地址单位与响应时序。当前 wrapper 的 `sys_req_addr` 继承 accelerator 内部 word address 约定，尚未转换为平台 byte address。
- 总线错误/超时如何反馈给 accelerator、DONE 后写回数据何时对 CPU 可见、缓存维护要求和 reset/abort 行为。
- 服务器真实 SRAM macro model 与 Liberty/PVT 信息的合法共享/运行路径，便于后续复核宏控制保持及 DC/STA。

## 运行入口

在仓库根目录执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File .\scripts\Test-KwtE203NiceWrapper.ps1
```

脚本默认把新日志写入 `build/kwt_e203_nice_wrapper_2026-11-02_v2`，若目录已存在会拒绝覆盖。完整 SRAM/计算回归日志见 `handoff/evidence/sram_16bit_regression_2026-11-02/`；源身份由各自的 `source_manifest.csv` 记录，仓库内随附证据文件的哈希见 `shared_artifacts_sha256.csv`。

收到服务器集成信息后，硬件下一步是生成贴合服务器真实端口/译码/时钟复位的 adapter，并运行 E203 CPU/SoC smoke test；在此之前不把 standalone wrapper 称为可直接落地的 E203 集成版本。
