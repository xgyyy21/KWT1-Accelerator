# KWT-1 软件侧独立验收：单 PE 专项证据包（2026-10-20）

## 1. 结论先行

本报告只验收固定硬件归档提交 `abe7e167ea62041a48fd8935ca3d8a9d224cc731` 中的 `handoff/pe_special_validation_2026-10-20/`，不采用可变 `hardware` 分支的后来版本。软件侧实际读取该提交的完整归档，在隔离目录检查 145/145 个文件的 SHA-256，并使用当前 `software` 分支的比较器与 FP32 参考模型独立核对。

| 专项 | 软件侧结论 | 实际独立核验范围 |
| --- | --- | --- |
| `rounding_nonfused` | **PASS** | 2 次 MAC、1 次 bias；3/3 个真实 PE 事件逐位一致，最终为正零 `0x00000000`。 |
| `k32_boundary` | **PASS** | 64 次 MAC、1 次 bias；65/65 个事件逐位一致；逐周期核对 9 拍停使能、块内 K 重新从 0 起、PE 累加寄存器保持与最终 `0xbf400000`。 |
| `finite_boundaries_hardware_added` | **PASS（仅本次新增 PE 向量，是否纳入联合验收待双方确认）** | 256 个逻辑输出、512 次 MAC、256 次 bias；768/768 个真实 PE 事件与当前软件模型逐位一致。 |

附带的 24,713 对有限值算术向量，软件侧复算其 **49,426 个加法/乘法期望值均一致**。归档中只有每对输入和期望值，没有逐对保存 RTL 的实际输出；因此“这 24,713 对的 RTL 结果由软件逐对复核”是 **BLOCKED**。硬件仿真日志报告这些对已在 RTL 测试平台通过，属于硬件侧已有结论，不计作本轮软件侧实测。

上述 PASS 是对归档轨迹、归档输入与当前软件参考结果的验收。软件侧没有重跑 RTL 仿真，不能单凭静态归档证明 CSV 必然由所列源码生成；来源可信度依据固定提交、源码快照哈希、filelist、实际命令、输入路径、测试平台和日志之间的一致性。

## 2. 基线和保护状态

- 软件工作目录：`C:\Users\Lenovo\Documents\Codex\kwt1-team-checkout-20261017`。
- 开始时实际分支：`software`；HEAD：`d11d169ea6f7b8500d6a2186c803d0f1a5eba709`，与上次记录一致。
- 开始时 `git status --short --branch`：`## software...origin/software`，另有既存未跟踪文件 `reports/PE_HAND_2X2_SOFTWARE_COMPARE_2026-10-19.md`。没有修改或覆盖它。
- 固定硬件归档提交：`abe7e167ea62041a48fd8935ca3d8a9d224cc731`；材料从该提交的 GitHub ZIP 下载后解压到 `C:\Users\Lenovo\Documents\Codex\_kwt1_temp\pe_special_abe7_20261020\KWT1-Accelerator-abe7e167ea62041a48fd8935ca3d8a9d224cc731\handoff\pe_special_validation_2026-10-20`。下文用 `$packet` 表示此完整目录。
- 本轮只在软件工作区新增本报告；没有切换分支、修改原有代码或输入、运行无关回归、提交或推送。
- 软件侧执行环境：Python `3.12.14`，解释器 `C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe`。硬件归档环境记录为 Icarus `iverilog/vvp 14.0 (devel)`、Python `3.10.0`；本轮未调用 Icarus。

## 3. 证据完整性与实际输入

归档 `SHA256SUMS.txt` 自身 SHA-256 为 `76d677aa2bc3b60da280bf3a84baa9c88de231a5eae2fb0662fbfe94fe871186`。逐条计算清单中的 145 个文件哈希，并与目录中除清单自身外的实际 145 个文件比对：**145 条匹配，0 个缺失、哈希错误或清单外文件**。不是只读取硬件自带的校验报告。

