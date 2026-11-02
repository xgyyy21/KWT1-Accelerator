# 给综合/平台同学：E203 NICE Wrapper v3 修订复核

日期：2026-11-02  
状态：请复核修订后 standalone RTL；本轮未运行 Yosys/Slang，也未完成 E203/SoC 集成

## 本轮硬件侧修改

- Wrapper 限定支持 `E203_XLEN=32`、`E203_ADDR_SIZE=32`，不再让参数化声明暗示其他位宽已验证。
- CFG_READ/CFG_WRITE 严格按配置寄存器权限过滤；STATUS/CTRL 不能通过通用配置操作访问。
- START-to-BUSY 启动保护窗口及整个任务期间由 `start_guard` 防止重复写/启动/清除；命令拒绝通过 NICE response error 返回，不污染作业 STATUS.ERROR。
- START 接受与完成分离；新 START 清上次粘滞 DONE/ERROR。CLEAR 与同周期事件的优先级已在合同及 TB 中固定为“事件优先”。
- NICE reset 期间 request-ready/active 被抑制。

## 复核文件和运行证据

- v3 语义提案：[control_interface_v3_硬件提案_2026-11-02.md](control_interface_v3_硬件提案_2026-11-02.md)
- Wrapper RTL：[rtl/kwt1_e203_nice_wrapper.sv](../rtl/kwt1_e203_nice_wrapper.sv)
- E203-shaped adapter 骨架：[rtl/kwt1_e203_nice_adapter.sv](../rtl/kwt1_e203_nice_adapter.sv)
- 主协议 TB：[tb/kwt1_e203_nice_wrapper_tb.sv](../tb/kwt1_e203_nice_wrapper_tb.sv)
- 连续双任务 TB：[tb/kwt1_e203_nice_wrapper_continuous_tb.sv](../tb/kwt1_e203_nice_wrapper_continuous_tb.sv)
- 全 RTL 编译依赖哈希脚本：[scripts/Test-KwtE203NiceWrapper.ps1](../scripts/Test-KwtE203NiceWrapper.ps1)
- 连续任务回归入口：[scripts/Test-HardwareIndependentChecks.ps1](../scripts/Test-HardwareIndependentChecks.ps1)
- 本轮完整命令/退出码/日志/源快照/哈希：[hardware_independent_checks_2026-11-02_v4](evidence/hardware_independent_checks_2026-11-02_v4/)

Wrapper 测试脚本的 `source_manifest.csv` 展开 `rtl/files.f` 并记录全部 RTL 输入，再附加 TB 与运行脚本；不是只记录 Wrapper 和 filelist 文件本身。v4 证据包含运行时使用的完整源快照、文件哈希、工具版本、命令和日志。当前工作尚未生成新的 Git commit SHA，证据通过哈希固定本轮本地文件。

## 本轮验证边界

- Icarus/vvp 14.0 功能仿真测试通过，包含命令权限/错误分类、启动窗口、CLEAR 优先级、response 背压、连续两任务和 16-bit 写回。
- SRAM 测试使用项目功能模型，覆盖 127/128/1023、读响应阻塞、standby、reset 保留；不证明供应商宏时序或 PVT 合法性。
- 按硬件负责人要求，**未运行 Yosys/Slang**。此前已有的 Wrapper 单体结构检查报告不等于本轮修改后结构检查通过。
- 未连接服务器 `e203_subsys_nice_core`，未运行 CPU/SoC smoke test 或真实 shared SRAM。

请继续确认：比赛真实 E203 的译码/实例接入边界、实际时钟复位、System Bus 地址和仲裁/写完成合同、NICE error 对 CPU 的可见性，以及真实 SRAM 模型和比赛 PVT/宏参数配置。也请确认采用“拆分 NICE 控制 adapter 与 SoC 数据面”的集成方向。
