# KWT-1 Final4 综合报告草稿（按提纲八节）

> 写作原则：每个数字后面标注证据状态。
> 【实测】= 有原始日志；【用户确认】= 口述但无原始证据；【待补】= 缺数据；【作废】= 已有结论但对象错误，不得引用。
> 生成日期：2026-11-11；最后更新：2026-11-13（新增 12 层加速器 RTL 功能验证 12/12 PASS、L00/L01 综合前后一致性、整机 SoC 阻塞说明）
> 报告可直接引用的版本、输入、L00/L01 对拍结果与口径汇总见 `FINAL4_REPORT_READY_20261113.md`；12 层明细见 `LAYER12_RTL_RESULT_20261113.md`。

---

## 〇、结论摘要（更新至 2026-11-13）

**交付物**：Final4 全 SoC 网表 `kwt1_soc_mapped.v`（11,530,431 B，115,978 cells，GTECH=0，总细胞面积 3,255,536 µm²，其中加速器 `u_accelerator` 148,013 µm² ≈ 0.148 mm²）+ SDC + 综合/时序报告。

**功能**
- 新 INT16 `newfix` 加速器块级门仿：**L00/L01 PASS**；两层各完成 12,672 次 32 位输出写回，并与 Golden 零失配。历史 K64/K256 和 `0x8000` 拒绝测试另见原始日志。
- 综合前后仿真级一致性：**L00/L01 PASS**；RTL 与门级实际输出逐地址、逐位比较，各 12,672 字、零差异。
- **加速器 RTL 12 层功能验证：12/12 PASS（2026-11-13）**；每层 M99/K64/N256，各比较 12,672 个 32 位输出字，与软件 Golden **0 失配**，非法 `0x8000` 任务均被拒绝，控制错误 0。**这是综合前 RTL 的实际仿真结果**，与门级 L00/L01 是两件事。证据：`LAYER12_RTL_RESULT_20261113.md`、`per_layer_12_rtl_20261113.csv`、服务器 `~/kwt1_final4_layer12_20261113/`。
- 全 SoC CPU 程序门仿：**未 PASS**。最新门级整机运行已跑到程序结束（4,516 条指令，`EXIT_PC=0x800003f0`，加速器收到 m=2/k=64/n=2 并向 `0xa0004000` 写回 4 个字），但程序自检读回 `0x11000004 = 4`、未满足其“完成位=2”的判据，最终 `x3=2`、`TEST FAIL`。整机 RTL 级复现受 TB 绑定阻塞（见 5.3.3）。**不得把块级 RTL/门级 PASS 扩写为全 SoC PASS。**

**L00/L01综合前后仿真级功能一致性验证PASS。** 对象为新 INT16 `newfix` 加速器块级 RTL 与同源综合网表，**不是**全 SoC CPU 程序验证，也不是 Formality/LEC。综合日志使用 `int16_accelerator_top_newfix.sv`（SHA-256 `2257fc3eabf058d575a8f39d57de03ab42d8a2a9d2745f74ab3eace7e300a923`）；门仿网表 SHA-256 为 `4416857c0e544eb1245d5686e4f83a4ac6009a4f177d0259d9e204495e3b1c0b`。L00/L01 的 X、W、Bias、Golden 在 RTL 与门级目录的 SHA-256 逐项相同，配置均为 M99/K64/N256，shift 分别为 15/16。独立复跑转储的两层输出各 12,672 个 32 位字，按输出地址顺序逐字逐位比较均为 **0 mismatch**；两边各自对 Golden 也均为 0 mismatch、写回各 12,672 次。门级两层 MMIO STATUS 均为 `0x00000002`（完成且无错误），RTL 日志 `error=0`、`CTRL_ERRORS=0`；原始门级 `accel_done/accel_error` 端口显示 `z`，因此完成状态以 MMIO 读回为证。比较脚本、输入哈希、输出转储、编译及运行日志保存在服务器 `~/kwt1_final4_rtl_gate_compare_20261113/`，汇总见 `RESULT.md` 和 `COMPARE_RESULT.json`。本次使用 `+notimingcheck`，未做 SDF 或形式等价。

**精度**
- 数值模型与复现脚本**已冻结**（commit `bbff21cf`，候选 `rtl_int48_fixed`，48 位累加）。
- 官方 600 样本精度：**待组委会评测**，本报告不填“通过”。
- **100 条真实测试样本本地预评估（2026-11-12）**：12 层层内汇总最大 **0.659%（layer 00）**，全部 < 3%；单样本最大 3.78%（layer 00），已如实记录。
- 单样本工程验证：layer 00 NRMSE **9.449e-05**；12 层最坏情况上界 **≤0.199%**。

**时序**：setup **0.00 ns**（0 违例）；hold **−0.24 ns**（4 条路径，未做 hold fixing）；pre-layout、ideal clock、hold uncertainty = 0。

**功耗**：新 INT16 Final4 网表的有效活动功耗**未取得**；报告中出现的历史功耗数字均按口径标注，不得当作新网表结论。

**2026-11-13 新 INT16 L00 功耗尝试（未取得有效功耗数字）**：L00/L01 原有 PASS 记录使用 `kwt1_final4_soc_newfix_20261111/kwt1_soc_mapped.v`（SHA-256 `4416857c0e544eb1245d5686e4f83a4ac6009a4f177d0259d9e204495e3b1c0b`），但 `kwt1_final4_full_gate_20261112` 的测试平台顶层为独立 `int16_accelerator_top_11000000`，输入由测试平台存储模型提供，没有 E203 CPU、完整 SoC 总线活动。原测试时钟为 100 MHz，未保存 SAIF/VCD。独立目录 `~/kwt1_final4_power_20261112/` 中，已将 L00 活动采集测试平台设为 150 MHz，VCS 编译成功；一次原生 SAIF 采集运行约 18 分钟仅推进到约 0.85 µs，距完整 L00 计算窗口约 1.65 ms 很远，故终止（`SIM_RC=255`），未产生 SAIF，也未执行有效功耗注释。历史 L00 功能仿真记录 247721 周期、12672 输出匹配，仅可作 100 MHz 独立加速器功能记录，不能作为本次 150 MHz 全 SoC 功耗/能耗结果。全 SoC、加速器及单任务能耗数字均留空；需有包含 CPU/总线/SRAM 的同源完整 SoC 有界活动文件，或可完成的加速器活动采集，才可填写对应口径。

**明确不作结论**：整机门级 PASS、SDF 后仿 PASS、官方 600 样本精度、Formality/LEC。

---

## 一、性能表与各评分支撑点

