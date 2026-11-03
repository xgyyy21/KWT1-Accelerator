# INT16 E203 最小任务证据

本目录由 `scripts/Run-Int16E203Minimal.ps1` 生成。仿真使用 Icarus Verilog 14.0，顶层为 `int16_e203_minimal_tb`，输入向量来自 `handoff/int16_e203_minimal_2026-11-03/`。

通过条件：

- 第一轮 `A=0x90000000`、X=1，16 个输出均为 `0040`；
- 第二轮 `A=0x90008000`、X=2，16 个输出均为 `0080`；
- 越界 `0x90040000` 被 adapter 返回 ERROR；
- 总线命令和响应数量相等，响应包含背压等待。

这份证据是本地行为级 RTL 结果，不是服务器真实 E203 或真实 SRAM 宏结果。
