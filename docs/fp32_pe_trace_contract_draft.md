# FP32 PE 轨迹对接数据契约草案（2026-10-18）

> **仅供软件/硬件讨论，待双方负责人确认。**这里设计如何对拍，不声称硬件已生成轨迹。现有 `software/examples/fp32_hand_image/expected_pe_trace_demo.csv` 的 80 行全部由软件产生，`source_kind=software_candidate`；真实 `pe_trace.csv` 尚未收到。数值协议仍有特殊值、次正规和有符号零的未决项。

## 1. 两种顺序，两个坐标系

- **数值顺序**：对逻辑输出 `Y[row,column]`，按全局 `k=0…K−1` 做乘法和累加；最后一次 bias。软件对拍按这个身份找事件。它不要求所有 PE 的行在 CSV 中按同一顺序出现。
- **时钟顺序**：硬件在某个上升沿接受 X/W，在之后的某个沿提交乘积与累加。空泡、停使能、复位会影响周期。`cycle` 只记录真实硬件事件时间；不能用 `cycle` 猜 `k`，也不能从“8 拍乘、4 拍加”自行写死每个 valid 周期。
- `row,column` **建议表示 Y 的逻辑矩阵坐标**，绝非 8×16 阵列中的物理 PE 编号。若硬件只能导出物理 PE 行列，需另给“任务号、PE 位置 → 逻辑输出坐标”的确定映射。
- 当前三组演示仅用 `case_id` 区分任务，19 列中**没有层号 `layer_id`**。未来扩至 12 层时，需由硬件/软件共同增加层号及任务实例 ID，避免不同层相同坐标和 K 发生身份冲突。

## 2. 已有软件演示 CSV 的列及候选类型

保留现有 `software/examples/fp32_trace_csv.py` 的 19 列以便 testbench 直接读取。表内“建议宽度”是文件交换约定，**不表示 RTL 新增了同宽度端口**；空栏只用于该事件不适用的字段。整数用 ASCII 十进制，FP32 字一律 `0x` 加 8 位十六进制。

| 字段 | 类型、建议范围 | `mac` 行 | `bias` 行 |
|---|---|---|---|
| `source_kind` | 交换文件使用 `software_candidate` / `rtl_measured`；单元测试内部另用 `synthetic_test` | 表明来源 | 同左；禁止给软件演示或人工测试改名伪称实测 |
| `case_id` | 非空字符串，当前三例之一 | 定位向量与清单 | 同左 |
| `tile_id` | 建议非负 `uint32`；**具体编号规则待确认** | 候选示范 K32 用 `k//32` | 示范为最后一个 K 块编号；硬件需定义 |
| `row`,`column` | 建议非负 `uint32`，分别 `<M`、`<N` | 逻辑 `Y[row,column]` | 同一输出元素 |
| `event` | 枚举 `mac` / `bias` | 某个 k 的加法提交 | 全部 K 项后的一次偏置加法提交 |
| `cycle` | RTL 候选 `uint32` 时钟沿计数；软件为空 | 真实提交周期 | 真实提交周期；复位起点、回绕待确认 |
| `valid` | 布尔 `0/1`；软件演示有效行均为 `1` | 若导出逐周期表，只有提交时为 `1` | 同左；空泡建议不导出为事件行 |
| `k` | 全局非负 `uint32`，`0≤k<K` | 与本次乘积所属数学项绑定，即使跨 K tile 也不归零 | 空，不虚构第 K 次乘法 |
| `x_bits`,`w_bits` | 原始 binary32 `uint32` 位模式 | `X[row,k]`、`W[k,column]` | 空 |
| `acc_before_bits` | binary32 `uint32` 位模式 | 此项**加法提交前**部分和，首项为 `0x00000000` | 完整 K 项后的部分和 |
| `product_bits` | binary32 `uint32` 位模式 | 本次乘法**单独舍入后**的结果 | 空 |
| `acc_after_bits` | binary32 `uint32` 位模式 | `round32(acc_before+product)` | `round32(acc_before+bias)` |
| `bias_bits` | binary32 `uint32` 位模式 | 空 | 该输出列的偏置 `bias[column]` |
| `result_bits` | binary32 `uint32` 位模式 | 空 | 最终输出；应等于 `acc_after_bits` |
| `rtl_commit` | Git 提交号文本；软件演示为空 | 实测须有可定位版本 | 同一运行须一致；`+dirty` 时补源码快照清单 |
| `input_manifest_sha256` | 64 位小写十六进制 SHA-256 文本 | 标识所用软件镜像清单版本 | 同左；还要用实际 `.bin/.mem` 哈希证实装载 |
| `reference_trace_sha256` | 64 位小写十六进制 SHA-256 文本 | 标识软件黄金 JSON 版本 | 同左 |