| 指标 | 数值 | 状态 | 依据 |
| --- | --- | --- | --- |
| 吞吐 / 周期数 | **结构上限** 1,480 tasks/s（101,352 拍 @150 MHz，未实测）；**块级任务实测** 743,159 周期 @100 MHz → **134.6 tasks/s**；**SoC 待测** | 【实测·块级】TB 存储模型主导；**不是 SoC 吞吐** | `THROUGHPUT_20261113.md`、`~/kwt1_final4_layer12_20261113/work15|work16/run_l*.log` |
| 单任务时延 | 块级实测 **7.4316 ms @100 MHz**（折合 4.954 ms @150 MHz）；结构上限 675.7 µs @150 MHz | 【实测·块级】/【折算】 | 同上 |
| 算力（GOPS） | 块级实测 **0.436 GOPS @100 MHz**（0.655 @150 MHz 折算）；结构上限 4.80 GOPS | 【实测·块级】 | 同上 |
| 吞吐（历史混合设计） | M2·K64·N32：20,373 周期（50 MHz）/ 21,970 周期（150 MHz），146.45 µs | 【作废】对象是 RTL+final3 混合设计，非 Final4 网表、非本层形状 | `kwt1_gate_final4_params_20261109/run.log`、`sim_sdf5.log` |
| 面积（加速器 u_kwt） | **148,013 µm² ≈ 0.148 mm²**（`u_kwt` 含总线适配共 148,079 µm²；含 16×RAMSP128X16 权重 SRAM） | 【实测】Final4 全 SoC 综合 `area_hier.rpt` | 占全 SoC 细胞面积 4.5%，远低于 2.25 mm² 预算 |
| 全 SoC 面积 | **3,255,536 µm² ≈ 3.256 mm²**，115,978 cells | 【实测】`area_hier.rpt` | E203 与共享 512 KB SRAM 按赛题规则不计入加速器预算 |
| 功耗（计算窗口） | 162.2279 mW（clock_network 157.64 mW / 97.2%） | 【作废】VCD 来自 RTL+final3 混合仿真，非 Final4 网表 | 见第五节说明 |
| 功耗（历史混合设计参考） | 逻辑 0.21 mW + SRAM 4.38 mW + 漏电 3.88 mW ≈ **8.5 mW** | 【历史口径】RTL+final3 混合活动，**不作为新 INT16 Final4 功耗** | `power_fullsoc_compute.rpt` |
| 数值一致性自测 | 32 个输出 word 与 INT16 Golden 逐字一致，CPU 侧 `x3=1` | 【实测】混合仿真；**属 RTL↔Golden 一致性，不等于量化精度验收** | `run.log`、`sim_sdf5.log` |
| 量化精度（NRMSE） | 数值模型/脚本已冻结；官方 600 样本待组委会评测，本报告不填“通过” | 【待评】 | `nrmse_verification/NRMSE_RESULT.md` |
| 加速器块级门仿（新 INT16 `newfix`） | **L00/L01 PASS**：两层各 12,672 次输出写回，各自与 Golden 零失配；门级 STATUS 均为 `0x00000002` | 【实测】零延迟门仿；K64/K256 与非法输入测试属其他日志 | `~/kwt1_final4_rtl_gate_compare_20261113/gate_run.log`、`RESULT.md` |
| L00/L01 综合前后仿真级一致性 | **PASS**：两层各 12,672 个 32 位字，RTL↔门级逐地址零差异；双方对同一 Golden 也均零失配 | 【实测】`newfix` 加速器块级、零延迟门仿；**非 LEC** | `~/kwt1_final4_rtl_gate_compare_20261113/RESULT.md`、`COMPARE_RESULT.json`、四份输出转储 |
| 加速器 RTL 12 层功能 | **12/12 PASS**：每层 12,672 字、与 Golden 0 失配、非法任务拒绝、控制错误 0、退出码 0；743,159 周期/层 | 【实测】综合前 RTL，M99/K64/N256，shift 按层 15/16 | `LAYER12_RTL_RESULT_20261113.md`、`per_layer_12_rtl_20261113.csv`、`~/kwt1_final4_layer12_20261113/` |
| 整机 SoC CPU 程序（门级真网表） | **未 PASS**：跑到程序结束（4,516 指令，`EXIT_PC=0x800003f0`），程序自检 `x3=2`；STATUS 读回 `0x4` = `error_sticky`（bit2），done=0 | 【实测·失败】不得当作整机 PASS | `~/kwt1_cpubus_diag_20261112_fix1/run/sim_fix10.log` |
| 加速器功能（旧绑定顶层） | 未通过（`k=63` / `S_RESULT` 超时）——**已被上一行的新版本取代** | 【实测·对象作废】 | 同上 |
| 时序（150 MHz） | setup **0.00 ns**（0 违例）/ hold **−0.24 ns**（4 条路径；未做 hold fixing） | 【实测】pre-layout、ideal clock、hold uncertainty=0 | `kwt1_final4_soc_newfix_20261111/timing_max.rpt`、`timing_min.rpt` |

**评分支撑点结论**：面积与 L00/L01 块级综合前后功能一致性可按各自证据口径引用；**量化精度（NRMSE）只写“模型与脚本已冻结、官方 600 样本待评测”，不写“通过”**；功耗与时序必须带口径说明；全 SoC 吞吐需在真实网表上测得。

### 1.1 吞吐率：三个口径必须分开写（2026-11-13）

赛题“任务”= 一次完整 FFN1：M=99、K=64、N=256，**1,621,632 MAC**。

| # | 口径 | 周期 | 时钟 | 任务/s | GOPS | 性质 |
|---|---|---:|---|---:|---:|---|
| 1 | 块级**纯计算**窗口 | 101,352 | 150 MHz | **1,480** | 4.80 | 结构上限，**未实测** |
| 2 | 块级**任务**窗口（含 A/B/bias 读 + Y 写回） | 743,159 | 100 MHz 仿真 | **134.6** | 0.436 | **实测**，受 TB 存储模型主导 |
| 2' | 同上按 150 MHz 折算 | 743,159 | 150 MHz | 201.8 | 0.655 | **折算**，非实测 |
| 3 | **正式 SoC 任务**（E203 调度 + 总线 + 写回） | **> 782,857**（下界） | 50 MHz 仿真 | **≤ 191**（上界） | — | 已跑通配置/启动，18 ms 内未跑完 |

