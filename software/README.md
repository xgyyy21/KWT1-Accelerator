# KWT-1 本科组软件起步工程

本目录对应赛题指定的 KWT-1、第一层 FFN 线性计算 `Y[99,256] = X[99,64] @ W[64,256] + b[256]`。它把 PC 上的模型参考、可执行数值规则、数据打包和 E203 驱动流程接成一个工作链。**真实 KWT-1 权重已在合成零波形、以及一条划分未核实的真实音频上分别完成 12 层导出冒烟；第 0 层 FFN1 的归档 RTL 功能数值已独立验收，合法验证集精度、连续 12 层推理与真实 SoC 联调仍未完成。**见[真实音频试跑记录](../work/real_audio_unverified_smoke.md)。

**2026-10-23 交接状态：**本页所引软件验收的核心代码基线为 `d11d169`，后续交接文档可在此之上更新；核心参考模型、打包器、比较器和测试无需重写。[10 月 22 日增量报告](../reports/KWT-1_软件侧增量验收_2026-10-22.md)分别记录两组合成输入整层数值/写回与四组共 13,531 个 PE 事件的独立核验及来源限制。[10 月 23 日真实模型第 0 层报告](../reports/KWT-1_真实模型第0层RTL独立验收_2026-10-23.md)记录从原始 X/W/bias 重算的 25,344 个结果、50,688 条写回和 208 个 tile 均与归档 RTL 结果一致；软件没有重新运行整层仿真。真实音频的验证集划分仍是 `unverified`，RTL 源码身份以归档 SHA-256 为准，E203/SoC、其余 11 层和 PPA 均未验收。下文的 10 月 17—20 日记录保留其当时语境，不能用来代替这份最新状态。

**2026-10-20 状态更新：**软件分支 `d11d169` 的 FP32 参考模型和 19 列 PE 比较器已经用于真实单 PE 轨迹。[固定硬件专项归档 `abe7e167`](../handoff/SOFTWARE_INDEPENDENT_REVIEW_PE_SPECIALS_2026-10-20.md)的 `rounding_nonfused` 3/3、`k32_boundary` 65/65、硬件新增有限边界向量 768/768 个事件由软件侧独立对拍一致。后一项是否纳入正式联合验收仍待商议。K=32 的证据是 **PE 累加寄存器保持**，不是部分和写入 SRAM 后恢复；也不能推及 8×16 阵列、整层、SoC 或 150 MHz 物理时序。旧版缓存读回 CSV 的三组输入哈希错误仍是历史失败记录，不能用新版硬件重跑材料覆盖。当前任务与双方未签的接口字段见[FP32 接口确认单](../docs/KWT-1_FP32_接口确认单.md)。

**结合 2026-10-17 [硬件回复](../docs/KWT-1_回复软件同学_硬件当前状态_2026-10-17.md)，首版先做 FP32。**旧 `ffn1_numeric.py`、`pack_tensors.py`、`precision/` 和 `innovation/weight_stationary.py` 是 Q16.8/16 位等**后续候选原型**，不能作为 FP32 RTL 的逐位标准。当前先看[FP32 运算、手算例与未定事项](FP32_REFERENCE_DRAFT.md)、[`fp32_reference.py`](fp32_reference.py) 和 [`pack_fp32.py`](pack_fp32.py)。`innovation/fp32_tiled.py` 是另写的首版 FP32 **容量与搬运草案**。FP32 参考提出非融合、每步舍入、K 递增、偏置最后一次等规则；低 16 位字先的镜像仍不是已冻结的系统布局。2026-10-17 看到的 `origin/hardware` (`acfae72`) 已有 8×16 阵列、A/B/result 三块 `16 bit×1024` 缓存原型，以及**独立的 FP32 PE 功能性延迟模型**；此处是当时的硬件快照，当前单 PE 对拍结果见上方更新。旧缓存读回 CSV 的 144 条记录有 3 组输入 SHA-256 元数据不符，详见[历史读回核验报告](../docs/KWT-1_硬件缓存读回核验_2026-10-17.md)；固定源码后续 replay 不应与其混淆。现有单 PE 功能测试不构成整层/SoC 或物理时序验证；目前没有正式 E203 地址表或实际驱动适配。

## 已有文件与状态

