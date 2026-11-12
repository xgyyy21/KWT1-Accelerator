# KWT-1 Final4 交接文档（2026-11-12 定稿）

> 本文件只做三件事：**文件在哪、做完了什么、还差什么**。
> 所有数字都带证据文件；未完成项不写成完成。

---

## 1. 一句话状态

- **量化/数值**：格式已冻结（INT16、48 位累加），官方 600 样本待组委会；本地 100 样本预评估 12 层最大 NRMSE **0.659%**。
- **综合**：Final4 全 SoC 网表完成，**GTECH=0**、115,978 cells、加速器 **148,013 µm²（0.148 mm²）**、setup 0.00 ns / hold **−0.24 ns**（pre-layout）。
- **门级**：加速器块级 **PASS**；整机门级**已能启动并正确取指**，但停在第 4 次 FETCH，**未 TEST PASS**。
- **未做**：LEC、Final4 网表功耗、官方 600 样本、整机端到端吞吐。

---

## 2. 本地目录（`D:\KWT1-Accelerator\final4_report_20261111\`）

| 目录 / 文件 | 用途 | 关键内容 |
|---|---|---|
| `REPORT_DRAFT.md` | **主报告**（八节 + 摘要 + 完成度 + 夜间失败记录） | 全部数字与口径 |
| `REPORT_QUANT_ARCH.md` | **量化与架构专题报告**（370 行） | 格式合同、精度、PE 阵列、存储层次、面积 |
| `OPEN_ITEMS.md` | 未完成事项登记 | OPEN-1 整机门级 |
| `numeric_format_audit/` | 任务①数值格式审计 | `NUMERIC_FORMAT_RESULT.md`、`numeric_format_table.csv`、12 层向量、`verify_int16_package.log`、`src/`（合同/量化/脚本） |
| `nrmse_verification/` | NRMSE 复算与 100 样本预评估 | `NRMSE_RESULT.md`、`layer_nrmse.csv`、`frozen_ref/`（冻结配置+4 个文件比对）、`scv2_100/`（100 样本结果+manifest+日志+`NRMSE_100.md`） |
| `block_synth_20261111/` | 块级综合 | `RESULT.md`、`synth_*.tcl`、`newfix/`（新加速器 RTL 副本） |
| `full_layer_test/` | 块级整层 TB + 门级调试 | `RESULT.md`、`GATE_DEBUG.md`（§3.9 为最新门级结论） |
| `itcm_preload_20261111/` | ITCM 预装/模型补丁 | `pack_itcm_inter.py`、`trace_monitor.v`、`patch_ram_model.py` |
| `handoff_to_hw_20261111/` | 给硬件的交接 | `BUG_REPORT.md`、`MESSAGE_TO_HW.md`、`REPRO.md` |
| `soc_resynth_20261111/` | SoC 重综合包装 | 绑定顶层 wrapper |
| `KWT1_Final4_提交报告_模板.docx` | 提交模板 | — |

---

## 3. 服务器目录（`s3_30usr@RDserver03`）