- 口径 2 的计数起点是 START 被接受，终点是 `accel_done`；**不包含** CPU 取指、MMIO 配置与中断/轮询开销。
- 12 层全部为同一形状，每层均 `743,159` 周期，逐层表见 `THROUGHPUT_20261113.md` 与 `throughput_12_rtl_20261113.csv`。
- 计算只占 `101,352 / 743,159 = 13.6%`，其余为存储访问与握手。
- **不要把 1,480 或 201.8 写成 SoC 实测**：现有整机程序下发的是 M=2/K=64/N=32/shift=3 的非法任务（`STATUS` 读回 `error_sticky`），其 12,193 周期是整段程序时长，不能折算每任务周期。
- 同一 RTL、同一形状在另一版比较 TB 中记录为 **247,721** 周期（约 1/3），说明口径 2 对测试平台存储模型高度敏感；这也是必须等 SoC 级测量的原因。

---

## 二、量化与模型

### 2.1 数据格式：INT16 × INT16 → INT32，累加 48 位，输出 INT16

**Final4 的数值格式不是 A12W10Y16。** 逐层镜像实测 `max|x| = 20,162`、`max|w| = 27,538`，均超出 12 位/10 位容器；实际是 **16 位有符号字**，`x_frac = 12` 只是小数位，不是位宽。完整核实见 `final4_report_20261111/numeric_format_audit/NUMERIC_FORMAT_RESULT.md`。

| 对象 | 位宽 / 符号 | 标度 | 依据 |
| --- | --- | --- | --- |
| 输入 X | **signed INT16**，合法值 [-32767, 32767] | Q4.12（`x_frac=12`，零点 0） | `int16_numeric.py` L99 |
| 权重 W | **signed INT16**，合法值 [-32767, 32767] | Q0.16（`w_frac=16`） | `int16_numeric.py` L100 |
| Bias | **signed INT32** | Q8.28（`bias_frac = x_frac + w_frac = 28`） | `int16_numeric.py` L101-102 |
| 乘积 | **signed INT32** | Q8.28 | `int16_pe_mac.sv` L76 |
| 累加 | **signed 48 位**（合同最小 38 位） | Q8.28 | `int16_pe_mac.sv` L24；合同 L58 |
| 输出 Y | **signed INT16**，饱和到 [-32767, 32767] | Q3.13 或 Q4.12（`y_frac` 逐层 13/12） | `int16_pe_mac.sv` L16；合同 L17-30 |
| 输出移位 | 15（层 00、03-10）或 16（层 01、02、11） | — | `int16_config.json` |
| 计算形状 | m=99, k=64, n=256（k_tile=32）；冒烟 m=2, k=64, n=32 | — | `program/program_manifest.json` |

要点：乘法 16×16→32 位全精度；bias 在 64 个乘积之后**只加一次**；`-32768 (0x8000)` 是保留码，硬件遇到即拒绝任务；输出只做 RNE 右移 + 饱和，没有乘性缩放。

### 2.2 理论节约

- **存储**：权重由 FP32 改为 INT16，存储量减 **50%**（交接文档口径）。
- **缓存**：权重缓存为 16 × `RAMSP128X16` = **4 KB**（16 bank × 128 word × 16 bit，bank i ↔ 输出通道 i，见 `int16_weight_sram_16bank.sv`）。一个 tile = 16 输出通道 × 64 K = 2 KB；一层 N=256 需 **16 个 tile**，每个 tile 在 99 个 m 行上复用。
- **搬运**：因此是 **tile 级复用 + 每层权重搬运一次**（不是"整层驻留"）。DMA 计数 `w=1024` 与 16,384 个权重 ÷ 16 个/拍自洽；输出写回 32 笔（实测 DMA 计数 `x=128, w=1024, bias=32, y=32`）。
- **计算**：MAC 由 FP32 乘加降为 INT16 乘加，单 PE 面积与功耗显著下降；k_tile=32 复用累加器。

### 2.3 数值精度（NRMSE）

> **状态：数值模型与复现脚本已冻结；官方 600 样本精度待组委会评测。**
> 官方 600 条样本由组委会选取、评测后公布清单，目前未公开，因此**本报告不填写“600 样本精度通过”**。

**模型核对（2026-11-11）**：权重为官方 `models_data_v2_12_labels/kwt1/best_weights`，commit `237e4097`；下载官方 `best_weights.index` 计算 SHA-256 与导出清单记录一致（`5a60a0fa…b70fbc`）。官方发布的 `kwt1/flags.json` 为 `d_model=64, mlp_dim=256, num_layers=12, heads=1`，与赛题要求的 “FFN 64→256→64” 及本交付包的 `W[64,256]` 完全一致；README 表格中的 “mlp-dim 128” 与发布 checkpoint 的实际结构不符，**N=256 正确**。

**已冻结的软件材料**（commit `bbff21cf`）

| 内容 | 路径 |
|---|---|
| INT16 冻结配置 | `software/precision/configs/int16_frozen_d7329f2.json` |
| INT16 整数计算模型 | `software/precision/int16_numeric.py` |
| 逐层汇总 NRMSE 的评测脚本 | `software/precision/int16_round01.py` |
| KWT-1 权重固定与逐层浮点参考导出 | `software/kwt_reference.py` |

冻结配置关键字段（已在线核对）：`selected_candidate = rtl_int48_fixed`、`acc_bits = 48`、`bias_bits = 32`、`rounding = nearest_even`、`model_commit = 237e4097`、`rtl_commit = d7329f2`；其自身状态字段为 **“official validation accuracy pending”**，与本报告口径一致。逐层 `(x_frac, w_frac, y_frac, bias_bits)` 与交付包 12 层向量**逐项一致（0 处不符）**；唯一差异是累加器宽度（冻结 48 位 vs 交付包生成时 38 位），本数据下累加绝对值 < 2^31，两种宽度都不触发截断，重跑结果完全相同。四个冻结文件与本地复算所用副本 **SHA-256 逐字节一致**（`numeric.py` `98b9767a…`、`round01.py` `f78019b5…`、`kwt_reference.py` `4ba5f479…`、配置文件 `38ccd1d3…`）。

**评测口径（与赛题一致）**

- `NRMSE_l = RMS(Y_decoded − Y_float) / max(RMS(Y_float), 1e-8)`；
- 每层**先汇总该层全部输出的误差平方和与参考值平方和，再统一计算一次**（`int16_round01.py::_nrmse`），不是先算每个样本的比值再平均；
- 12 层取最大值，门槛 3%；解码结果必须有限；
- `Y_float` 必须是**同一样本、同一层、由固定 KWT-1 权重导出的 `y_float`**；**INT16 Golden 包不能替代浮点参考**。