当前演示清单 SHA-256 为 `148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93`，黄金 JSON SHA-256 为 `a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b`。实际 RTL 轨迹必须记录它**真正使用**的输入版本，不得仅复制软件演示字段。三个算例的输入、每步结果和手算锚点见 [`fp32_software_pe_readiness_2026-10-18.md`](fp32_software_pe_readiness_2026-10-18.md)。

## 3. 现有 PE 信号与事件候选映射

只读检查本地缓存 `origin/hardware` 提交 `acfae7282f2d16f6fe8df476efed147f23df4b71` 的 `rtl/fp32_pe_mac.sv`：`trace_cycle`、X/W、部分和、乘积、bias 均为 32 位；`trace_k` 为 16 位；`trace_valid` 和 `trace_bias_valid` 为 1 位。**该模块没有 `row`、`column`、`tile_id` 输出。**`trace_k` 来自模块内部任务计数，任务重启时归零，不能不经映射就称为全局 K。模块当前是功能性延迟模型，其参考算术在延迟寄存器前组合求值；并非已经时序收敛的真实流水线证明。

候选采样方式（须经硬件 TB 验证）：

| RTL 标志 | 建议输出事件 | 同一事件需采的内容 | 尚待证明 |
|---|---|---|---|
| `trace_valid=1` | `mac`，一条有效 K 累加提交 | `trace_k`, `trace_x_bits`, `trace_w_bits`, `trace_product_bits`, `trace_acc_before_bits`, `trace_acc_after_bits`, `trace_cycle`；TB 补 `case_id,row,column,tile_id,global k` | 标志和所有数据是否同一个可见时钟沿；复位、`enable=0`、空泡时是否仍正确 |
| `trace_bias_valid=1` | `bias`，最终偏置加法提交 | `trace_bias_bits`, `trace_acc_before_bits`, `trace_acc_after_bits`, `result`/`result_valid`, `trace_cycle`；TB 补逻辑输出坐标 | `result_valid` 是否同沿；两类 valid 是否互斥；bias 是否真的只发生一次 |
| 两者均为 `0` | 无有效计算提交，可能是等待/空泡/输入接受/乘法在途 | 若做逐周期调试表，保留 cycle 和原始控制信号；**事件 CSV 可以不写行** | 原始寄存器残值不得当作新计算结果 |

如要对齐阶段事件“乘法完成但加法未完成”或“跨 K 块保存部分和”，需硬件另增具有明确 valid 的阶段轨迹；当前两种标志只足以描述建议的 **MAC 提交**和 **bias 提交**。K32 保存/恢复可先通过 `k31` 的 `acc_after_bits` 与 `k32` 的 `acc_before_bits` 是否逐位相等判断；若需要证明搬运机制，再交保存/恢复时序与存储读写 trace。不能把无效周期推断成保存事件。

## 4. 局部 K 与全局 K

软件演示在 `k32_boundary` 中 `tile_size=32`，故 `tile_id=0` 覆盖全局 `k=0…31`、`tile_id=1` 覆盖 `k=32…63`。一般映射建议为

```text
global_k = tile_start_k + local_k
tile_start_k = 该任务本次 K 块起始的全局索引
```

这只是数学身份，不规定调度器必须每块调用一次 PE。若整个 K=64 作为一次 PE 任务，当前模块 `trace_k` 可为 `0…63`；若两次 K=32 任务，每次 `trace_k` 可能是 `0…31`，必须由 TB/调度器提供 `tile_start_k` 才能转成全局索引，而且**不能在第二块清空部分和**。必须由硬件说明实际采用哪一种运行方式和部分和的保存/恢复路径。`trace_k=16'hffff` 在当前源码中是 bias 内部哨兵，CSV 的 bias 行仍应留空 `k`，不可把它解释为全局 65535。

## 5. 对拍和首错报告的建议

