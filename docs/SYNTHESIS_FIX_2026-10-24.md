# FP32 RTL 综合阻塞修复（2026-10-24）

## 修复内容

1. `rtl/fp32_pe_mac.sv`：将“一个 K 块收到超过 K 个输入”的 `$fatal` 限定在未定义 `SYNTHESIS` 时编译。仿真仍保留协议保护，综合前端不再看到运行态系统任务；乘加数据通路未改动。
2. `rtl/fp32_tile_cache_streamer.sv`：删除模块级共享的 `r/c` 循环变量，在 `always_comb` 和 `always_ff` 内分别声明过程局部变量，避免严格 HDL 前端把它们识别为跨过程多重赋值。

## 未修改

- `rtl/files.f` 未改变，仍作为固定编译入口。
- 端口、地址计算、FP32 舍入规则、tile 调度和写回路径未修改。
- `events_this_cycle` 的复位告警和 8+4 延迟结构的真实物理流水问题未在本补丁中处理；它们属于后续综合/时序任务。

## 验证

- `iverilog -g2012 -DSYNTHESIS` 编译 `fp32_tile_cache_streamer_tb`：退出码 0。
- `iverilog -g2012 -DSYNTHESIS` 编译 `fp32_competition_ffn1_tb`：退出码 0；保留已知 constant-select 仿真提示。
- `fp32_tile_cache_streamer_tb`：PASS，退出码 0。
- `fp32_pe_array_k64_tb`：PASS，128 个 PE、K=64，结果 65.0，退出码 0。
- 99×64×256 整层仿真已启动并观察到 tile 2/512 次写回且 `error=0`，因长时间运行主动停止；本次不宣称整层 PASS。

当前环境未提供可调用的 Yosys/Slang，因此综合前端结果需由综合同学在固定提交上复跑。

