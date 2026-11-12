# 新 INT16 Final4：报告可用材料（2026-11-13）

## 1. 本次正式使用的设计与测试

| 项目 | 正式使用版本或配置 | 证据 |
|---|---|---|
| 综合前 RTL | `int16_accelerator_top_newfix.sv`；SHA-256 `2257fc3eabf058d575a8f39d57de03ab42d8a2a9d2745f74ab3eace7e300a923` | 服务器 `~/kwt1_final4_full_layer_20261111/`、`~/kwt1_final4_soc_newfix_20261111/synth_soc_newfix.log`（编译源记录） |
| 综合后网表 | `kwt1_soc_mapped.v`；SHA-256 `4416857c0e544eb1245d5686e4f83a4ac6009a4f177d0259d9e204495e3b1c0b` | 服务器 `~/kwt1_final4_soc_newfix_20261111/`、比较目录 `versions.sha256` |
| 算术规则 | 两次测试分别编译上述 RTL 与由该 RTL 综合得到的网表；没有替换 PE 算术或 Golden。对两个任务分别以相同输入、配置及 Golden 验证最终 32 位结果 | `rtl.f`、`gate.f`、综合日志、`input_pair_check.json` |
| 测试任务 | L00、L01，均为 M=99、K=64、N=256；L00 shift=15，L01 shift=16 | `rtl_tb.sv`、`gate_tb.sv` |
| 输入与 Golden | 每层 X、W、Bias、Golden 共 8 个文件；RTL 与门级测试目录逐文件 SHA-256 一致（8/8） | `input_pair_check.json`、`COMPARE_RESULT.json` |
| 输出布局 | `Y_MEM[0:12671]`，按连续 32 位字地址写回，按原数组索引逐地址比较 | 两份测试平台、比较脚本及四份输出转储 |
| 仿真方式 | VCS 加速器块级 RTL/零延迟门级仿真；门级使用 `+notimingcheck` | `commands.txt`、编译与运行日志 |

比较目录：服务器 `~/kwt1_final4_rtl_gate_compare_20261113/`。其中保存 `rtl_l00_out.hex`、`gate_l00_out.hex`、`rtl_l01_out.hex`、`gate_l01_out.hex`，以及原始日志、输入哈希、版本哈希和 [比较脚本](D:/KWT1-Accelerator/final4_report_20261111/compare_rtl_gate_outputs.py)。

## 2. 可直接引用的验证结果

| 层 | 输出规模 | RTL↔门级逐地址逐位差异 | RTL↔Golden | 门级↔Golden | 门级完成状态 |
|---|---:|---:|---:|---:|---|
| L00 | 12,672 × 32 位 | 0 | 0 | 0 | MMIO STATUS=`0x00000002`，写回 12,672 次 |
| L01 | 12,672 × 32 位 | 0 | 0 | 0 | MMIO STATUS=`0x00000002`，写回 12,672 次 |

两层 RTL 日志均记录 `error=0`、`CTRL_ERRORS=0`；RTL 和门级完整测试日志均记录 `FULL_LAYER PASS`。L00 两份输出文件 SHA-256 同为 `55d8ed561093752401964e38289b27f1912fc9db1ac7215ad2442b91e2dc0cab`；L01 同为 `d0535c412184d053af96ab72369f0936c02d42d953799229300d613254a98b35`。逐地址比较脚本退出码为 0，详见服务器 `COMPARE_RESULT.json` 与 `compare.log`。

**报告正文建议写法：**“针对新 INT16 Final4 加速器，对综合前 RTL 与同源综合后映射网表进行 L00、L01 两层仿真级功能一致性验证。两次测试使用 SHA-256 一致的 X、W、Bias 与 Golden，配置分别为 M99/K64/N256、右移 15 位和 16 位。每层 12,672 个 32 位输出字按地址顺序逐位比较，RTL 与门级输出均零差异，且各自与 Golden 零失配；门级 MMIO 状态读回均表明作业完成且未报告错误。因此，**L00/L01 综合前后仿真级功能一致性验证 PASS**。”

## 3. 报告中的适用范围与留空项