| 路径 | 用途 | 关键文件 |
|---|---|---|
| `~/kwt1_final4_soc_newfix_20261111/` | **Final4 网表与综合报告**（冻结） | `kwt1_soc_mapped.v`（11,530,431 B，MD5 `265bef7d…`）、`.sdc`、`area_hier.rpt`、`qor.rpt`、`timing_max/min.rpt`、`synth_soc_newfix.tcl`、`synth_soc_newfix.log` |
| `~/kwt1_final4_soc_newfix_20261111_core.tgz` | 上述核心件备份（2.0 MB） | — |
| `~/kwt1_final4_romfix_20261112/` | **本次门级修复（新增，未改冻结件）** | `ROM1KX32_comb.v`、`RAMSP4KX64_comb.v`、`RAMSP8KX32_comb.v`、`trace_monitor3.v`、`rom_boot.hex`、`itcm_m0..7.hex`、`gate_romfix*.f`、`sim_romfix*.log` |
| `~/kwt1_final4_realgate_20261111/` | 原门级 TB 与监视器 | `tb_top_gate_nofsdb.v`、`f5.do`、`trace_monitor.v`、`RAMSP4KX64_itcm.v`、`gate_rom.f` |
| `~/kwt1_final4_full_layer_20261111/` | 加速器块级整层 TB | `tb_full_layer.sv`、`newfix.f`、`sim_newfix_full.log`（`L00/L01 cycles=`） |
| `~/kwt1_final4_block_synth_20261111/` | 块级综合工程 | `synth_*.tcl`、报告 |
| `~/kwt1_gate_final4_params_20261109/` | 测试程序与向量 | `program/kwt_smoke.verilog`、`inputs/` |
| `~/kwt1_gate_models_extended_20261104/model_1.v` | 标准单元仿真模型 | — |
| `~/kwt1_gate_eco_crossrow_d7329f2_20261105/rtl/` | E203 RTL（编译 incdir） | `core/ subsys/ perips/ soc/ debug/` |
| `~/Desktop/admin_public_dir/SOC_RTL_2025/e203_hbirdv2-master/rtl/e203/mem_gen/` | 官方宏模型 | `RAMSP4KX64/`、`RAMSP8KX32/`、`ROM1KX32/`（**只有物理壳 + `_rtl.v` 包装，无功能模型**） |
| `~/Desktop/admin_public_dir/SRAM_Lib_2025/` | 厂商 SRAM | 仅 `RAMSP4096X16 / 2048X16 / 1024X16 / 128X16`（**无 4KX64 / 1KX32**） |

---

## 4. 已完成的操作

### 4.1 数值格式与量化（任务①）

- 逐层镜像实测 `max|x|=20,162`、`max|w|=27,538`，确认 **A12W10Y16 不成立**，实际为 **INT16 全字**。
- 合同：X Q4.12、W Q0.16、bias INT32 Q8.28、乘积 INT32、累加 48 位（最小 38 位）、RNE 右移 15/16、饱和 ±32767、`-32768` 保留。
- 与 12 层交付包逐字复核：**304,128 字，0 mismatch**（`numeric_format_audit/`）。
- 冻结配置核实：commit `bbff21cf` 的 `int16_frozen_d7329f2.json`，候选 `rtl_int48_fixed`、`acc_bits=48`；与 2026-11-02 配置的 12 层格式 **逐项一致**，仅累加宽度 38→48（本数据不触发截断，重跑结果相同）。

### 4.2 精度（NRMSE）

- 官方模型：KWT-1 `237e4097` / `models_data_v2_12_labels/kwt1/best_weights`；**30/30 运行时文件**通过 Git blob 校验；12 层 FFN1 权重逐张量核对；探针 logits 与官方分类器 **max|Δ|=0.000e+00**。
- 官方 `kwt1/flags.json`：`d_model=64, mlp_dim=256, heads=1, 12 层`（README 表中的 128 与发布 checkpoint 不符）。
- **单样本实测**（layer 00）：NRMSE **9.449e-05**，max abs 2.44e-04。
- **100 样本预评估**（官方 testing_list，10 词×8 + unknown×10 + silence×10）：12 层层内汇总最大 **0.659%（layer 00）**，全部 <3%；**单样本最大 3.78%**（`down/8769c34c`）；layer 00 输出饱和 **354** 次；x/w/bias/mac 饱和 0；耗时 25.6 s。
- 12 层最坏情况上界 **≤0.199%**（半 LSB + 三角不等式）。

### 4.3 综合

- **SoC 顶层综合完成**：`kwt1_soc_mapped.v` 11,530,431 B、115,978 cells、**GTECH=0**、总细胞面积 3,255,536 µm²。
- 宏实例：`RAMSP128X16 16 / RAMSP8KX32 24 / RAMSP4KX64 8 / ROM1KX32 1`；`link_library` 含四个宏 `.db` → **综合确实走真实宏**。
- 加速器：`u_kwt` 148,079 µm²，其中 `u_accelerator` **148,013 µm²（0.148 mm²）**，占 SoC 4.5%。
- 时序：setup **0.00 ns（0 违例）**；hold **−0.24 ns（4 条路径，未做 hold fixing）**；pre-layout、ideal clock、hold uncertainty=0。

### 4.4 块级门级