**当前已有的工程验证（单样本，不作为官方成绩）**

| 项 | 结果 | 说明 |
|---|---|---|
| 12 层 INT16 Golden 独立重算 | 0 mismatch / 0 饱和（12 × 25,344 字） | 属 RTL 与软件数值模型的一致性，**不等于量化精度验收** |
| layer 00 NRMSE（有真实 `y_float`） | 9.449e-05（0.0094%），最大绝对误差 2.44e-04 | 单样本 `eight/750e3e75_nohash_0.wav`，`split=unverified` |
| 12 层最坏情况上界（半 LSB + 三角不等式） | ≤ 1.99e-03（0.199%） | 单样本下的保守推导，非实测 |

**100 样本本地预评估（2026-11-12，非官方）**

用完整数据集重跑了 100 条真实测试样本（官方 `testing_list.txt`，10 词×8 + unknown×10 + silence×10；只解压选中的 WAV）：

| 项 | 结果 |
|---|---|
| 模型/预处理 | 官方 commit `237e4097`，30/30 运行时文件 Git blob 校验通过；12 层 FFN1 权重逐张量核对；探针 logits 与官方分类器差 **0.000e+00** |
| 12 层层内汇总 NRMSE | 最大 **0.659%（layer 00）**，其余 9.9e-5 ~ 6.7e-4，**全部 < 3%** |
| 单样本分布 | layer 00 中位数 9.6e-5，p95 1.28e-2，**单样本最大 3.78%**（`down/8769c34c`，单样本已超 3%） |
| 饱和 | x/w/bias/mac 全 0；layer 00 输出饱和 354 次，其余层 0~11 次 |
| 耗时 | 100 样本 25.6 s |

结论：按官方"全部样本层内汇总"口径，3% 门槛通过；但当前冻结 `y_frac` 对大响度样本余量很小，正式 600 样本前建议在 validation 划分上复核。完整证据见 `nrmse_verification/scv2_100/NRMSE_100.md`。

**待补**

- 官方 600 样本清单与逐层 `y_float` 公布后，用上述冻结脚本直接复算并写入正式成绩；
- 12 层 FP32 逐层导出包（`layer_01..11.npz` / `fp32_layerXX/expected.bin`）当前不在本机，取得后可运行 `nrmse_verification/run_nrmse.py --npz <pack>` 转为实测。

完整证据与复现命令见 `final4_report_20261111/nrmse_verification/NRMSE_RESULT.md`。

### 2.4 舍入 / 溢出 / 误差处理

| 项 | 结论 | 状态 | 依据 |
| --- | --- | --- | --- |
| 舍入策略 | **RNE 五成双**：取绝对值右移、比较余数、半格看商奇偶，再恢复符号；输出移 15 或 16 位 | 已确认 | `int16_pe_mac.sv` L38-73、L118 |
| 溢出饱和 | 输出饱和到 **±32767**；`-32768` 永不产生 | 已确认 | `int16_pe_mac.sv` L66-71、L144-149 |
| 累加溢出 | 48 位累加不逐步饱和；全范围上界 `64×32767² + 2³¹ = 70,862,766,144 < 2³⁷`，48 位有余量 | 已确认 | `int16_pe_mac.sv` L24、L79-80；合同 L58 |
| 误差处理 | 线性 MAC + 移位，无激活函数近似，无非线性拟合误差（见第八节） | — | — |

---

## 三、硬件设计

### 3.1 系统结构

```
E203 RISC-V (rv32imc, NICE 协处理器接口 + 系统总线)
  │
  ├─ NICE wrapper ──> u_kwt / u_accelerator（int16_accelerator_top）
  │                      ├─ PE 阵列：16 × INT16 MAC
  │                      ├─ 权重缓存：16 × RAMSP128X16（16 bank 并排）
  │                      ├─ x / bias 缓冲、y 写回
  │                      └─ 控制/状态寄存器 + 系统总线适配
  │
  └─ 系统总线（ICB）─→ int16_e203_system_bus_adapter → 共享 SRAM
                          共享 SRAM：24 × RAMSP8KX32
  E203 自身：ITCM 8 × RAMSP4KX64 + DTCM
```

### 3.2 计算单元

- 16 个 INT16 MAC 并行：`INT16 × INT16 → INT32` 全精度乘积，不截断。
- 累加：**48 位**有符号累加器（合同最小 38 位；全输入范围上界 `64×32767² + 2³¹ = 70,862,766,144 < 2³⁷`，48 位留有余量）。
- bias 在 64 个乘积累加完成后**只加一次**，宽度 INT32，尺度 `2^28`。
- 输出：RNE（四舍六入五成双）右移 15 或 16 位，饱和到 `[-32767, 32767]`；`-32768` 为保留码，硬件收到即拒绝任务。
- 12 层共用同一套阵列，逐层换参数（`y_frac` 逐层 13/12）。

### 3.3 存储层次

| 存储 | 组成 | 用途 |
|---|---|---|
| 权重缓存 | 16 × `RAMSP128X16`（每宏 128 行 × 16 bit，16 个 bank 并排） | 每个周期向 16 个 PE 各提供 1 个 INT16 权重 |
| 输入/偏置缓冲 | 同宏阵列 / 寄存器 | `x`、`bias` 装载 |
| 共享 SRAM | 24 × `RAMSP8KX32` | `x`/`w`/`bias` 原始数据与 `y` 写回 |
| ITCM | 8 × `RAMSP4KX64` | CPU 程序（由 TB 预装） |

权重按 k 分块装入 16 个 bank 后在 m 方向复用；具体 k 分块与地址映射以 RTL（`int16_weight_sram_16bank.sv`）为准。

### 3.4 控制接口与地址映射

- 加速器通过 `int16_e203_system_bus_adapter` 挂到 E203 的系统总线，CPU 用 MMIO。
- 控制/状态寄存器：`0x1100_0000` 段（bit0 = start，其余为参数与状态）。
- 输入数据：`0xa000_0000` 段；`y` 输出：`0xa004_0000` 段。
- 数据搬运由加速器侧 DMA 发起，CPU 只负责配置与启动/等待。

### 3.5 时钟与复位

- 目标 `core_clk` = **150 MHz**（SDC `-period 6.66667`）；外部晶振 16 MHz。
- SoC 内部 `e203_subsys_hclkgen` 做 PLL/旁路选择，`e203_reset_ctrl` 产生 `rst_core/rst_itcm/rst_dtcm` 的同步复位。
- 门级仿真中这三条时钟均实测有 9130 个上升沿（见 5.3）。

