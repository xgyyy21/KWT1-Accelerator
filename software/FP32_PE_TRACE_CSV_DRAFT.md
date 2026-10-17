# FP32 PE 逐步轨迹 CSV 提议（待软硬件确认）

> 状态：**软件候选格式**，不是已冻结的 RTL 接口。`expected_pe_trace_demo.csv` 完全由软件参考代码生成，绝非硬件实测；真实 `pe_trace.csv` 尚未收到。

## 为什么需要它

最终输出 `Y` 错了，只能知道某个结果不对。逐步轨迹则把一次点积拆成 `X×W`、舍入后的乘积、累加前后值，以及最后一次偏置相加，能定位第一次出错的 `k`。例如 `k=31` 后本应为 `0x40000000`，`k=32` 的 `acc_before_bits` 也应为这个值；若硬件重新清零，就能立即发现。

软件候选规则：每个输出元素的累加器从 `+0` 开始，`k=0…K-1` 递增；每次乘法和随后的加法分别按 binary32 最近值、正中取偶舍入；全部 K 项结束后，对该输出元素加一次其列对应的 bias。NaN、无穷、溢出处理仍待约定。详见 [`FP32_REFERENCE_DRAFT.md`](FP32_REFERENCE_DRAFT.md)。

## 建议的列及含义

| 列 | 建议语义 |
|---|---|
| `source_kind` | `software_candidate` 或 `rtl_measured`。演示文件始终是前者，不可改名冒充实测。|
| `case_id` | `hand_2x2`、`rounding_nonfused`、`k32_boundary` 等用例名。|
| `tile_id` | 该项所在 K 块的编号；演示里 K=32 分块是 `k//32`。硬件实际编号、非 K 块的标记待确认。|
| `row`,`column` | **逻辑输出矩阵** `Y[row,column]` 的索引；不是阵列物理 PE 坐标。若硬件只提供 PE 坐标，须同时给出到逻辑索引的映射。|
| `event` | `mac` 表示一个 K 项完成累加；`bias` 表示全部 K 项之后的最后一次偏置加法。建议两种事件分别写一行。|
| `cycle` | RTL 时钟周期计数。软件没有时钟，故演示留空。8 拍乘法、4 拍加法属于**时序**；它们不改变 `k` 的数学顺序。|
| `valid` | 当前行是否表示有效的逻辑运算结果。软件示范的 `1` **不表示 RTL 已提交**；真实 RTL 建议仅在对应结果确实提交时写 `1`，空泡可不写。硬件 `trace_valid` 与 `trace_bias_valid` 的对应关系待定。|
| `k` | 全局数学 K 索引，从 0 开始，即使跨 K tile 也不重新编号；`bias` 行为空。|
| `x_bits`,`w_bits` | 参与此 `k` 乘法的 X、W 的原始 32 位模式，如 `0x3f800000`；`bias` 行为空。|
| `acc_before_bits` | 此项加法之前的累加器位模式；第一项必须是 `0x00000000`。在 `bias` 行是全部 K 项结束时的部分和。|
| `product_bits` | `X×W` **已单独舍入**的位模式；只在 `mac` 行填写。|
| `acc_after_bits` | `mac` 行为 `round32(acc_before+product)`；`bias` 行为 `round32(acc_before+bias)`。|
| `bias_bits`,`result_bits` | 只在 `bias` 行填写该列偏置和最终输出的原始位模式。|
| `rtl_commit` | 生成实测轨迹的 RTL 提交号。软件演示留空。|
| `input_manifest_sha256` | 输入向量 `manifest.json` 的文件哈希，用于标识**宣称的清单版本**；它本身不能证明 RTL 真正读入了清单所指的 `.bin/.mem`，仍须核对镜像哈希、读回或仿真输入。|
| `reference_trace_sha256` | 软件候选 `expected_traces.json` 的文件哈希，固定所用参考版本。|

`*_bits` 一律是 8 位十六进制数字的 `0x` 表示法，不是十进制浮点文本。位模式比较才能发现 `+0/-0`、最低有效位和 NaN 编码差异。对于 `bias` 行，`k/x/w/product` 留空，绝不虚构一次额外乘法。实际硬件若先记录输入接受、稍后记录乘积或累加提交，必须明确每条记录对应的**提交**周期和全局 `k`，不能用周期代替 `k`。

## 软件示范与复现

在仓库根目录运行：

```powershell
python -m software.examples.fp32_trace_csv --output-dir software/examples/fp32_hand_image --check
```

这会核对 [`expected_pe_trace_demo.csv`](examples/fp32_hand_image/expected_pe_trace_demo.csv) 和 `.sha256` 与当前软件计算逐字节一致。演示含 80 条记录：2×2 用例 12 条、非融合舍入 3 条、跨 K=32 用例 65 条。它的 `cycle`、`rtl_commit` 留空，因没有 RTL 实测。软件生成脚本保留独立手算锚点及输入清单哈希；逐步 JSON 在 [`expected_traces.json`](examples/fp32_hand_image/expected_traces.json)。

最终输出比较器 `software.compare_fp32` 能检出漏加、重复加 bias、K 块清零和位舍入错误导致的结果差异；逐步轨迹才能更早定位到哪一个 `k`。输入字序应先由缓存读回对拍核实，数值轨迹本身不冻结 SRAM 排布。

## 请硬件负责人确认

1. 真实轨迹从 `fp32_pe_mac.sv`、阵列哪一级取样？`trace_valid` 与 `trace_bias_valid` 是否分别对上 `mac`/`bias` 的**提交**事件？
2. 提供逻辑 `row,column,global k,tile_id` 与 PE 物理位置、内部任务计数的映射；K=32 边界再次发送 `task_first` 或 `clear_acc` 是否会清空部分和？
3. `cycle` 从哪一个时钟沿开始计数、复位是否清零、是否跨任务连续？空泡和 `enable=0` 怎样表现？
4. `product_bits`、累加前后位模式、bias 后最终值在硬件哪个周期有效？如果不能同时输出，能否用同一个 `global k` 对齐？
5. 真实 trace 的文件名、列名、16 进制书写形式、仿真命令、RTL commit、输入文件哈希，以及哪三组测试向量分别跑完？

收到真实轨迹后，软件才可编写并执行逐行对拍，报告首个错误事件。当前文件只准备了字段及**软件示范**。
