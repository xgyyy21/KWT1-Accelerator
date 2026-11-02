# 给软件同学：NICE Wrapper v3 语义复核

日期：2026-11-02  
状态：硬件按 v3 提案完成实现和 mock 回归，邀请软件侧复核；未声称真实 E203 联调

## 本轮变更

- CFG_READ/CFG_WRITE 现在只允许配置寄存器 `0x08..0x20` 中已定义的七个地址；通用访问 CTRL/STATUS 或错误地址时返回 `nice_rsp_err`，不会再对内部无效写操作返回成功。
- START 接受后设置 `start_guard`，直到完成或作业错误才释放。BUSY 尚未拉高的窗口内，重复 START、配置写及 CLEAR 均返回命令错误。
- 命令错误只影响该条 NICE response，不置位 STATUS.ERROR；作业 ERROR 仍由加速器状态寄存器粘滞报告。
- 新 START 在空闲时可作为下一任务入口，并按现有内部寄存器行为清除上次 DONE/ERROR；空闲 CLEAR 也可显式清状态。CLEAR 与 DONE/ERROR 同拍时，事件优先。
- NICE reset 期间 `nice_req_ready` 和 `nice_active` 均被抑制。

## 合同与实现/证据

- 硬件侧完整控制合同提案：[control_interface_v3_硬件提案_2026-11-02.md](control_interface_v3_硬件提案_2026-11-02.md)
- Wrapper RTL：[kwt1_e203_nice_wrapper.sv](../rtl/kwt1_e203_nice_wrapper.sv)
- Wrapper 协议/错误语义 TB：[kwt1_e203_nice_wrapper_tb.sv](../tb/kwt1_e203_nice_wrapper_tb.sv)
- 连续两任务 TB：[kwt1_e203_nice_wrapper_continuous_tb.sv](../tb/kwt1_e203_nice_wrapper_continuous_tb.sv)
- 全 RTL 依赖 source manifest 生成脚本：[Test-KwtE203NiceWrapper.ps1](../scripts/Test-KwtE203NiceWrapper.ps1)
- 连续任务测试脚本：[Test-KwtE203NiceWrapperContinuous.ps1](../scripts/Test-KwtE203NiceWrapperContinuous.ps1)
- 本轮完整运行证据（v4，含源文件快照、哈希、命令、日志和退出码）：[hardware_independent_checks_2026-11-02_v4](evidence/hardware_independent_checks_2026-11-02_v4/)

## 当前测试结果

Icarus/vvp 14.0：Wrapper 协议测试、连续 Wrapper 两任务测试、16-bit SRAM 功能边界测试、顶层连续双任务、顶层异常、SRAM 引脚合同、共享 SRAM loader 共 7 项均通过（进程退出码均为 0）。具体命令、退出码、日志、工具版本、源文件快照及 SHA-256 清单见 v4 evidence 子目录。仿真使用行为级 SRAM 模型，不是供应商宏时序模型；没有运行真实 E203/SoC。

请重点确认：

1. 是否接受“新 START 清旧 DONE/ERROR”，还是要求 ERROR 必须先 CLEAR 才允许新任务。
2. 命令响应错误和作业 STATUS.ERROR 分离是否符合驱动处理预期。
3. STATUS 读取无副作用、未定义高位恒为 0，以及 CLEAR 同周期事件优先规则是否接受。
4. 请提供真实 NICE 指令位级编码、编译/汇编发射样例，以及 CPU 侧如何观察 `nice_rsp_err`。
5. 请确认真实 System Bus 的 word/byte 地址换算、写完成、DONE 后 CPU 读回可见性及缓存维护规则。

本地 mock opcode 仍不是正式 ABI；本地 16-bit word address 也不是 E203 物理地址，软件驱动不要据此硬编码平台参数。