### 3.6 物理资源（Final4 综合实测）

| 项 | 值 |
|---|---|
| 加速器 `u_accelerator` | **148,013 µm² ≈ 0.148 mm²**（含权重 SRAM 宏） |
| 加速器块级综合 | 61,766 cells / 42,832.8 µm² / setup +5.35 ns / hold −0.68 ns |
| 全 SoC | 115,978 cells / 3,255,536 µm² / GTECH = 0 |
| 宏 | 16 × RAMSP128X16 + 24 × RAMSP8KX32 + 8 × RAMSP4KX64 |

---

## 四、testbench

### 4.1 驱动方式

- **本次正式使用的 L00/L01 块级测试**：测试平台直接例化 `newfix` 加速器 RTL 或同源综合网表，由存储模型提供相同 X/W/Bias，配置 M99/K64/N256、右移 15/16 位，按连续输出地址记录 12,672 个 32 位字。RTL 和门级原始输入及 Golden 共 8 个文件的 SHA-256 全部一致。独立测试平台副本只增加 `$writememh` 输出转储；脚本逐地址比较两份实际输出。文件及脚本见 `~/kwt1_final4_rtl_gate_compare_20261113/`。
- 以下 CPU 程序驱动方式属于**另一组全 SoC 测试平台**，不用于推导本次块级一致性结果。
- `tb_top.v` 例化 `e203_soc_top`，产生 `clk/rst_n`，通过 `+TESTCASE=<file>` 加载程序。
- 程序以 16 位字文本给出（`program/kwt_smoke.verilog`），由 TB 预装到 ITCM；CPU 从复位向量取指。
- 结束判据：CPU 写 `x3=1`（成功）/ `x3=2`（失败），TB 打印 `TEST PASS` / `TEST FAIL`。
- 看门狗：`#2000000000` 超时打印 `KWT CPU WATCHDOG`。
- 门级 TB 额外例化 `trace_monitor`，观测 ITCM 的 `CS/WE_BAR/ADDRESS/RDATA`、加速器 `s_icb_*`、`accel_busy/done/error`。

### 4.2 仿真流程

```bash
# RTL 混合设计（历史 PASS，非 Final4 证据）
vcs -f files.f -top tb_top -o simv
./simv +TESTCASE=<prog> +DUMPWAVE=0

# 新 INT16 Final4 加速器块级 RTL↔门级对拍（在独立比较目录）
cd ~/kwt1_final4_rtl_gate_compare_20261113
vcs -sverilog -full64 -timescale=1ns/1ps -f rtl.f -top tb_full_layer -o simv_rtl > rtl_compile.log
./simv_rtl > rtl_run.log
vcs -sverilog -full64 -timescale=1ns/1ps -f gate.f -top tb_full_layer -o simv_gate > gate_compile.log
./simv_gate +notimingcheck > gate_run.log
python3 compare_rtl_gate_outputs.py > compare.log
# 命令及退出码见 commands.txt；结构化结果见 COMPARE_RESULT.json

```

全 SoC 历史门级诊断的具体编译命令与文件清单见对应服务器目录；本报告不将其当作本次 L00/L01 块级 PASS 的运行命令。

### 4.3 三组单独 TB

| TB | 内容 | 状态 |
| --- | --- | --- |
| 加速器单独 | `newfix` RTL 与同源综合网表分别运行 L00/L01，测试平台存储模型提供同一批 X/W/Bias | **【实测 PASS】** 两层各 12,672 字与 Golden 一致；RTL↔门级逐地址零差异。历史 K64/K256 测试另见原始日志 |
| E203 单独 | CPU 跑 riscv-tests | 【未做】未单独跑 riscv-tests |
| 共享 SRAM 单独 | SRAM 模型读写/预装验证 | 【部分】ITCM 位交织与预装已验证（`MODEL_MEM0`），读写端口回读正常 |

### 4.4 整合 TB

- 两套整合级 TB：
  1. `~/kwt1_gate_final4_params_20261109/`：**RTL SoC + final3 映射加速器**（历史混合 PASS，见 5.2，不能当 Final4 证据）；
  2. `~/kwt1_final4_realgate_20261111/`：**Final4 全 SoC 网表**（`kwt1_soc_mapped.v` + 宏模型 + ITCM/ROM 预装），当前卡在 ITCM 控制 X 传播（见 5.3 与 `full_layer_test/GATE_DEBUG.md`）。

### 4.5 检查项与通过标准

| 层次 | 检查项 | 通过标准 |
|---|---|---|
| 加速器块级 | K64 / K256 两个连续作业；整层 99×64×256 | 输出逐字与 Golden 一致（12,672/12,672），`accel_error=0` |
| 加速器块级 | 非法输入 `0x8000` | 必须置 `accel_error` 并拒绝作业 |
| 整 SoC | CPU 取指、写控制字、等 done、逐地址比对 | `x3=1` 且 32 个 word 与 `inputs/y_expected.mem` 一致 |
| 整 SoC | 超时 | 不允许出现 `KWT CPU WATCHDOG` |

本轮 L00/L01 实测使用独立块级 TB，**未运行上表的全 SoC CPU/x3 检查**。门级结果的完成证据为两层 MMIO STATUS 均读到 `0x00000002`；原始 `accel_done/accel_error` 输出线在该映射块级测试中显示 `z`，不作为完成证据。

### 4.6 预装与模型注意事项（本轮实测教训）

1. `RAMSP4KX64` 采用 **MUX=8、MEM_WIDTH=512** 的位交织：`mux = A[2:0]`、`row = A[11:3]`，物理行 bit `8*i+mux` 对应 64 位字 bit `i`；按连续 64 位打包会导致 CPU 取到错误指令。
2. `$readmemh` 必须插在**实际编译**的 `ifdef` 分支里（该模型有两个功能分支）。
3. `ROM1KX32` 的 `Q` 是自赋值黑盒，仿真恒 X；需要行为级替身或显式驱动。
4. VCS 增量编译会因时间戳偏移跳过重编译，改 TB 后必须换新的 `-o` 名字或清 `csrc`。

---

## 五、综合策略、性能计算、形式验证、门级仿真、PTPX

### 5.1 三个元件单独综合 + FM/PT/PTPX

