# INT16 本地回归证据

工具：Icarus Verilog 14.0 devel。测试均使用当前 `rtl/files.f`。

- `int16_pe_mac_tb.run.log`：PE 数值、RNE、饱和、非法 `0x8000` 和 K=64/K_TILE=32 延续，PASS。
- `int16_accelerator_top_tb.run.log`：K=64、K=256 及不复位连续两任务，PASS。

`.simv` 文件为本地生成的仿真二进制，不纳入版本控制；如需复现，请运行 `scripts/Run-Int16E203Minimal.ps1` 或使用同样的 Icarus 命令重新编译。