已阅读 `README.md`、`cases.json`、`provenance.json`、`replay/run_report.json`、`replay/commands.json`、`filelist.f`、各用例输入检查记录及相关日志。归档显示软件来源提交为当前 HEAD；归档 `inputs/` 内的软件原有 manifest、黄金 JSON、黄金 CSV，以及 `software_snapshot/` 内的 FP32 参考实现和比较器，与当前软件 checkout 的相应文件逐字节一致。原有 manifest SHA-256 为 `148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93`，黄金 JSON 为 `a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b`，黄金 CSV 为 `b3f3fdeb958c5f5d0443787954b6d3d385af2257cdf10948416bd521deda4896`。

新边界向量**另有自己的** `boundary_inputs/manifest.json`（`7e89c181f906cb2d72b23417be2b3570ec03ddb8d8f41c434f7dfc336e18d392`）、`expected_traces.json`（`8e5223b0e2dff4760936acaa1825649d6f69c8f0ca4c509b7bb5bd94e7ff62c1`）和黄金 CSV（`02febb2413bcd203e736745688ab424b3314a86662cfe4102fa5d8ec835d268a`）；没有混用软件原有来源指纹。

四个用例共 12 组 X/W/bias 输入，均独立核对 `.mem` 的 16 位词序、`.bin` 的小端字节、manifest 内的词数和 SHA、硬件输入检查记录、`commands.json` 的 `+X_FILE/+W_FILE/+BIAS_FILE` 路径以及 `simulation.log` 的 `INPUT_FILES` 行。全部一致。软件原有用例的 `.bin` 与当前软件 checkout 同名文件逐字节相同。归档 testbench 的 `$readmemh` 使用上述参数路径加载文件；此检查确认材料和加载配置自洽，但没有重新执行仿真。

硬件归档中的 `rtl_commit` 标为 `9941d8a5981dfdbd851b1e92a0ebc2cdef39f8e8+dirty`：这是**运行时 RTL 基线**，不是本证据包的 Git 提交。`provenance.json` 解释 dirty 为新增 TB/运行脚本当时未提交。编译源码快照及 SHA-256 为：

| 源码快照 | SHA-256 |
| --- | --- |
| `sources/rtl/fp32_math_pkg.sv` | `f9b2ff813b51aba48914ce181c3840d40bd3bbd4f5b2ad0c89a3f4acadb888fe` |
| `sources/rtl/fp32_pe_mac.sv` | `8ff62fcae149b206c5507efd93ccc60a062bedcdb21858a1725cae7c760ddaed` |
| `sources/tb/fp32_pe_special_tb.sv` | `3efa5798eb1daf106cc88003aef530a8be43e6b287ed42130ba81bda58c4a0dd` |
| `sources/tb/fp32_math_boundary_tb.sv` | `d9652a7da90220b1fa652cd2fabb7fb660f9df2e8a8e2ae77fab840d742f0d9b` |

`filelist.f` 列出这四份源码。两份 RTL 快照与归档根目录 `rtl/` 同名文件的 SHA-256 一致。硬件记录的编译命令为 `iverilog -g2012 -s fp32_pe_special_tb -f filelist.f`，按用例设置 `ROWS/COLS/TOTAL_K`；实际记录分别为 `1/1/2`、`1/1/64`、`32/8/2`。仿真由 `vvp` 加上用例、输入和来源参数执行；详细原始参数见固定提交的 `replay/commands.json`。这些是对**硬件已有运行记录**的核验，不是本轮重新运行编译器。

## 4. 软件侧实际运行的命令与结果

以下命令均从软件 checkout 根目录执行，`$packet` 指第 2 节的固定归档目录，`$py` 指第 2 节的 Python 解释器；使用了当前软件分支的 `software.compare_pe_trace`，不是证据包内保存的硬件侧比较结果：

```powershell
$py = 'C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe'
$packet = 'C:\Users\Lenovo\Documents\Codex\_kwt1_temp\pe_special_abe7_20261020\KWT1-Accelerator-abe7e167ea62041a48fd8935ca3d8a9d224cc731\handoff\pe_special_validation_2026-10-20'
& $py -B -m software.compare_pe_trace --expected software/examples/fp32_hand_image/expected_pe_trace_demo.csv --actual "$packet\replay\rounding_nonfused\pe_trace.csv" --case-id rounding_nonfused --compare-tile-id
& $py -B -m software.compare_pe_trace --expected software/examples/fp32_hand_image/expected_pe_trace_demo.csv --actual "$packet\replay\k32_boundary\pe_trace.csv" --case-id k32_boundary --compare-tile-id
& $py -B -m software.compare_pe_trace --expected "$packet\boundary_inputs\expected_pe_trace.csv" --actual "$packet\replay\finite_boundaries_hardware_added\pe_trace.csv" --case-id finite_boundaries_hardware_added --compare-tile-id
```

