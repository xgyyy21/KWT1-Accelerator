# KWT-1 软件侧 FP32 PE 联调准备与阶段状态（2026-10-18）

> **候选规则，待双方负责人确认。**这是对已有代码、向量和测试的复核，不是新数值协议，也不是硬件 PE 验收。硬件 2026-10-18 回复中的九条规则是“临时实现依据”；特殊值、次正规、有符号零和流水线时序仍未冻结。参见 `E:\大二上\实验室\芯片设计\FP32硬件给软件回复草稿_2026-10-18.md`。

## 1. “算对”与“何时算完”先分开

软件参考描述一个输出 `Y[row,column]` 的**数值次序**：累加器设为 `+0`；依次取 `k=0…K-1`，将 `X[row,k]×W[k,column]` 单独舍入为 FP32，再与前一部分和相加并再次单独舍入；跨 K 分块不清零；最后只加一次该列 bias。硬件可以用很多时钟周期完成一步。8 拍乘、4 拍加尚未被软件推算成有效信号出现在哪个时钟沿，须以真实硬件轨迹为准。

## 2. 九条暂接受规则：源码与验证证据

下表的“软件已实现”只说本仓库代码；“测试覆盖”只说指定例子。**全部条款仍待双方正式确认。**源码路径相对仓库根目录。

| 候选规则 | 软件源码 | 测试/证据 | 当前判断 |
|---|---|---|---|
| binary32 原始 32 位字 | `software/fp32_reference.py:24,46,72`；输入为整数位模式，有限数被拆成精确整数×2 的幂；输出重新编码成 32 位字 | `test_fp32_reference.py` 手算字模式；`test_compare_fp32.py` 的单 bit 错误检查 | 软件已实现有限数位精确路径；NaN/∞行为未约定 |
| 每个输出从 `+0` 起步 | `run_ffn1_bits` 第 158 行；`trace_cell` 第 174 行 | `test_fp32_step_traces.py` 核首步 `acc_before=0x00000000`；`test_signed_zero_for_independent_multiply_and_add` | 软件已实现；首项为 `-0` 时仍执行 `+0 + (-0)`，结果按当前舍入模式为 `+0`，硬件待核 |
| K 从小到大 | 第 159、176 行的 `range(depth)`；分块版 `software/innovation/fp32_tiled.py:109` | `test_k_order_can_change_result` 的换序反例；分块测试 | 软件已实现；硬件调度及 PE 映射待证实 |
| 乘法每次单独舍入 | `multiply_bits` 第 102 行调用 `_round_dyadic`；后者在第 61、72 行执行最近值、正中取偶 | `test_nearest_even_and_gradual_underflow`、`test_nonfused_product_then_add` | 软件已实现；不是宿主 Python 浮点连续计算 |
| 加法每次单独舍入 | `add_bits` 第 110 行用整数对齐指数、精确求和后调用 `_round_dyadic` | 2×2 逐步固定锚点、零号和正中舍入测试 | 软件已实现 |
| 不融合成 FMA | 第 160–161 行先得 32 位 `product`，再调用 `add_bits`；乘、加是两个函数 | `rounding_nonfused`：第二个乘积 `0x3f800000`，加 `-1` 后 `0x00000000`；融合路径可得 `0xa8800000` | 软件已实现；硬件真实 PE 待对拍 |
| K=32 分块保留部分和 | `fp32_tiled.py:106–120` 的 `partial` 在 K 块循环外创建；基本参考连续循环 | `test_k32_boundary_preserves_partial_sum_and_adds_bias_once`、`test_tails_and_k_boundary_keep_partial_sum`；k31 后 `0x40000000`、k32 前同值、k32 后 `0xbf800000` | 软件已实现；硬件 `task_first/clear_acc` 控制待证实 |
| 全部 K 后每个输出加一次对应列 bias | `run_ffn1_bits` 第 162 行；分块版第 120 行 | 2×2 的两列不同符号偏置；K32 末值 `0xbf400000`；比较器故障注入可发现漏加/重加 | 软件已实现；硬件 bias 贯通待验证 |
| 最近值、正中取偶 | `_round_right_even` 第 61 行及 `_round_dyadic` 第 72 行 | 正中例 `1 + 2^-24 → 1`；最小次正规数乘 `0.5 → +0` | 软件已实现；RTL 位精确验收待确认 |

**特别注意：**软件当前对次正规采用渐进下溢，对有符号零保留位模式；`test_nearest_even_and_gradual_underflow` 覆盖 `0x00000003×0.5→0x00000002`，`test_signed_zero_for_independent_multiply_and_add` 覆盖乘法符号异或及 `+0+(-0)`。这是**候选软件行为**，不是硬件已接受的规则。软件对 NaN、±∞和有限运算溢出抛出 `UnsupportedFP32Case`；`test_unfrozen_special_cases_rejected` 固定此“尚不支持”状态，不等于正式允许硬件忽略这些输入。没有擅自修改参考实现。

## 3. 已备好的三组 PE 向量

