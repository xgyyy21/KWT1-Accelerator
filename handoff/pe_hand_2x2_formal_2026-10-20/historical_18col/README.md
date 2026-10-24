# 单 PE `hand_2x2` 联调材料

这是一份基于当前真实 RTL `fp32_pe_mac` 重新运行得到的最小联调材料，供软件侧逐事件对拍。

## 材料内容

- `rtl/fp32_math_pkg.sv`：FP32 加法/乘法函数依赖。
- `rtl/fp32_pe_mac.sv`：当前单 PE RTL，乘法延迟 8 拍、依赖加法延迟 4 拍，乘法和加法分别舍入，不使用 FMA。
- `tb/fp32_pe_hand_2x2_tb.sv`：真实 DUT 测试平台。4 个输出单元、每个 K=2，共 8 个 MAC 事件和 4 个 bias 事件。
- `replay/pe_trace_raw.csv`：本次运行直接由真实 DUT trace 端口采样得到的原始轨迹。
- `replay/simulation.log`：本次仿真输出。
- `pe_hand_2x2.f`：Icarus Verilog 文件列表。
- `SHA256SUMS.txt`：本资料包文件哈希。

## 复现命令

在仓库根目录执行：

```powershell
& .tools/iverilog/bin/iverilog.exe -g2012 -s fp32_pe_hand_2x2_tb `
  -o build/fp32_pe_hand_2x2_replay.vvp `
  rtl/fp32_math_pkg.sv rtl/fp32_pe_mac.sv tb/fp32_pe_hand_2x2_tb.sv
& .tools/iverilog/bin/vvp.exe build/fp32_pe_hand_2x2_replay.vvp `
  +TRACE_FILE=build/fp32_pe_hand_2x2_replay.csv
```

预期输出：`fp32_pe_hand_2x2_tb PASS cells=4 mac_events=8 bias_events=4`。

## 当前轨迹的边界

`replay/pe_trace_raw.csv` 是真实 PE RTL 的原始采样，当前为 18 列，包含行列、事件、周期、K、输入、乘积、累加前后值、bias 和结果等字段。它还没有按软件侧最终 19 列合同补齐 `tile_id/global_k` 等字段，因此不能直接声明为最终正式 `pe_trace.csv`。

本例中：

- `row/column`：由测试平台遍历 2×2 输出单元产生；
- `trace_k`：单个 K 块内的局部 K，取 0、1；
- `cycle`：RTL 内部采样周期；
- `bias`：K 项全部完成后单独产生一次；
- `task_first`/`task_last`：当前测试用例的首块/末块标记；
- 本例没有跨 K=32 的全局块恢复，因此不能用来证明 K=32 跨块行为。

软件侧应优先使用 `replay/pe_trace_raw.csv` 对照数值和事件顺序；如果需要最终 19 列文件，双方需要先确认字段映射，再由硬件侧重新导出正式格式。

## GitHub 位置

资料包目录：
<https://github.com/xgyyy21/KWT1-Accelerator/tree/hardware/handoff/fp32_hand_2x2_pe_material_2026-10-19>

规范 RTL：
<https://github.com/xgyyy21/KWT1-Accelerator/blob/hardware/rtl/fp32_pe_mac.sv>

规范测试平台：
<https://github.com/xgyyy21/KWT1-Accelerator/blob/hardware/tb/fp32_pe_hand_2x2_tb.sv>