1. **先核来源。**固定软件清单/黄金 JSON 哈希，以及 RTL commit、源码快照、输入镜像哈希、filelist、仿真器版本和命令。若来源不同，先停止数值结论。
2. **再核事件身份。**对有效行使用 `(case_id,row,column,event,global k)` 做唯一键；`bias` 的 K 为“空”。核对每个输出恰有 `K` 个不同 `mac` 键和 1 个 `bias` 键，无重复、缺失、额外事件。硬件行可以跨 PE 交织，不能直接按 CSV 行号一对一比较。`tile_id` 用来校验映射与 K32 连续性，具体编号待硬件确认。周期单调性和延迟属于**另一个时序检查**。
3. **按事件比较位模式。**`mac` 比 `x_bits,w_bits,product_bits,acc_before_bits,acc_after_bits`；`bias` 比 `bias_bits,acc_before_bits,acc_after_bits,result_bits`。按原始 32 位字比较，不能用普通浮点相等吞掉 `+0/-0` 或 1 ULP 错误。
4. **首错格式候选：**`case_id=..., row=..., column=..., event=mac, global_k=32, tile_id=1, field=acc_before_bits, expected=0x40000000, actual=0x00000000, cycle=..., rtl_commit=...`。此例仅说明报告格式，**不是已发生的硬件错误**。若缺事件，写 `actual=<missing>`；若多事件，写 `unexpected/duplicate`；若位值错，另外列前一条成功事件供定位。
5. **单独检查时序。**记录 `in_valid`/输入接受、乘法完成、加法提交、bias 提交的周期，待硬件给稳定定义后再检查 8/4 拍对应关系。现在不能从软件黄金 `cycle` 空栏推算出 RTL 周期。

## 6. 需要硬件确认并交付的最小材料

软件侧已准备 `software/compare_pe_trace.py` 作为**候选格式比较器**：它要求真实数据明确标 `source_kind=rtl_measured`、填写周期和 RTL 提交号，按 `(case_id,row,column,event,global k)` 找事件，再逐位比较有效数据；默认不比较尚未约定的 `tile_id`，也不从周期推断 8/4 拍。它会先阻止输入清单或黄金轨迹指纹不一致的比较。可以在收到真正且符合本草案的硬件 CSV 后，从仓库根目录运行：

```powershell
python -m software.compare_pe_trace --expected software/examples/fp32_hand_image/expected_pe_trace_demo.csv --actual <硬件真实pe_trace.csv> --case-id k32_boundary --report <本地报告.json>
```

当前只用**人工构造并明确标作 `synthetic_test` 的测试行**验证比较器的排序、K32 首错、缺 bias、重复事件和错误来源阻断；人工行不能走命令行的真实轨迹入口，成功时只报告 `SYNTHETIC-MATCH`。没有任何真实硬件轨迹通过此工具。若硬件最终采用不同列或采样语义，先共同修订草案与工具，不能为了得到 PASS 在软件中悄悄重解释硬件字段。

1. **先交 `hand_2x2` 的真实单 PE `pe_trace.csv` 和 testbench 输出**，包含 RTL commit（若 dirty 另附源码快照指纹算法）、filelist、仿真命令、工具版本和日志，以及实际装载的 `.bin/.mem` 哈希；首组对拍后再扩展 `rounding_nonfused`、`k32_boundary`。
2. `trace_valid`、`trace_bias_valid` 是哪一个上升沿之后可见，是否分别只代表 MAC 与 bias **提交**，各位模式是否同沿有效；`result_valid` 的对齐关系、空泡与停使能行为。
3. 逻辑 `row,column`、物理 PE 位置、任务号、`tile_id`、`tile_start_k` 和内部 16 位 `trace_k` 的映射；K32 时 `task_first/clear_acc` 的真实策略。
4. 如要核阶段延迟，定义周期起点、复位、跨任务/回绕、输入接受和结果提交的计数口径；说明 8 拍乘/4 拍加模型是否仍为正式实现计划。
5. 特殊值、次正规、有符号零、溢出的数值处理方案，由双方负责人共同批准后才进入正式逐位验收。
6. 若宣称 **K32 跨块 SRAM 保存与恢复**，另交写入地址与值、读取地址与值、有效周期和与 k31/k32 部分和对应的 testbench 记录；单次 K64 连续计算的轨迹不能替代该证据。

收到这些信息之前，本文件只是**对接草案**；软件黄金 CSV 可供硬件 testbench 开发参考，但不能把它填入 `rtl_measured` 栏，也不能据此宣称 PE 或阵列通过。