| 步骤 | 状态 |
| --- | --- |
| 三个元件单独综合 | **已完成块级**：CPU 子系统 102,612 cells / 1,489,163 µm² / setup +4.70 ns / hold −0.46 ns；新加速器 61,766 cells / 42,832.8 µm² / setup +5.35 ns / hold −0.68 ns（16×RAMSP128X16）【实测】`block_synth_20261111/RESULT.md` |
| Formality 形式验证 | **【未做】** 无 FM 证据；综合未导出 SVF，RTL↔网表 LEC 不可信 |
| PT 时序 | 【实测】DC 内 STA 已做（见 5.4），未单独跑 pt_shell |
| PTPX 功耗 | **未跑通**：`pt_shell T-2022.03-SP5-5` 存在，但读 `.db` 报 `PT-063 Library Compiler path not set`，设计未 link（功耗 pW 级） |

### 5.2 拼接成 SoC 后仿真 / PT / PTPX

- 门级功能仿真：**PASS，但对象错误**。`files.f` 只含 151 个 `rtl/` 文件 + `accelerator_final3_mapped.v` + SRAM 模型，**不含 `kwt1_soc_mapped.v`**。
- 结论：该 PASS 证明的是「RTL SoC + final3 映射加速器」可跑通 M2/K64/N32，**不是 Final4 映射网表**。

### 5.3 SoC 单独综合与验证

- 综合：**已完成**（Final4 新加速器版本，DC T-2022.03-SP5-5，SS 0.99V/125℃，SMIC 40nm 库）。
  - 网表 `kwt1_soc_mapped.v` **11,530,431 B**，MD5 `265bef7db7eea2da9c3e5a9b3d6f7013`；
  - **115,978 cells**；总细胞面积 **3,255,536.48 µm²**；
  - **GTECH = 0**；宏：16×`RAMSP128X16`（权重缓存）+ 24×`RAMSP8KX32`（共享 SRAM）+ 8×`RAMSP4KX64`（ITCM）；
  - 加速器层次 `u_kwt` = 148,079.44 µm²，其中 `u_accelerator` = **148,013.37 µm²**。
- 加速器功能（`newfix` 块级门级）：**L00/L01 PASS**。两层各完成 12,672 次输出写回并与 Golden 零失配；具体综合网表身份及综合前后直接比较见 5.3.1。K64/K256 属于另一次块级测试。
- 门级仿真（整 SoC 真网表，跑程序）：**仍未 PASS，但已跑到程序结束**。`full_layer_test/GATE_DEBUG.md` §3.9 的启动问题修复后，2026-11-12 20:56 的最新一次门级运行（`~/kwt1_cpubus_diag_20261112_fix1/run/sim_fix10.log`）结果为：
  - CPU 从 mrom 起步、跳入 ITCM 执行，**完成 4,516 条指令**，`[RESULT] EXIT_PC=0x800003f0 cyc=12193 itcm=4516 dtcm=0 shared=1120`；
  - CPU 通过 `0x11000000` 写配置、启动加速器；`[ACC_TRACE]` 显示加速器收到 `m=2 k=64 n=2 a=a0001000 b=a0002000 bias=a0003000 dst=a0004000`，状态走到 12，`enger=1 sticky=0`；
  - 加速器向 `0xa0004000` 写回 4 个 32 位字；CPU 读 `0x11000004` 得到 `0x00000004`；
  - 程序按“`status & 2` 为完成位”判据自检，未满足，最终 `x3=2`、`TEST FAIL x3=00000002`。
- 结论：**总线/MMIO/加速器启动/写回的通路已经打通，但加速器返回了错误状态**，属未解决缺陷，**不得写成整机门级 PASS**。
- 根因定位（2026-11-13）：`assets/int16_system_bus_control.sv` 中状态字定义为
  `A_STATUS = {29'd0, error_sticky, engine_error, done_sticky, engine_done, engine_busy}`，
  即 bit0=busy、bit1=done、bit2=error_sticky、bit3=engine_error。CPU 读回 `0x4` = **error_sticky=1、done=0**，所以程序的“等 done 位”轮询永远不会成功。
  该次 SoC 程序下发的是 **M=2 / K=64 / N=32 / shift=3**，与所有已通过的块级配置（M=99 / K=64 / N=256，shift 15/16）不同；`[ACC_TRACE]` 还显示加速器内部看到 `n=2`，与程序写入的 N=32 不一致。下一步需确认是参数寄存器写入未生效，还是该任务形状被判非法。
- SDF：已生成（143 MB，`DESIGN e203_soc_top`，SS，MAXIMUM），但**标注对象是 RTL 设计**，59k 实例未匹配，**结论作废**。

### 5.3.1 新 INT16 L00/L01 综合前后功能一致性（本次正式结果）

综合日志 `~/kwt1_final4_soc_newfix_20261111/synth_soc_newfix.log` 记录了 `int16_accelerator_top_newfix.sv` 作为综合输入（SHA-256 `2257fc3eabf058d575a8f39d57de03ab42d8a2a9d2745f74ab3eace7e300a923`）。门级测试使用同目录的 `kwt1_soc_mapped.v`（SHA-256 `4416857c0e544eb1245d5686e4f83a4ac6009a4f177d0259d9e204495e3b1c0b`），以其加速器模块为块级 DUT。RTL 和门级测试的 L00/L01 X、W、Bias、Golden 八个文件逐项 SHA-256 相同，配置均为 M99/K64/N256；L00 右移 15 位，L01 右移 16 位。

| 层 | RTL 与门级输出 | RTL 与 Golden | 门级与 Golden | 写回与状态 |
|---|---:|---:|---:|---|
| L00 | 12,672 个 32 位字逐地址比较，**0 差异** | 0 失配 | 0 失配 | 两边各 12,672 次写回；门级 STATUS=`0x00000002` |
| L01 | 12,672 个 32 位字逐地址比较，**0 差异** | 0 失配 | 0 失配 | 两边各 12,672 次写回；门级 STATUS=`0x00000002` |

RTL 日志记录 `error=0`、`CTRL_ERRORS=0`；门级测试 `CTRL_ERRORS=0`、`FULL_LAYER PASS`。逐地址比较脚本退出码为 0；四份输出、输入哈希、RTL/网表版本哈希及完整命令在服务器 `~/kwt1_final4_rtl_gate_compare_20261113/`，汇总为 `RESULT.md`、`COMPARE_RESULT.json`。**结论：L00/L01 综合前后仿真级功能一致性验证 PASS。** 本结论限于加速器块级这两层，使用零延迟门仿（`+notimingcheck`）；不等同于 Formality/LEC、SDF 后仿或全 SoC CPU 程序门仿通过。

### 5.3.2 加速器 RTL 12 层功能验证（2026-11-13）

对象是**综合前** `int16_accelerator_top_newfix.sv`（SHA-256 `2257fc3e…`，与 5.3.1 同一文件），不是门级、也不是软件 Golden 复算。