九个 X/W/bias 输入 `.bin` 的字节数与完整 SHA-256 见 [`fp32_word_readback_hash_reconciliation.md`](fp32_word_readback_hash_reconciliation.md)。三组数据均在 `software/examples/fp32_hand_image/`；`manifest.json` 固定形状、字节数、字序和哈希。`*.mem` 每行一个 16 位字，FP32 **低 16 位在前**；`expected_traces.json` 保存每个输出、每个 k 的 `x_bits/w_bits/product_bits/acc_before_bits/acc_after_bits` 和 bias 后结果；`expected_pe_trace_demo.csv` 是同一信息的 80 行软件演示 CSV，含 74 个 MAC 和 6 个 bias 事件。两文件完全由软件生成，**不是真实 RTL trace**。

| 用例 | 形状与目的 | 可独立手核的位模式锚点 | 软件黄金结果 |
|---|---|---|---|
| `hand_2x2` | X 2×2、W 2×2、bias 2；检查普通正负数、行列和不同列偏置 | `Y[0,0]`：k0 `1×2→0x40000000`、累加仍 `0x40000000`；k1 `−2×1.5→0xc0400000`、累加 `0xbf800000`；加 `+0.25` 后 `0xbf400000` | 行优先：`0xbf400000, 0xc0200000, 0x40b80000, 0x3f000000` |
| `rounding_nonfused` | X 1×2、W 2×1；专门区分独立舍入与 FMA | k0 `−1×1→0xbf800000`；k1 原始输入 `0x3f800001×0x3f7ffffe`，舍入乘积 `0x3f800000`；再与 `−1` 加为 `0x00000000`；bias `+0` | `0x00000000`；融合参考可出现 `0xa8800000`，应判错 |
| `k32_boundary` | X 1×64、W 64×1；大部分权重为零，突出 K32 边界和偏置次数 | k31 乘积 `+2=0x40000000`、部分和 `0x40000000`；k32 **加前仍为** `0x40000000`，乘积 `−3=0xc0400000`、加后 `0xbf800000`；k63 后仍为 `0xbf800000`；末尾只加一次 `+0.25` | `0xbf400000` |

完整 64 项不在文档里重复抄写，以免另造一份会漂移的“黄金数据”。硬件 testbench 可直接读取 `.mem` 和 `expected_traces.json` 或演示 CSV；后者 `cycle`、`rtl_commit` 为空，`source_kind=software_candidate`。软件黄金轨迹 SHA-256：`a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b`；输入 `manifest.json` SHA-256：`148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93`。生成方式是 `software.examples.fp32_step_traces` 调用整数位精确 `multiply_bits`/`add_bits`；不是直接用 Python `float` 累乘。独立锚点和舍入边界由 `software/tests/test_fp32_reference.py` 检查。

复现现有黄金文件而不改写：

```powershell
python -m software.examples.fp32_step_traces --output-dir software/examples/fp32_hand_image --check
python -m software.examples.fp32_trace_csv --output-dir software/examples/fp32_hand_image --check
python -m unittest discover -s software/tests -p 'test_*.py'
```

## 4. 阶段状态和责任边界

| 工作 | 当前状态 | 可查证据 / 阻塞 | 负责人及下一步 |
|---|---|---|---|
| 软件单元测试 | **本轮已重跑：80 项，79 通过、1 跳过、0 失败** | `software/tests/`；含 6 项候选比较器人工行测试；跳过项依赖未安装的上游 sparse checkout；只证明当前实现与固定测试一致 | 软件：保持测试可复现，后续变更再跑 |
| FP32 数值参考与三组向量 | **软件候选已备**；协议未冻结 | `fp32_reference.py`、`expected_traces.json`、独立手算锚点；异常/次正规/零号仍待合同 | 软件与硬件负责人共同确认例外语义；软件保留旧版 oracle |
| 缓存局部读回 | 新本地 CSV 对软件镜像 **144/144 通过记录校验**；正式硬件来源未固定 | 新旧 CSV 差异及缺失日志见指纹复核报告；仅 `matrix_cache_manager` | 硬件给新文件提交、源码/filelist/日志；软件从固定提交重核 |
| 真实 FP32 单 PE 逐步对拍 | **待硬件验证**；软件候选比较器已备 | 未收到真实 `pe_trace.csv`；已有 80 行 CSV 是软件演示；`compare_pe_trace.py` 仅在人工合成测试行上跑过 | 硬件给 PE testbench、轨迹、映射与仿真命令；软件在双方确认字段后运行首错对拍 |
| 8×16 阵列、bias 和 K32 延续 | **待硬件验证** | PE 尚未完成真实逐步对拍，阵列内部分和和 bias 无实测 | 硬件接入后交阵列 trace 与结果；软件用三组向量核 |
| SoC/E203 端到端 | **待硬件和综合联调** | 缺总线/寄存器冻结及真实端到端运行日志 | 硬件/综合定接口、集成；软件再做驱动与端到端对拍 |

**这轮仍可独立做的事：**保持三组镜像和黄金轨迹可复现，准备合法数据来源及精度/NRMSE 测量，编写候选 trace 字段与首错格式。实际 PE 周期、物理 PE 到逻辑坐标的映射、特殊值语义必须待硬件材料和双方确认。见 [`fp32_pe_trace_contract_draft.md`](fp32_pe_trace_contract_draft.md)。
