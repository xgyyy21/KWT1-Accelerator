# INT16 layer00 权重复用仿真证据

本目录对应 `handoff/INT16_layer00权重tile跨行复用交接_2026-11-04.md`。

- `layer12_summary.json` 和 `layer_00.log`–`layer_11.log`：12 层 INT16 软件 Golden 对拍；
- `layer00_final_summary.json`、`layer00_final.log`：layer00 最终事务数量断言和输出对拍；
- `top.run.log`：K=64 tile 复用、K=256 原路径、K=64 任务间重新装载、总线错误后缓存失效；
- `int16_pe_mac_tb.run.log`：PE 数值回归；
- `int16_e203_minimal_tb.run.log` 和关联轨迹：E203 adapter 模拟器及地址边界回归；
- `traffic_comparison.json`：原服务器轨迹与本地优化 RTL 的事务计数对比；
- `source_sha256.json`、`evidence_sha256.json`：源码/输入/结果哈希。

工具为本地 Icarus Verilog 14.0 devel。本地总线和 SRAM 均为行为级验证模型；此证据不代表真实 E203、真实宏、综合、150 MHz 或功耗已通过。`.simv/.vvp` 仿真二进制不入库。