| 文件 | 用途 | 当前验证 |
|---|---|---|
| `kwt_reference.py` / `KWT_REFERENCE.md` | 使用固定源码与 `best_weights` 导出每层 `x,w,b,y_float` | 固定权重下合成零波形和一条划分未核实的真实音频各 12 层导出、24 张 FFN1 参数逐张量核验通过；尚无合法验证集精度 |
| `ffn1_numeric.py` | 可配置有符号定点参考模型、量化、舍入、饱和、RMSE | 小规模算例通过；格式是示例 |
| [`fp32_reference.py`](fp32_reference.py) / [`pack_fp32.py`](pack_fp32.py) | 首版 FP32 的逐步运算参考、NPZ 打包和 16 位字镜像 | 独立手算、舍入、跨 K=32 分块及一条划分未核实音频的 12 层镜像完整性核验通过；已与已交付的单 PE 有限值向量逐位对拍，系统布局与特殊值合同尚未冻结 |
| [`fp32_step_traces.py`](examples/fp32_step_traces.py) / [`expected_traces.json`](examples/fp32_hand_image/expected_traces.json) | 为三组 FP32 小任务生成每次乘法、累加和最后偏置的机器可读位模式记录；旁附 SHA-256 | 与独立手算锚点、样例输出及重建字节核对通过；其中已交付的真实单 PE 专项轨迹见上方独立验收报告 |
| [`compare_fp32.py`](compare_fp32.py) | 按候选布局比较 RTL `.bin` 或逐行 16 位 `.mem` 与 FP32 expected 的原始 32 位模式，并检查镜像清单 | 两种格式的手算镜像自比、单比特故障定位和错误布局拒绝通过；尚无真实 RTL 输出 |
| [`check_hardware_fp32_vectors.py`](check_hardware_fp32_vectors.py) | 与硬件分支的独立 .NET FP32 加法、乘法向量交叉核验 | 20,441 对输入中，支持范围内加法 20,125 对、乘法 17,626 对零位差；特殊输入和溢出单独计数；不是 RTL 验证 |
| [`check_word_readback.py`](check_word_readback.py) | 核对硬件缓存读回 CSV 的 16 位字、FP32 重组、地址、坐标、周期及输入指纹 | 旧归档 144 条记录中字值/地址/周期与镜像一致，3 组输入 SHA-256 不符，**旧 CSV 严格判失败**；后续固定源码 replay 是另一份证据，不改变旧结论；仅缓存模块局部验证 |
| [`fp32_trace_csv.py`](examples/fp32_trace_csv.py) / [`FP32_PE_TRACE_CSV_DRAFT.md`](FP32_PE_TRACE_CSV_DRAFT.md) | 从既有逐步 JSON 生成 80 条带 `software_candidate` 标记的 PE trace CSV 演示 | 演示仍是纯软件数据；真实 RTL 单 PE 轨迹已另外交付并独立对拍，不能混称为同一份文件 |
| [`compare_pe_trace.py`](compare_pe_trace.py) | 对真实 19 列 PE 轨迹检查事件、来源声明、FP32 位模式和可选 `tile_id`，输出首个差异 | 已用于上方固定归档的真实单 PE 专项对拍；文件哈希、实际输入加载、源码与仿真命令须在比较器外另行核验 |
| `pack_tensors.py` | 从 NPZ 生成二进制、16 位 `.mem`、期望输出和哈希清单 | 打包/解包测试通过；若提供 `y_float`，先核对它与 `X@W+b`；内存布局是示例 |
| `evaluate_layers.py` | 按 12 层聚合样本误差，避免将逐样本误差平均冒充官方指标 | 合成单元测试通过；仍需合法验证集样本 |
| [`precision/`](precision/README.md) | 对多个候选定点格式扫描 12 层误差与饱和次数 | 真实权重加合成零波形的全链路试跑通过；没有合法验证集结论 |
| `driver/` | E203 装载、启动、等待、回读的可移植 C 骨架 | C99 语法检查；尚无真实总线适配 |
| `compare_rtl.py` | 按当前镜像格式逐元素比较 RTL 输出与软件整数期望值，定位首个差异 | 人工注入不一致的二进制/`.mem` 小样例通过；尚无真实 RTL 输出 |
| [`synthetic_smoke.py`](SYNTHETIC_SMOKE.md) | 不依赖真实模型，生成 3 组完整尺寸 `99×64×256` 的合成 RTL 联调向量 | 手算哨兵、字节位置和重复性检查通过；**不代表 KWT 精度** |
| [`examples/hand_2x2.py`](examples/HAND_2X2.md) | 生成 2×2 可逐项手算的整数乘加、补码和内存镜像 | 4 个结果及全部 `.mem/.bin` 字节与独立手算常量一致；**仅为原型协议** |
| [`innovation/`](innovation/README.md) | 16 位原型权重驻留；另有 [FP32 的 8×32×16 分块容量与流量草案](innovation/FP32_TILING_CANDIDATE.md) | 软件计算和小矩阵逐位检查；没有 RTL 性能或 PPA 实测 |