- 加速器块级 TB：**PASS**（K64 / K256、两个连续作业、整层 99×64×256 两层各 12,672/12,672、`0x8000` 拒绝）。
- 块级综合：新加速器 61,766 cells / 42,832.8 µm² / setup +5.35 / hold −0.68；CPU 子系统 102,612 cells / 1,489,163 µm² / +4.70 / −0.46。

### 4.5 整机门级（2026-11-12 夜间）

- **根因 1**：CPU 复位向量是 **0x1000（mrom）**，不是 ITCM（`pc_rtvec = aon_io_bootrom ? 0x1000 : 0x8000_0000`；TB 里 `bootrom_n=0`）。
- **根因 2**：`ROM1KX32`、`RAMSP4KX64`、`RAMSP8KX32` 在本环境里**只有综合用接口壳**（`Q` 自赋值恒 X），官方目录无功能模型；`_rtl.v` 也只是包装物理模型。
- **修复（仅仿真模型 + TB，未改冻结网表/RTL）**：
  - `ROM1KX32_comb.v`：组合读 `Q=mem[A]`，启动镜像 `800000b7 / 00008067`；
  - `RAMSP4KX64_comb.v`：`mux=A[2:0]`、`row=A[11:3]`、`Q[i]=mem[row][8*i+mux]`；
  - `RAMSP8KX32_comb.v`：8192×32 逻辑阵列；
  - `trace_monitor3.v`：TB 侧按实例装载 `itcm_m0..7.hex`。
- **结果**：

```
ROMFIX rom_boot[0]=800000b7 rom_boot[1]=00008067
FETCH n=0 addr=0000 data=00068693800016b7   ✓
FETCH n=1 addr=0001 data=00050513a0001537   ✓
FETCH n=2 addr=0002 data=0400613000000637   ✓
FETCH n=3 addr=0003 data=00b520300006a583   ✓
TRACE_END fetches=4 accesses=4 last=0003
KWT CPU WATCHDOG                            ✗
```

- 停住点：第 4 个字含 `lw a1,0(a3)`（数据 load），之后 ITCM 地址变 X；`accesses=4` 说明不是同址死循环。
- **仍未 TEST PASS**；下一步是确认该 load 的地址与从设备响应。

### 4.6 PT 时序检查尝试（2026-11-12，未成功）

- 服务器有 `pt_shell T-2022.03-SP5-1`；已写 `~/kwt1_final4_soc_newfix_20261111/pt_sta.tcl`（read netlist → link → read SDC → update_timing → report_setup/hold/qor）。
- 失败原因：**PT-063 "Library Compiler executable path is not set"**，导致标准单元 `.db` 无法读入（LNK-001），设计未 link，报告为空（`-slack less than 0.0000`，无路径）。
- 已尝试：`set_app_var lc_executable_path`（报 CMD-104：不是 app var）、把 `lc_shell` 加入 `PATH`（仍 PT-063）、改用 `.lib`（标准单元目录只有 `.db`，没有 `.lib`）。
- 结论：**PT STA 被工具环境挡住，不是设计问题**。有效时序证据仍为 DC 内 STA：setup 0.00 ns（0 违例）、hold −0.24 ns（4 条路径）。
- 残留文件：`pt_sta.tcl`、`pt_setup.rpt`、`pt_hold.rpt`、`pt_qor.rpt`、`pt_violators.rpt`、`pt_coverage.rpt`（**均为未 link 结果，不可引用**）。

### 4.7 报告

- `REPORT_DRAFT.md`：八节 + §0 摘要 + §9 完成度 + §10 夜间失败记录。
- `REPORT_QUANT_ARCH.md`：量化与硬件架构专题（含附录 A 红线、附录 B 证据缺口）。
- 今日关闭 G1：权重缓存为 **4 KB / 16 通道 tile**，一层 16 个 tile，每层权重搬一次（DMA `w=1024` 自洽），不是“整层驻留”。

---

## 5. 关键数字速查