测试平台用 `~/kwt1_final4_rtl_gate_compare_20261113/rtl_tb.sv`，按层移位拆成两个只跑单层的变体：`tb_s15.sv`（右移 15）、`tb_s16.sv`（右移 16）。向量取 `~/kwt1_cpu12_bundle_20261105/vectors/layer_00..11/` 的 `x.mem / w.mem / bias.mem / y_expected.mem`，按 32 位打包成 hex。

| 层 | 右移 | 周期 | 比较字数 | 与 Golden 失配 | 非法任务 | 控制错误 | 退出码 | 结果 |
|---|---:|---:|---:|---:|---|---:|---:|---|
| 00 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 01 | 16 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 02 | 16 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 03 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 04 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 05 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 06 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 07 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 08 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 09 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 10 | 15 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |
| 11 | 16 | 743,159 | 12,672 | 0 | 拒绝 | 0 | 0 | FULL_LAYER PASS |

每层日志固定输出 `LAYER n mismatches=0 / 12672`、`ILLEGAL done=0 error=1 cycles=0`、`CTRL_ERRORS=0 OTHER_CMDS=0`、`FULL_LAYER PASS`，单层 CPU 时间约 1.3 s。

**口径边界**：12 层 PASS 是**加速器块级**结果；门级只有 L00/L01 两层做过直接比较；整机 SoC 程序仍未 PASS（5.3.2 之后的 5.3.3）。任务形状固定为 M=99/K=64/N=256，未改 M/K/N、未改数值格式、未改冻结 RTL。

### 5.3.3 整机 SoC RTL 级复现的阻塞

现成整机 TB `~/kwt1_cpubus_diag_20261112_fix1/tb/tb_soc_cpubus.sv` 只能对**映射网表** `kwt1_soc_mapped.v` 运行：它通过 `u_dut...u_e203_sram.u_e203_itcm_ram.u_sram_wrap_32XK64` 这一网表专用层次预装 ITCM 程序镜像。把同一 TB 换到综合前 RTL 源（`files_soc_newfix.f`）后，VCS 在 `-XMRE` 阶段报：

```
tb_soc_cpubus.sv, 77-79: token 'u_sram_wrap_32XK64' cannot be resolved
```

RTL 侧 ITCM 由 `assets/kwt1_sram_bank.sv` 的 `RAMSP8KX32 u_macro` 组成，没有 `u_sram_wrap_32XK64` 这一层，因此需要重写 ITCM/DTCM 预装路径并重新确定存储模型层次。加上整机程序自检 `x3=2` 未定位，属“大规模调试 CPU/SRAM 模型”，本轮不开展；**不开展新的整机门级仿真，也不以块级 PASS 代替整机 PASS**。

### 5.4 时序结果（可用部分）

| 项 | 值 | 前提 |
| --- | --- | --- |
| Setup WNS | **0.00 ns**（0 违例） | SS 0.99V/125℃，ideal clock |
| Hold WNS | **−0.24 ns**（4 条路径） | **hold uncertainty = 0**；未做 hold fixing |
| 违例数 | setup 0 / hold 4 | 同上 |

必须注明：理想时钟、无 CTS/RC/OCV，**hold 为负且未修复**，属 pre-layout 复核，不是签核；不得写“时序收敛”。

### 5.5 功耗（口径说明）

- **新 INT16 Final4 网表的有效活动功耗：未取得**。L00/L01 块级门仿 PASS 不会自动产生可用于全 SoC 功耗的活动文件；现有活动采集未完成。因此本报告不给出新网表功耗数字。
- 已有 162.2279 mW 来自 VCD→SAIF→DC，但 VCD 由 5.2 的混合设计产生 → **不可作为 Final4 网表功耗**。
- 历史混合设计报告中的 SRAM 宏 4.38 mW、逻辑 0.21 mW、漏电 3.88 mW **不纳入新 INT16 Final4 正式功耗表**。
- clock_network 占 97.2%：RTL 时钟网无 buffer + 综合网表插入单元无活动，属双重失真。

---

## 六、复现材料与测试方法

### 6.1 材料清单（服务器）

| 类别 | 路径 |
| --- | --- |
| Final4 网表/DDC/SDC | `~/kwt1_final4_soc_newfix_20261111/`（`kwt1_soc_mapped.v` 11,530,431 B，MD5 `265bef7d…`；`area_hier.rpt`、`qor.rpt`、`timing_max/min.rpt`）；备份 `~/kwt1_final4_soc_newfix_20261111_core.tgz` |
| Final4 门级 TB 工程 | `~/kwt1_final4_realgate_20261111/`（`trace_monitor.v`、`gate_rom.f`、`ROM1KX32_boot.v`、`RAMSP4KX64_itcm.v`、`f5.do`） |
| 混合设计 TB（历史） | `~/kwt1_gate_final4_params_20261109/`（`tb/tb_top.v`、`files.f`） |
| 测试程序 | 同上 `program/kwt_smoke.verilog`（16,512 B） |
| 输入/Golden | 同上 `inputs/`（x/w/bias/y_expected.mem，含 manifest+sha256） |
| 标准单元/宏模型 | `model_1.v`、`RAMSP128X16.v`、`RAMSP8KX32.v`、`RAMSP4KX64.v`、`ROM1KX32.v` |
| 功耗库 | `scc40nll_vhsc40_rvt_ss_v0p99_125c_basic.db` + 四个宏 `.db` |

### 6.2 软件入口

```
# A. 混合设计（RTL SoC + final3 加速器）：证明流程可跑通，不是 Final4 证据
cd ~/kwt1_gate_final4_params_20261109
./simv +DUMPWAVE=0 +notimingcheck +TESTCASE=$PWD/program/kwt_smoke

# B. Final4 全 SoC 真网表：当前卡在 ITCM 控制 X 传播
cd ~/kwt1_final4_realgate_20261111
./simv_rom6 +DUMPWAVE=0 +notimingcheck +TESTCASE=$HOME/kwt1_gate_final4_params_20261109/program/kwt_smoke.verilog
```

### 6.3 硬件入口

- 顶层：`tb_top.u_e203_soc_top`
- 加速器：`u_kwt`（层次 `u_e203_soc_top/u_kwt/u_accelerator`）
- 控制寄存器：0x11000000 段；数据：0xa0000000 段；y 输出：0xa0040000 段

### 6.4 复现仿真流程（目标形态，尚未跑通）

