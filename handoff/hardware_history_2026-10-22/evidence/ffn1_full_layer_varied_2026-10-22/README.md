# FFN1 非均匀输入整层 RTL 联调材料

本材料对应赛题规定的第一层：`X[99,64] × W[64,256] + bias[256]`。本次使用可复现的有限 FP32 非均匀输入，目的是补充上一轮“全部输入为 1.0”测试对位置映射和数值路径覆盖不足的问题。

## 实际结果

- RTL 仿真：Icarus Verilog 14.0 devel；运行日志包含全部最终断言和 `$finish`。本次用启动器异步观察进程结束，但未保留进程退出码，因此不单独报告退出码。
- tile：208 个；每个 tile 2 个 K 块；最后一个行组有效行数为 3。
- 输出：25,344/25,344 与软件参考逐位一致。
- System Bus 写回：50,688/50,688 个半字，地址、顺序、数据均通过检查。
- 输入读取：642,048 个半字。
- 仿真日志末尾的实际断言：
  `PASS: FFN1 full layer m=99 k=64 n=256 tiles=208 outputs=25344 writes=50688 cycles=2587777`
  `PASS: FFN1 read_halfwords=642048 unique_write_halfwords=50688 tail_rows=3 last_write_cycle=2587777 done_cycle=2587779`
- 独立检查器：`comparison_summary.json` 为 PASS，首个差异为 null。

输入 X、W、bias 各包含 12 种有限 FP32 位模式，期望输出包含 1,080 种不同位模式。软件参考采用归档的 `fp32_reference.py`：每次乘法、加法分别按 binary32 舍入，K 从 0 到 63 累加，bias 最后加入一次。

## 文件说明

- `ffn1_output.csv`：25,344 个实际 RTL 最终输出。
- `ffn1_writeback.csv`：50,688 个实际总线半字写回事件。
- `ffn1_tiles.csv`：208 个实际 tile 启动事件。
- `ffn1_x.mem`、`ffn1_w.mem`、`ffn1_bias.mem`：仿真实际加载的低半字优先 SRAM 快照。
- `software_expected_output.csv`：固定软件参考生成的期望值，不是 RTL 输出。
- `input_data/`：生成器使用的完整 32 位输入及期望值。
- `sources/`：本次仿真的 RTL 文件快照和 testbench。
- `comparison_summary.json`：坐标、地址、tile、写回和软件参考逐位核对结果。
- `ffn1.run.log`、`ffn1.run.err.log`：真实仿真日志。
- `compile_reproduction.log`、`iverilog_version.log`、`vvp_version.log`：编译和工具版本记录。

## 复现命令

在材料目录中，具备 Icarus Verilog 14.0 devel 和 Python 3.10+ 的环境中执行。输出目录必须是新的空目录。材料已包含生成好的输入，因此可以直接复跑 RTL：

```powershell
Push-Location sources
& iverilog -g2012 -s fp32_competition_ffn1_tb -o <build-dir>/ffn1.vvp -f rtl/files.f tb/fp32_competition_ffn1_tb.sv
Pop-Location
& vvp -i <build-dir>/ffn1.vvp +OUT_DIR=<new-output-dir> `
  +X_FILE=<material-dir>/input_data/ffn1_x_fp32.mem `
  +W_FILE=<material-dir>/input_data/ffn1_w_fp32.mem `
  +BIAS_FILE=<material-dir>/input_data/ffn1_bias_fp32.mem `
  +EXPECTED_FILE=<material-dir>/input_data/ffn1_expected_fp32.mem
& python -B Check-VariedFfn1.py --package <new-output-dir>
```

`<build-dir>`、`<new-output-dir>` 和 `<material-dir>` 请替换为绝对路径；从材料目录运行检查器时，需先把 `software_expected_output.csv`、`software_reference/` 和 `input_data/` 复制到新输出目录。testbench 的输入文件是 32 位一行，`$readmemh` 读取；testbench 另行输出低半字优先的实际加载快照。完整运行约需几十分钟，不能用软件 CSV 替代仿真。

## 范围和限制

这证明的是当前 protocol-neutral `fp32_accelerator_top` 的一组非均匀有限值 FFN1 RTL 功能路径。软件负责人仍需独立复核。它不等同于真实 E203 NICE/System Bus 接入、真实 SRAM 宏、12 层参数切换、FFN2、物理 8/4 拍时序、综合 PPA 或正式平台验收。NaN、Inf、溢出策略仍需双方冻结。