三次命令的退出码都为 0，比较器均返回 `BIT-EXACT-CANDIDATE`、`first_mismatch: null`。该比较器会核对事件身份、必填和空字段、输入与黄金来源哈希、启用的 `tile_id`、MAC 的 X/W/乘积/累加前后位模式及 bias 的累加/bias/结果位模式；它**不单独验证**流水时序或真实加载路径，因此还进行了第 3 节和下述逐周期检查。

| 用例 | 实际输入与参考 | 期望/实际事件 | 独立结果 | 真实 PE CSV SHA-256 |
| --- | --- | --- | --- | --- |
| `rounding_nonfused` | `inputs/rounding_{x,w,bias}.mem/.bin`；软件原有黄金 CSV | 2 MAC + 1 bias / 2 MAC + 1 bias | 3/3 一致；**PASS** | `cb66622d015c6b887a2ba21b66532d04be1090f16f93799ed70abbcde615d7a0` |
| `k32_boundary` | `inputs/tile_{x,w,bias}.mem/.bin`；软件原有黄金 CSV | 64 MAC + 1 bias / 64 MAC + 1 bias | 65/65 一致；**PASS** | `a6370cb5d4823ab16b3943a806cb5cb268cf1b7974fc657166b6c4a67f825434` |
| `finite_boundaries_hardware_added` | `boundary_inputs/{x,w,bias}.mem/.bin`；**新增**独立 manifest/黄金 | 512 MAC + 256 bias / 512 MAC + 256 bias | 768/768 一致；**PASS，待确认是否纳入联合验收** | `02f82aa1e2fedcfadf78856835975823e19166434e1276c009e241f0d4110c9e` |

### 4.1 `rounding_nonfused`：单独舍入

真实 CSV 的第二次 MAC 输入为 `X=0x3f800001`、`W=0x3f7ffffe`，按软件 FP32 模型先将乘法舍入为 `0x3f800000`（+1），再与先前的 -1 相加得到 `0x00000000`（+0）；唯一 bias 提交仍为 `0x00000000`。乘、加分别舍入，未使用 FMA。三行及全部相关位字段与软件原有黄金一致，无首个差异。

### 4.2 `k32_boundary`：PE 寄存器跨块保持

正式事件记录的全局 K 连续为 0…63，`tile_id = k // 32`。额外读取 `replay/k32_boundary/signal_trace.csv`：与正式 CSV 按 cycle 对齐的 64 个 `trace_valid` 和 1 个 `trace_bias_valid` 逐个匹配；64 次 MAC 的块内 `trace_local_k = k % 32`，因此全局 K=32 时从块内 0 重新开始，0 个映射差异。

- 全局 K=31 于 cycle 209 提交，部分和 `0x40000000`（+2）。
- cycle 210…218 共 9 拍均为 `enable=0`、`rst_n=1`、`clear_acc=0`，累加寄存器均为 `0x40000000`，没有 MAC/bias 提交。
- 第二块于 cycle 219 接受首项；全局 K=32 于 cycle 271 提交，块内 `trace_local_k=0`，累加前仍为 +2；该项乘积为 `0xc0400000`（-3），累加后为 `0xbf800000`（-1）。
- 64 次 MAC 结束后只出现 1 次 bias，最终 `0xbf400000`（-0.75）。

这些值由本轮直接查询归档 CSV 得到，和硬件归档的 `timing_and_boundary_report.json` 一致。此处只证明**单 PE 累加寄存器**在两块之间保持，未验证部分和写入 SRAM、读回或恢复。

### 4.3 `finite_boundaries_hardware_added`：新增向量另报