```
# 1) 真网表编译
tb_top_gate.v + kwt1_soc_mapped.v + 5 个模型  →  simv_gate
# 2) ITCM 预装（当前阻塞）
# 3) 运行
./simv_gate +TESTCASE=.../kwt_smoke.verilog
# 4) 通过标准：TEST PASS、x3=1、32 word 与 inputs/y_expected.mem 逐字一致
```

---

## 七、对照实验

| 实验 | 目的 | 状态 |
| --- | --- | --- |
| 内积 vs 外积数据流 | 比较带宽/PE 利用率 | **【未做】** |
| 权重 tile 复用 vs 不复用 | 量化搬运节省 | **【分析】**：tile 级复用下每层权重搬 1,024 拍（16,384 权重 ÷ 16/拍）；若每个 m 行重读则为 99×1,024 ≈ 101,376 拍，约 **99 倍**差异【推导，基于 `int16_weight_sram_16bank.sv`】 |
| 量化 vs FP32 | 精度/面积/功耗对照 | **【部分】**：单样本 NRMSE 已做（layer 00 = 9.449e-05；12 层上界 ≤0.199%）；面积已做；官方 600 样本与功耗对照未做 |
| 门控时钟 on/off | 动态功耗下降比例 | **【未做】**（RTL 有 clock gating 单元，但未做开关对照） |

说明：这四项都需要可运行的真网表门级/功耗环境，属下一阶段。

---

## 八、误差分析

| 项 | 结论 |
| --- | --- |
| 量化误差 | **【单样本实测】** layer 00：NRMSE 9.449e-05，max abs 2.44e-04；分解为量化 7.45e-05 + 输出舍入 5.84e-05。12 层最坏上界 ≤0.199%。官方 600 样本统计待评测 |
| 溢出/饱和 | 单样本包（12 × 25,344 字）：全部为 0。**100 样本预评估**：x/w/bias/mac/累加饱和 **0**；但 layer 00 输出饱和 **354** 次、layer 03/04/05/07/08 合计 21 次（合同允许的饱和，已计入 NRMSE）。`-32768` 保留码未出现 |
| 非线性函数拟合误差 | **无**：本设计只做线性 MAC + 移位，无激活函数近似 |

---

## 九、完成度清单（更新至 2026-11-13）

| 章节 | 状态 | 仍然缺的 |
|---|---|---|
| 〇 摘要 | ✅ | — |
| 一 性能表 | ✅（吞吐一行为混合设计口径，已标注） | Final4 网表真实吞吐/周期需重测 |
| 二 量化与模型 | ✅ | 官方 600 样本精度待组委会评测；100 样本本地预评估已完成（最大 0.659%） |
| 三 硬件设计 | ✅ | — |
| 四 testbench | ✅（L00/L01 块级 RTL/门级对拍已完成） | E203 单独 riscv-tests 未跑；全 SoC CPU 程序门仿未取得同等级别完整结果 |
| 五 综合/STA/功耗 | ⚠️ 部分 | L00/L01 综合前后仿真级一致性 PASS；功耗未取得，LEC 未做，SDF 结论作废 |
| 六 复现材料 | ✅ | — |
| 七 对照实验 | ⚠️ 部分 | 内积/外积、权重驻留、门控时钟三项未做 |
| 八 误差分析 | ✅（单样本） | 600 样本汇总统计待评测 |
| 吞吐（Final4 端到端） | ❌ 未取得 | 门级 X 传播，见第十节 |
| 功耗（Final4 网表） | ❌ 未取得 | 同上，见第十节 |

**交付前必须补的只有两类**：① 组委会 600 样本公布后的精度复算；② Final4 网表功耗（若能跑出活动文件）。其余为加分项。

---

## 十、2026-11-12 夜间尝试记录（明确失败项）

| 项 | 尝试方式 | 结果 | 失败原因 |
|---|---|---|---|
| Final4 端到端吞吐 | 真网表门级跑 `kwt_smoke`，统计取指到 `x3=1` 的周期 | **部分**（CPU 已启动，仍未跑完） | 已定位并修复 ROM/ITCM 两个黑盒模型；CPU 现在能取到正确指令（4 次 FETCH 后停住），未到 `x3=1` |
| Final4 网表功耗 | 需先有可运行的门级活动文件（VCD/SAIF） | **失败** | 同上，跑不出活动文件；`pt_shell` 另有 `PT-063 Library Compiler path not set` |
| 块级加速器周期数 | `~/kwt1_final4_full_layer_20261111/sim_newfix_full.log` 已有 TB 计数 | **不可用作吞吐** | TB 计数 `cycles=743,159/任务`，但同一次运行有 58,880 次存储器字访问（a=50,688 / b=8,192），该数字由**测试台的存储服务延迟**主导，不是加速器计算吞吐 |
| 块级加速器功耗 | VCD→SAIF→DC `report_power` | **未完成** | 时间与工具链风险（PT 库路径失败的历史问题）；且块级 TB 的活动同样被存储模型主导，不能代表真实负载 |
| Formality / LEC | — | **未做** | 无 SVF，无 FM 许可与证据 |
| 内积 vs 外积对照 | — | **未做** | 需要另一套 RTL/网表 |
| 门控时钟 on/off | — | **未做** | 依赖功耗环境，随功耗项失败 |
| 600 样本精度 | 需要官方清单与逐层 `y_float` | **待组委会**（不算失败） | 官方未公布 600 条清单 |

**结论**：吞吐与功耗两项在 Final4 上都没有可交付数字。报告只保留混合设计的历史数字并明确标注口径；**不得**把块级 TB 的 743,159 周期写成加速器吞吐。

---

## 附：本轮红线（写报告时不得越过）

1. 不得写「Final4 全 SoC 门级功能 PASS」——2026-11-13 的新证据只证明 `newfix` 加速器块级 L00/L01 综合前后仿真级一致性；旧绑定顶层超时和 RTL+final3 混合仿真属于不同版本与对象。
2. 不得写「SDF 后仿 PASS」——标注对象错误，59k 实例未匹配。
3. 不得写「功耗 162.23 mW」作为 Final4 结论——VCD 来自混合设计。
4. 不得写「形式验证通过」——没有 FM 证据、没有 SVF。
5. 时序结论必须带 `hold uncertainty = 0` 与 `pre-layout` 两个前提。
6. 不得写「官方 600 样本精度通过」——600 条样本由组委会选取、评测后公布，当前无官方清单与逐层 `y_float`。
7. 不得把「INT16 Golden 逐位对拍 0 mismatch」当作量化精度验收——前者是 RTL 与软件数值模型的一致性，后者是 `NRMSE_l ≤ 3%`。
