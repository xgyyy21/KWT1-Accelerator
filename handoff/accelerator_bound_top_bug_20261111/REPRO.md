# 复现步骤（服务器）

## 0. 目录

```bash
mkdir -p ~/kwt1_final4_full_layer_20261111
cd ~/kwt1_final4_full_layer_20261111
```

把本包 `tb/` 下的两个 TB 拷进来。

## 1. 文件清单

Final4 综合 `files.f` 第 155–158 行使用的 RTL：

```bash
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_mac.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_array_16.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_system_bus_control.sv
~/kwt1_soc_full_synth_sram_final4_20261109/int16_accelerator_top_bound.sv
```

SRAM 模型：

```bash
~/Desktop/admin_public_dir/SRAM_Lib_2025/RAMSP128X16/verilog/RAMSP128X16.v
```

## 2. 通用顶层（对照组，应 PASS）

```bash
cat > repo.f <<'EOF'
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_mac.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_array_16.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_system_bus_control.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_accelerator_top.sv
int16_accelerator_top_tb.sv
EOF

vcs -sverilog -full64 -timescale=1ns/1ps -f repo.f \
  -top int16_accelerator_top_tb -o simv_repo -l vcs_repo.log
./simv_repo -l sim_repo.log
```

期望最后一行：

```
PASS int16_accelerator_top_tb K64_and_K256 PE=16 bus=32 continuous_jobs=2
```

## 3. Final4 绑定顶层（复现问题）

```bash
cat > bound.f <<'EOF'
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_mac.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_array_16.sv
~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_system_bus_control.sv
~/kwt1_soc_full_synth_sram_final4_20261109/int16_accelerator_top_bound.sv
~/Desktop/admin_public_dir/SRAM_Lib_2025/RAMSP128X16/verilog/RAMSP128X16.v
repo_bound_tb.sv
EOF

vcs -sverilog -full64 -timescale=1ns/1ps -f bound.f \
  -top int16_accelerator_top_tb -o simv_bound -l vcs_bound.log
./simv_bound -l sim_bound.log
```

期望：约 5 ms 仿真时间后打印 `TIMEOUT state=8 ... k=63 ... counts=560/560`，退出码非 0。

## 4. 两个 TB 的差别

- `repo_bound_tb.sv` 由 `int16_accelerator_top_tb.sv` 只改两处：
  1. DUT 换成 `int16_accelerator_top_32_11000000_0 #(.CTRL_BASE(32'h0))`；
  2. `always_ff` → `always`（规避 VCS 对 `memory` 多驱动的 `ICPD` 检查）。
- 其它激励、存储模型、期望值完全一致。