除正式比较器外，使用隔离目录中的一次性检查脚本 `C:\Users\Lenovo\Documents\Codex\_kwt1_temp\independent_finite_check.py` 调用当前 checkout 的 `software.fp32_reference`；未改动生产代码或正式黄金。脚本自身 SHA-256 为 `276388a0b4833ed8f677a8ec30bb7571c86e7ddb56cdd6b3743694fd37e313e4`。实际命令为 `& $py -B 'C:\Users\Lenovo\Documents\Codex\_kwt1_temp\independent_finite_check.py' $packet 'C:\Users\Lenovo\Documents\Codex\kwt1-team-checkout-20261017'`，退出码 0。当前参考实现 SHA-256 为 `45daa2c620dcd512ffa2380141cf762477ea25846fc0328027827cfa3842fefb`，与归档软件快照相同。脚本从 `.mem/.bin` 独立重建 32×2 的 X、2×8 的 W 和 8 项 bias，对 256 个逻辑输出重新计算；逐事件核对真实 CSV 的 X/W、乘积、累加前后、bias 和结果位模式，并重新生成 `expected_traces.json` 的 `cells`。**256 输出、512 MAC、256 bias 均一致**，无首个差异。检查涵盖该向量实际出现的正负零与次正规数；未将其自动并入原软件三组用例的正式合同。

同一临时脚本读取 `fp32_boundary_vectors.txt`，对每行 `A B ADD MUL` 调用当前软件 `add_bits`、`multiply_bits`：**24,713/24,713 对、49,426/49,426 个软件期望值一致**。文本 SHA-256 为 `cbd6107350b8b506bc655079fa0dc4aac8364e00d4a5515731e6354b0a4728c3`。从实际向量独立重算的覆盖统计与归档 JSON 一致：含次正规输入 10,061 对；次正规加法结果 1,797、乘法结果 1,986；负零加法结果 1、乘法结果 4,177。归档所称 713 对定向、24,000 对固定种子及排除 1,518 对溢出的**生成过程**不能仅从最终文本反推，仍依据硬件生成记录。

归档 `replay/math_boundaries/simulation.log` 写有 `fp32_math_boundary_tb PASS exact_finite_pairs=24713 add_and_mul_checked=1`，TB 源码对每行使用 RTL `fp32_add/fp32_mul` 与预期作位比较并在首个差异时报错。这支持**硬件侧报告通过**；由于没有逐对保存 RTL 实际 ADD/MUL 输出，本轮软件侧无法对这 24,713 对再做“RTL 实际值逐项独立比较”。这是附加算术证据的明确缺口，不影响已保存完整真实轨迹的 768 个 PE 事件对拍结果。

## 5. 验收边界、待办与交接意见

1. 本次可向硬件同学反馈：原有 `rounding_nonfused`、`k32_boundary` 两项软件独立核验 **PASS**；新增 `finite_boundaries_hardware_added` 的**本次单 PE 轨迹**软件独立核验 **PASS**，是否将其写入双方正式联合验收范围仍需确认。
2. 24,713 对向量的**软件期望**复算 PASS；其 RTL 逐对实际输出未归档，软件对这部分的逐项独立验收 **BLOCKED**。若希望签收该附加算术证据，请硬件侧提供每对真实 RTL 结果，或双方认可带固定源码/输入哈希的可复跑仿真作为替代证据。
3. `hand_2x2` 已于上一轮独立验收，本轮没有重复执行。硬件 `replay/run_report.json` 中的四项 `PASS_LOCAL_CHECK` 和本报告三项软件 PASS 是不同来源的结论。
4. 未验证 SRAM 部分和保存/读回/恢复、8×16 阵列、完整 KWT-1 层、E203/SoC、综合后的 150 MHz 物理时序或功耗。功能仿真的周期计数不能替代静态时序收敛。
5. 当前软件 FP32 参考范围是有限且逐步不溢出的 binary32、乘加分别舍入、逐渐下溢、正负零逐位区分。NaN、Inf 和溢出规则仍未获双方合同确认；本报告没有为其新增规则或扩大验收。
6. 可以把本报告交给硬件同学作为**软件侧对固定归档的验收反馈**。它不是宣告所有硬件、阵列或 SoC 已通过，也没有要求重做已通过的旧用例。