- 该结论覆盖**加速器块级、L00/L01、测试平台存储模型、零延迟门级**；不扩展为全 SoC CPU 程序 PASS 或任意输入的等价性。
- **12 层加速器 RTL 功能验证已单独完成（2026-11-13）**：综合前 RTL，12/12 层 `FULL_LAYER PASS`，每层 12,672 个 32 位字与 Golden 0 失配。详见 `LAYER12_RTL_RESULT_20261113.md`；该结果只证明**块级 RTL**，门级仍只有 L00/L01。
- 整机 SoC 程序门级运行已跑到结束（4,516 指令、`EXIT_PC=0x800003f0`），但程序自检 `x3=2`，**未 PASS**；RTL 级复现受 TB 层次绑定阻塞。三者不可互相替代。
- 本次没有 Formality/LEC 证明；正文不得写“形式等价通过”。
- 本次没有 SDF 时序后仿；正文不得写“带延迟门仿通过”。
- 新 INT16 Final4 的正式功耗和单任务能耗未取得，保留空栏；旧混合设计的 162.23 mW、4.16 mW 不使用。
- 官方 600 样本量化精度仍待评测；本地预评估应单独标注数据集与口径。
- 新网表的全 SoC 端到端周期/吞吐尚不能由本次块级测试推出。

其他已经整理的综合面积、STA 和数值精度材料见 [REPORT_DRAFT.md](D:/KWT1-Accelerator/final4_report_20261111/REPORT_DRAFT.md) 对应章节；正式排版时需保留其 pre-layout、测试集和版本口径。

## 4. 服务器文件与脚本位置

以下 `~` 指服务器 `/storage1/2026contest/server3/s3_30usr`。这些路径已在服务器核对；报告正文可引用文件名，证据附录使用完整路径。

| 用途 | 服务器路径 |
|---|---|
| 新 INT16 RTL 顶层 | `~/kwt1_final4_full_layer_20261111/int16_accelerator_top_newfix.sv` |
| 权重 SRAM RTL | `~/kwt1_final4_full_layer_20261111/int16_weight_sram_16bank.sv` |
| PE、阵列、总线控制 RTL | `~/kwt1_review_d7329f2_sram_prefetch_20261108/rtl/int16_pe_mac.sv`、`int16_pe_array_16.sv`、`int16_system_bus_control.sv`（同目录） |
| 全 SoC 冻结网表 / DDC / SDC | `~/kwt1_final4_soc_newfix_20261111/kwt1_soc_mapped.v`、`kwt1_soc_mapped.ddc`、`kwt1_soc_mapped.sdc` |
| 综合脚本与原始日志 | `~/kwt1_final4_soc_newfix_20261111/synth_soc_newfix.tcl`、`synth_soc_newfix.log` |
| 原测试向量生成脚本 | `~/kwt1_final4_full_layer_20261111/gen_full.py`；本轮实际使用的 8 个 `.hex` 输入在比较目录，哈希见 `input_pair_check.json` |
| 原 RTL / 门级测试平台 | `~/kwt1_final4_full_layer_20261111/tb_full_cand.sv`；`~/kwt1_final4_full_gate_20261112/tb_full_gate_status.sv` |
| 本次独立测试平台副本 | `~/kwt1_final4_rtl_gate_compare_20261113/rtl_tb.sv`、`gate_tb.sv`（只增加输出转储） |
| 本次 VCS 文件清单与命令 | `~/kwt1_final4_rtl_gate_compare_20261113/rtl.f`、`gate.f`、`commands.txt` |
| 逐地址比较脚本 | `~/kwt1_final4_rtl_gate_compare_20261113/compare_rtl_gate_outputs.py` |
| L00/L01 输入与 Golden | `~/kwt1_final4_rtl_gate_compare_20261113/l00_a.hex`、`l00_b.hex`、`l00_bias.hex`、`l00_y.hex`；L01 对应 `l01_*`（此处为指向原 RTL 测试输入的链接） |
| RTL / 门级实际输出 | `~/kwt1_final4_rtl_gate_compare_20261113/rtl_l00_out.hex`、`gate_l00_out.hex`、`rtl_l01_out.hex`、`gate_l01_out.hex` |
| 编译、仿真、比较日志 | `~/kwt1_final4_rtl_gate_compare_20261113/rtl_compile.log`、`gate_compile.log`、`rtl_run.log`、`gate_run.log`、`compare.log` |
| 结果、版本和输入哈希 | `~/kwt1_final4_rtl_gate_compare_20261113/RESULT.md`、`COMPARE_RESULT.json`、`versions.sha256`、`input_pair_check.json` |

`gate_run_interrupted.log` 仅保留第一次输出转储中断记录；正式引用完整复跑的 `gate_run.log`。工艺模型实际编译路径见 `gate.f`，此清单无需复制工艺文件到报告附件。
