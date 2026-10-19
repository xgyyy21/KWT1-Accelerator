# 单 PE 轨迹合同执行版（根据软件侧 2026-10-19 回复）

日期：2026-10-20。用于本轮 K=2 `hand_2x2` 正式 19 列联调包；不代表阵列、SoC 或所有 FP32 边界值已经验证。

## 数值范围

- 有限、且每一步乘法和加法均不溢出的 binary32。
- 乘法和加法各自采用最近偶数舍入（RNE），禁止 FMA；按全局 K 递增顺序累加，初始部分和为 `0x00000000`。
- bias 在全部 K 项之后只加一次。跨 K 分块不清零部分和。
- 次正规数采用逐渐下溢，不默认清零。正负零保留各自位模式，严格逐位比较；不允许 1 ULP 容差。
- NaN、Inf、溢出暂在合同外，双方另定规则。这不表示比赛最终可忽略这些情况。
- 本轮用例不覆盖次正规数、负零或非融合舍入专用边界，不把规则约定当成测试覆盖证明。

## 19 列及含义

| 字段 | 定义 |
|---|---|
| `source_kind` | 真实 DUT 有效事件固定为 `rtl_measured`，不指物理芯片测量 |
| `case_id` | 本轮为 `hand_2x2`；一个文件中不重复放入相同 case 的多个任务实例 |
| `tile_id` | MAC 为全局 `k // 32`；bias 为 `(K-1) // 32`，本轮均为 0 |
| `row` | 逻辑输出 Y 行号，0 开始 |
| `column` | 逻辑输出 Y 列号，0 开始 |
| `event` | `mac`：累加提交；`bias`：最终偏置加法提交 |
| `cycle` | 下述采样口径的真实提交周期，不用软件黄金结果猜测 |
| `valid` | 仅导出有效事件行，固定为 `1` |
| `k` | MAC 为全局 K，bias 留空 |
| `x_bits` | MAC 的 `X[row,k]` 原始位模式；bias 留空 |
| `w_bits` | MAC 的 `W[k,column]` 原始位模式；bias 留空 |
| `acc_before_bits` | 当前加法的输入部分和，不是从最终输出反推 |
| `product_bits` | 当前乘法独立舍入后的结果；bias 留空 |
| `acc_after_bits` | 当前加法独立舍入后的累加寄存器提交值 |
| `bias_bits` | bias 事件的 `bias[column]`；MAC 留空 |
| `result_bits` | bias 事件最终输出，等于 `acc_after_bits`；MAC 留空 |
| `rtl_commit` | 硬件 Git 基线提交，新增未提交 TB 时附 `+dirty`；精确复现以所附源码快照及逐文件哈希为准 |
| `input_manifest_sha256` | 指定软件 `manifest.json` 原始文件字节 SHA-256，不能指向自建清单 |
| `reference_trace_sha256` | 指定软件 `expected_traces.json` 原始文件字节 SHA-256，不能改为重新排版后的 JSON |

列顺序与软件 `software/examples/fp32_trace_csv.py` 的 HEADER 一致。整数为 ASCII 十进制；FP32 为小写 `0x` 加 8 位十六进制；空字段为空字符串。UTF-8/ASCII，无 BOM。

## 来源约定

- 软件基线：`d11d169ea6f7b8500d6a2186c803d0f1a5eba709`。
- `manifest.json`：`148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93`。
- `expected_traces.json`：`a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b`。
- 从 Git blob 导出原始字节，无 checkout 换行转换；保留实际输入 `.mem/.bin`。TB 用 `$readmemh` 实际读取 `x.mem/w.mem/bias.mem`，FP32 为 `{高16位word,低16位word}`。
- `inputs` 中其他用例/参考输出仅为完整保留软件输入目录，不代表本轮 TB 加载它们。实际加载清单见 `replay/input_validation.json`。
- `software_snapshot` 为固定软件提交导出的工具子集，不修改算法。原始 18 列材料单独存放为 `historical_18col`，不冒充本轮运行。

## 周期和信号采样约定

- 仿真时钟周期为 10 ns，仅为功能仿真，不表示 150 MHz 时序达标。
- 复位在下降沿释放，复位释放后的第一个上升沿为周期 1。
- 本次运行只复位一次，四个逻辑输出任务间周期不归零。若复位重新运行，应生成另一份运行记录，不能混入相同事件身份。
- DUT 在上升沿通过非阻塞赋值更新输出；TB 在该上升沿后 `#1ns` 采样，确保读取 NBA 更新后的有效信号和数据。
- `trace_valid=1` 时导出 MAC，`trace_bias_valid=1` 时导出 bias。两者互斥。
- bias 提交时 `result_valid=done=1`，`result=trace_acc_after_bits`；MAC 时 `result_valid=0`。无有效事件的周期只写入 `signal_trace.csv`，不写正式事件 CSV。
- 本轮使能恒为 1；包含输入结束后的空泡及每个结果后的观察周期。停使能、复位中断、周期计数回绕不在本轮覆盖范围。当前计数不能用于无约束长时间连续运行的回绕保证。
- 乘法边界：接受输入的上升沿到 `product_mem` 实际写入的上升沿相差 8 个周期。
- 加法边界：加法发起的上升沿到累加器提交的上升沿相差 4 个周期。输入接受到最终 MAC 提交还包含收集/调度等待，不承诺所有输入均固定 12 拍提交。
- 内部阶段信号只用于 TB 只读观察和时序断言，不用内部参考函数制造 CSV 值。
- 当前算术在组合函数中计算后经过延迟寄存器；本轮验证的是 RTL 功能和 8/4 拍接口边界，不证明乘加算术已物理拆成时序收敛的 8/4 级流水线。

## 坐标与验收

一个真实物理 PE 顺序计算逻辑 `(0,0),(0,1),(1,0),(1,1)`。本轮每次任务 K=2，`trace_k` 即全局 K=0、1；未执行 K=32 跨块。每个输出应有 2 条 MAC 和 1 条 bias，共 12 事件。

逐事件键为 `(case_id,row,column,event,k)`。使用软件原版比较器，显式启用 `--compare-tile-id`。软件工具返回的 `BIT-EXACT-CANDIDATE` 保留原文；本地通过不等于软件负责人已独立复核通过。