官方规定的型号、精度口径和必做范围，以[2026 本科组赛题指南](https://mp.weixin.qq.com/s/XQrz5_71pYRwk-U0qIl4SA)为准。`kwt_reference.py` 固定使用 [ARM Keyword Transformer 提交 237e4097](https://github.com/ARM-software/keyword-transformer/tree/237e4097) 的 KWT-1 模型。

## 最短工作路径

1. 按 `KWT_REFERENCE.md` 在独立的兼容 TensorFlow 环境准备固定源码、`kwt1/best_weights` 和一条原始音频。运行提取脚本时必须填写 `--split` 和 `--source-id`；真实音频若尚未对照原始数据集划分清单，用 `unverified`，人工波形用 `synthetic-smoke`，不能猜成验证集。在一个样本目录生成 `layer_00.npz` … `layer_11.npz`。NPZ 键为 `x,w,b,y_float`。旧版合成零波形清单没有来源记录，会被标成 `unknown`。
2. **首版 FP32：**先用[2×2 手算与非融合边界样例](FP32_REFERENCE_DRAFT.md)核对每一步位模式；然后对一层生成**候选布局**的 FP32 镜像。输入 NPZ 的 `x/w/b` 必须为 `float32`。`--split` 与 `--source-id` 是使用者声明，工具记录但不会替你核实数据集划分。

   ```powershell
   python -m software.pack_fp32 --input runs/reference/sample_0001/layer_00.npz --output-dir runs/fp32/sample_0001/layer_00 --source-id sample_0001 --split unverified
   ```

   FP32 `expected.bin` 来自按 K 顺序、乘加分别舍入、最后加一次偏置的候选规则；即使 NPZ 中有 `y_float`，也不会直接复制它作为逐位期望。只有与硬件共同冻结算术、地址和 16 位字序并获得 RTL 仿真结果后，才可把它用于正式对拍。

   RTL 如按同一候选顺序导出 `y.bin`，用 `python -m software.compare_fp32 --packed-dir runs/fp32/sample_0001/layer_00 --actual runs/rtl/sample_0001/layer_00/y.bin --report runs/rtl/sample_0001/layer_00/fp32_compare.json` 做**原始 FP32 位模式**对拍。若输出为 `.mem`，每行放一个恰好四位的十六进制 16 位字，按 FP32 低字、再高字排列，可把 `--actual` 指向该 `.mem`；工具会拒绝字数或清单布局不符的文件。它与下面的整数 `compare_rtl.py` 是两个不同工具。

3. **后续定点候选：**对一层生成旧 Q16.8/16 位原型镜像：

   ```powershell
   python software/pack_tensors.py --input runs/reference/sample_0001/layer_00.npz --output-dir runs/packed/sample_0001/layer_00 --spec software/prototype_fixedpoint.json
   ```

   输出中的 `manifest.json` 写明位宽、缩放、舍入、饱和、存储顺序、文件哈希和本地误差。**默认格式仅供联调，不能擅自当作团队最终格式。**若团队定下新格式，先修改/传入 `--x-bits` 等参数，再与 RTL 做逐位对拍。
4. **后续量化评估：**对多个样本的 12 层做本地误差汇总：

   ```powershell
   python software/evaluate_layers.py --input-root runs/reference --report runs/precision/summary.json --spec software/prototype_fixedpoint.json
   ```

   只有每个样本目录都包含 `layer_00.npz` 到 `layer_11.npz` 时，`all_12_layers_present` 才为 `true`；缺失情况列在 `incomplete_groups`。脚本会检查每个文件中的 `y_float` 与独立计算的 `X @ W + b` 是否在 `rtol=1e-4, atol=1e-4` 内一致，明显对不上的数据会被拒绝。但这项检查**不能证明** `y_float` 来自官方模型：仍须核对提取时保存的源码版本、权重、输入和运行清单。脚本使用的“输出误差 RMS ÷ 浮点参考 RMS（分母下限 `1e-8`）、按层汇总后取最大值”与[官方指南](https://mp.weixin.qq.com/s/XQrz5_71pYRwk-U0qIl4SA)第 10 页的本科公式一致。`maximum_numeric_nrmse` 仍只是**本地样本**的数值；`local_3_percent_screen` 还要求所有样本都声明为验证划分且清单、哈希齐全。合成、未知、训练和测试输入即使误差小也不会显示为本地筛查通过。划分声明需要人工对照原始数据集，且本地结果不代表统一评测集成绩。另须把 RTL 输出和软件数值模型的输出字逐位比较。
5. 硬件接口定稿后按 `driver/README.md` 实现 System Bus/NICE 控制及实际数据搬运的平台适配，并在 SoC 仿真中验证装载、启动、完成、读回及连续换层。两条路径的职责可以不同，等真实 E203 平台决定；目前寄存器草稿不能直接写死进驱动。
6. **旧定点格式的**硬件仿真产生输出镜像后，可用 `compare_rtl.py` 将它与同一原型任务目录里的 `expected.bin` 逐元素比较。例如：

   ```powershell
   python software/compare_rtl.py --packed-dir runs/packed/sample_0001/layer_00 --actual runs/rtl/sample_0001/layer_00/y.bin --report runs/rtl/sample_0001/layer_00/compare.json
   ```

   这个比较器按**整数**解释结果，不能直接拿来检查 FP32 位模式。任何格式的输出排布都要先和硬件确认；若布局不同，先按协议转换或更新读取器。
7. 没有真实模型数据时，FP32 首版先按 [`FP32_REFERENCE_DRAFT.md`](FP32_REFERENCE_DRAFT.md) 的手算例联调；[`2×2 定点手算样例`](examples/HAND_2X2.md) 和 [`SYNTHETIC_SMOKE.md`](SYNTHETIC_SMOKE.md) 的全尺寸向量仅属于后续整数原型。**合成数据不得填入官方精度表。**取得真实 12 层 NPZ 与合法划分来源后，再研究候选量化误差。

## 候选自主创新：列块权重驻留

在必做 FP32 版留下可复现基线之后，可用[权重驻留实验说明](innovation/README.md)研究数据复用。原有 `weight_stationary.py` 只适用于**16 位权重原型**：`64×16×2=2048` 字节恰好一块 2 KiB 缓存；但首版 FP32 是 `64×16×4=4096` 字节，**单块装不下**。新的 [FP32 分块草案](innovation/FP32_TILING_CANDIDATE.md)按 8 行、K=32、16 列推演三块 2 KiB 暂存与逻辑搬运量，并用小矩阵检查跨 K 块的逐位结果。它仍需硬件确认端口、部分和位置与实际调度；软件公式不是实测速度、面积或功耗。

## 软件与 RTL 必须共同冻结的协议

- 算术：首版 FP32 的乘加是否融合、每步舍入和 K 顺序、偏置位置、非规格化数/NaN/无穷/有符号零；后续量化才另外定缩放和饱和规则。
- 排布：`W[k,j]` 与输出 `Y[t,j]` 的线性地址公式；字节序、16 位 SRAM 中多字元素顺序、对齐、分块尺寸与顺序。
- 控制：System Bus 还是 NICE；寄存器/命令表、数据地址、`start/busy/done/error`、复位、中断/轮询、参数切换。
- 验证：同一份参数和输入文件的哈希，软件期望输出、RTL 实际输出，以及解码后相对官方浮点结果的误差。

## 当前机器上的检查

Codex 工作区自带 Python 可运行 NumPy 测试；`python` 系统别名在本机不可用。PowerShell 中可执行：

```powershell
& 'C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest discover -s software/tests -p 'test_*.py' -v
```

这套 Python 是 3.12，未提供与上游旧模型兼容的 TensorFlow。工程内另有隔离的 Python 3.8/TensorFlow 2.4.0 环境与按 Git blob 校验的固定提交稀疏源码；已做真实权重的**合成输入**冒烟测试，详情见 [`KWT_REFERENCE.md`](KWT_REFERENCE.md)和[运行记录](../work/real_kwt_bootstrap.md)。当前工作区没有截图中所提及的 `kwt_quant` 脚本或合法验证集精度数据。

## 交付前的完成条件

1. 固定权重和合法数据能提取 12 层 `x,w,b,y_float`，独立 `X@W+b` 与官方层输出接近。
2. 先与硬件共同冻结 FP32 逐步算术和存储布局；如后续提出量化版本，再按允许的训练划分标定、验证划分检查 12 层最大归一化 RMSE，目标不超过 3%。FP32 首版本身不需要先做 Q 格式标定。
3. 同一输入下，RTL 与软件数值模型逐位一致；正常值、边界值、复位、连续任务、换层都通过。
4. E203 驱动在 SoC 仿真中完成真实硬件任务，记录包括装载/总线等待/调度/写回的完整任务周期。
5. 提交源码、固定版本/哈希、转换脚本、数值规格、驱动、测试、运行命令及报告；其他人能从说明复现结果。
