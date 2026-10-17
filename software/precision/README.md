# 本科 FFN1 的候选数值格式扫描

这个目录帮软件同学回答一个具体问题：**如果把浮点的 `X`、`W`、`b` 改成某种定点格式，12 层的 `Y=XW+b` 会偏离多少？** 运行时不需要 TensorFlow，也不需要硬件；但它需要先由官方模型提取工具生成真实的 `layer_00.npz` 到 `layer_11.npz`。本目录没有附带真实 KWT-1 数据，因此现在不能给出真实精度结论。

## 输入从哪里来

先按 [`../KWT_REFERENCE.md`](../KWT_REFERENCE.md) 在兼容环境导出。目录形如：

```text
runs/reference/
  sample_0001/
    manifest.json
    layer_00.npz
    ...
    layer_11.npz
  sample_0002/
    manifest.json
    layer_00.npz
    ...
    layer_11.npz
```

每个 NPZ 必须有 `x[99,64]`、`w[64,256]`、`b[256]`、`y_float[99,256]`。脚本会独立计算一次浮点 `X @ W + b`，检查它与保存的 `y_float` 足够接近，防止明显拿错层或把 GELU 后的值当作 FFN 第一线性层的输出。**这项检查仍不能证明 NPZ 的来源**；请保存并核查每个样本的 `manifest.json`、固定的源码提交、权重哈希、原始输入及数据划分。新版提取器要求明确填写 `--split` 和 `--source-id`，并在清单中写入 12 个 NPZ 的哈希。

## 候选格式是什么

[`candidates.example.json`](candidates.example.json) 给出三组**说明用途**的格式，不是最佳设置，也不是硬件团队已同意的规格。每组包含输入、权重、偏置、累加器、输出的位宽和小数位。计算规则完全沿用 [`../ffn1_numeric.py`](../ffn1_numeric.py)：最接近舍入，正负恰好居中时远离零；有符号饱和；按 `k=0..63` 逐项乘加，每次加法后饱和；再加偏置；最后调节输出小数位并饱和。

通俗地说，若 `x_frac=4`，就把实数乘以 `2^4=16` 后取整数。`0.5` 存成 `8`，用时再除以 `16`。位宽太小会截顶（**饱和**），小数位太少会丢细节；两者都会产生数值误差。因此应该用真实数据比较多个候选，再与硬件同学共同决定最终实现。

## 怎样运行

从项目根目录执行：

```powershell
python -m software.precision.study `
  --input-root runs/reference `
  --candidates software/precision/candidates.example.json `
  --report runs/precision/candidate_study.json
```

若本机的 `python` 未安装 NumPy，可换成工程 [`../README.md`](../README.md) 中的 Python 路径。还没有真实 NPZ 时，命令会明确报错，不会生成空白的“成功”结果。需要快速试运行，可用自己制作的合成 NPZ；报告会把无来源清单的样本标成 `unknown`，明示 `local_3_percent_screen=false`，不得用来论证 KWT-1 已达标。当前 `runs/reference_smoke/zero_audio_verified` 虽然用了真权重，但输入是合成零波形，且旧清单缺少来源字段，也只能做冒烟测试。

输出 JSON 中每个候选都有：

| 字段 | 怎样理解 |
|---|---|
| `layers["00"]...["11"].nrmse` | 先汇总同一层所有样本、所有输出元素的误差平方，再开方并除以浮点参考的均方根 |
| `maximum_12_layer_nrmse` | 12 层中最大的误差；任一层缺失时为 `null` |
| `per_task_nrmse` / `max_single_task_nrmse` / `single_tasks_over_3_percent` | 每个音频样本的每一层单独计算的误差、最大值及超出 3% 的任务列表，供定位个别失败任务；它与“每层汇总后取最大”的数值指标分开，未知/合成来源时也只能作为诊断 |
| `local_3_percent_screen` | 仅当每个样本都完整覆盖 12 层、都由新版清单声明为 `validation` 且本地文件哈希与固定模型元数据检查通过、最大误差不超过 3% 时才为 `true`；**不等于官方评测通过** |
| `sample_provenance` / `local_3_percent_screen_status` | 逐样本列出声明的划分、来源 ID、缺失或不一致的证据以及不能显示“通过”的原因。旧清单标 `unknown`，合成数据标 `synthetic_smoke`，真实但划分未核实的音频标 `unverified_dataset_membership` |
| `saturation_counts` | 输入/权重/偏置量化夹到上下限的元素数、乘累加中夹断的事件数、输出夹断的元素数；同一权重用于不同样本会重复计数 |
| `storage_estimate` | 一个任务四类张量理论上至少多少字节、若每个元素占整数个字节则多少字节；**不包含实际总线搬运、对齐、片上缓存或控制开销** |
| `sources` / `available_export_manifests` | NPZ 和已有导出清单的 SHA-256，方便复现实验；哈希本身无法证明声明的划分真实 |

**“本地筛查通过”只是一个有条件的工程检查。**`validation` 与来源 ID 是运行者填入的，工具不能从一个 WAV 文件自动判断它属于哪个官方划分。使用报告前，请拿 `source_id` 对照数据集原始划分清单；报告也不代表隐藏评测集成绩或 RTL 已逐位通过。不要把训练、测试、合成、未知来源的样本混进验证报告。

这里采用[赛题指南](https://mp.weixin.qq.com/s/XQrz5_71pYRwk-U0qIl4SA)第 10 页的本科精度公式：

`每层误差 = RMS(本格式输出 − 浮点参考) / max(RMS(浮点参考), 10^-8)`，最后取 12 层最大值。**不能**先算每条语音的百分比再求平均。报告的饱和计数可以解释精度变差，但 `0` 次饱和也可能因为小数精度不足而不达标。

## 工作顺序与边界

1. 用允许的**训练划分**做无梯度数值标定，写出几组候选位宽/小数位。
2. 用**验证划分**导出的多条样本运行本工具，观察每层误差，特别是最差的一层。测试划分不能用于调量化参数。
3. 和硬件同学共同冻结数值格式。必须同意每个信号的位宽、小数位、负数表示、舍入、每步饱和及偏置位置。`candidates.example.json` 不应直接变成 RTL 规格。
4. 用冻结格式的同一组输入和权重，逐位对比 RTL 输出字与 [`../ffn1_numeric.py`](../ffn1_numeric.py) 的整数输出。精度与逐位一致是两个不同检查。
5. 真实 SRAM 容量、读取顺序、总线流量、综合面积和任务时间仍需硬件/综合工程给出。这里的 `storage_estimate` 只能作设计讨论的下界。

用下列命令运行合成单元测试，它检查数学聚合、未满 12 层时不报达标、饱和计数和与现有数值模型的一致性：

```powershell
python -m unittest software.tests.test_precision_study -v
```
