# INT16 PE 结果流水化回归证据

本目录对应 `INT16_PE两周期结果流水化交接_2026-11-04.md`。使用 Icarus Verilog 14.0 devel，重新编译当前 `rtl/files.f` 后运行三个 testbench：

- `int16_pe_mac_tb`：PE 数值和 E0/E1/E2 结果时序，PASS；
- `int16_accelerator_top_tb`：K=64、K=256、连续任务，PASS；
- `int16_e203_minimal_tb`：System Bus/ext2dtcm 最小任务、地址边界和越界错误，PASS。

`.simv` 是本地生成的仿真二进制，不纳入版本控制。`source_sha256.json` 绑定本次 RTL、TB、输入和 filelist，`evidence_sha256.json` 绑定日志与轨迹。