| 项 | 值 |
|---|---|
| 网表 | `kwt1_soc_mapped.v`，11,530,431 B，MD5 `265bef7d7eea2da9c3e5a9b3d6f7013` |
| Cells / 面积 | 115,978 / 3,255,536 µm² |
| 加速器 | 148,013 µm²（0.148 mm²），占 4.5% |
| 时序 | setup 0.00 ns / hold −0.24 ns（4 条路径） |
| 宏 | 16×128X16 + 24×8KX32 + 8×4KX64 + 1×ROM1KX32 |
| 单样本 NRMSE | 9.449e-05（layer 00） |
| 100 样本 NRMSE | 最大 0.659%（layer 00），单样本最大 3.78% |
| 门级 | 加速器块级 L00/L01 PASS；整机跑到 4,516 指令后 `x3=2`，未 PASS |
| 加速器 RTL 12 层 | **12/12 PASS**（2026-11-13，每层 12,672 字 0 失配） |

---

## 6. 仍未完成

| 项 | 状态 | 缺口 / 下一步 |
|---|---|---|
| 整机门级 `TEST PASS` | ❌ | 已跑到程序结束（4,516 指令、`EXIT_PC=0x800003f0`），程序自检 `x3=2`；`0x11000004` 读回 `4` 未满足完成位 `2` |
| 整机 RTL 级联调 | ❌ | TB 预装路径绑定网表 `u_sram_wrap_32XK64`，RTL 无该层，需重写预装 |
| Final4 端到端吞吐 | ❌ | 块级实测 743,159 周期 @100 MHz = 134.6 tasks/s（TB 存储模型主导，另一 TB 记录 247,721）；SoC 待测 |
| Final4 网表功耗 | ❌ | 需先跑出 VCD/SAIF；PT 另有 `PT-063 Library Compiler path not set` |
| LEC / Formality | ❌ | 无 SVF、无 FM 证据 |
| 官方 600 样本精度 | ⏳ | 组委会公布后用 `nrmse_verification/run_nrmse.py` 复算 |
| 12 层 FP32 包 | ❌ | `layer_01..11.npz` 不在本机 |

---

## 7. 复现命令

```bash
# 0) 12 层加速器 RTL 功能验证（2026-11-13）
ssh <server>
cd ~/kwt1_final4_layer12_20261113
bash run_layers.sh                 # ~1.3 s CPU/层，全 12 层约 20 s
cat result_s15.txt result_s16.txt
grep -h "mismatches=" work15/run_l*.log work16/run_l*.log

# 1) NRMSE（单样本 / 冻结配置）
cd ~/kwt1_final4_report_20261111/nrmse_verification   # 本地
python run_nrmse.py --vectors ... --npz ... --archived ... --out . --acc-bits 48

# 2) 块级门级（加速器）
cd ~/kwt1_final4_full_layer_20261111
vcs -sverilog -full64 -timescale=1ns/1ps -f newfix.f -top int16_accelerator_top_tb -o simv_newfix
./simv_newfix -l sim_newfix.log | grep -E "PASS|cycles"

# 3) 整机门级（当前修复态）
cd ~/kwt1_final4_romfix_20261112
vcs -sverilog -full64 -timescale=1ns/1ps -debug_access+all \
  +incdir+$HOME/kwt1_gate_eco_crossrow_d7329f2_20261105/rtl/{core,subsys,perips,soc,debug} \
  -f gate_romfix4.f -top tb_trace_top -o simv_romfix4 -l vcs_romfix4.log
./simv_romfix4 -ucli +DUMPWAVE=0 +notimingcheck \
  +TESTCASE=$HOME/kwt1_gate_final4_params_20261109/program/kwt_smoke.verilog \
  < $HOME/kwt1_final4_realgate_20261111/f5.do > sim_romfix5.log 2>&1
```

---

## 8. 红线（交接后不得越过）

1. 不写“官方 600 样本精度通过”；
2. 不写“Final4 网表门级功能 PASS”“SDF PASS”“Formal/LEC 通过”；
3. 不把 162.23 mW 当 Final4 功耗；
4. 不把块级 743,159 周期当吞吐；
5. 不把“INT16 Golden 逐位 0 mismatch”当量化精度验收；
6. 时序必须带 pre-layout / ideal clock / hold uncertainty=0 三个前提，且 **hold 是负的、未修复**；
7. 权重缓存是 **4 KB tile 级**，不是“整层驻留”。
