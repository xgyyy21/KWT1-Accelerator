# KWT-1 FFN1 INT16 数值精度验证（NRMSE）结果

日期：2026-11-11
目录：`D:\KWT1-Accelerator\final4_report_20261111\nrmse_verification\`
性质：**真实样本、真实 FP32 参考、真实执行**；不是理论估算。
限制：本轮只有 **1 条**真实语音样本具备 FP32 逐层参考，**不是官方 600 样本评测**。

> **报告口径（2026-11-11 定稿）**
> 官方 600 条样本由组委会选取、评测后公布清单，目前未公开。
> 因此综合报告只写：**“数值模型与复现脚本已冻结；官方 600 样本精度待组委会评测”**，
> **不写“600 样本精度通过”**，也**不把 INT16 Golden 逐位对拍当作量化精度验收**。
>
> 冻结材料（commit `bbff21cf`）：
> - 配置 `software/precision/configs/int16_frozen_d7329f2.json`
> - 整数模型 `software/precision/int16_numeric.py`
> - 逐层 NRMSE 评测 `software/precision/int16_round01.py`（`_nrmse(error_sq, reference_sq, n)`：先汇总再相除）
> - 权重固定与 `y_float` 导出 `software/kwt_reference.py`

---

## 0. 结论速览

| 项 | 结果 | 状态 |
|---|---|---|
| 模型 | `models_data_v2_12_labels/kwt1/best_weights`，commit `237e4097` | ✅ 与官方发布逐字节核对（checkpoint index SHA-256 一致） |
| 12 层维度 | X[99,64]、W[64,256]、bias[256]、Y[99,256] | ✅ 与官方 `kwt1/flags.json`（d_model=64, mlp_dim=256）一致 |
| 真实样本数 | **1**（`eight/750e3e75_nohash_0.wav`，split=`unverified`） | ⚠️ 非官方 600 样本 |
| INT16 Golden 自洽 | 12 层 × 25,344 字，**0 mismatch**、0 饱和 | ✅ 本轮独立重算 |
| INT16 vs FP32 NRMSE（实测） | **9.449e-05**（layer 00，0.00945%） | ✅ 本轮实测 |
| INT16 vs FP32 NRMSE（12 层归档） | 最大 **1.549e-04**（layer 02，0.0155%） | ⚠️ 归档结果，FP32 包不在本机，无法重跑 |
| 12 层最坏情况上界 | 最大 **1.99e-03**（0.199%） | ✅ 本轮按半 LSB 界推导 |
| 3% 门槛（仅本样本） | 全部远低于 3%（最坏上界 0.2%） | ✅ 单样本工程验证，**非官方成绩** |
| 解码结果有限 | 是（无 NaN/Inf，无饱和） | ✅ |

---

## 0.1 冻结配置核对（2026-11-11，已在线读取）

仓库已转为 public，本轮直接读取 `bbff21cf` 下的
`software/precision/configs/int16_frozen_d7329f2.json`：

| 字段 | 冻结值 |
|---|---|
| `selected_candidate` | `rtl_int48_fixed` |
| `acc_bits` | **48** |
| `bias_bits` | 32 |
| `rounding` | `nearest_even` |
| `zero_point` | 0 |
| `x_w_y_range` | [-32767, 32767] |
| `reserved_int16_value` | -32768 |
| `model_commit` | `237e4097…` |
| `rtl_commit` | `d7329f200832697a4946bada5b72bf7db5b4ed7c` |
| `status` | frozen … **official validation accuracy pending** |

**与交付包逐项比对**（`check_frozen_config.py`，日志 `config_check.log`）：

```
layer  manifest(x,w,y,b)   frozen(x,w,y,b)   same
 00    12,16,13,32         12,16,13,32        True
 01    12,16,12,32         12,16,12,32        True
 ...
 11    12,16,12,32         12,16,12,32        True
format mismatches: 0
```

- 12 层 `(x_frac, w_frac, y_frac, bias_bits)` **完全一致**；
- 唯一差异：冻结配置累加器 **48 位**，交付包生成时为 38 位；
- 本数据累加绝对值最大约 1.2e9 < 2^31，**两种宽度都不触发截断**；
- 用 `--acc-bits 48` 重跑，12 层 NRMSE 与 38 位**完全相同**（见 `run.log`）。

结论：交付包的 12 层镜像**可以直接按冻结配置解释**，只需在报告中注明冻结候选名与 48 位累加。

**四个冻结文件与本地副本的逐字节比对**（`compare_frozen.py` / `frozen_ref/COMPARE.txt`）：

```
int16_frozen_d7329f2.json  remote=38ccd1d3… local=38ccd1d3…  match=True
int16_numeric.py           remote=98b9767a… local=98b9767a…  match=True (sha256)
int16_round01.py           remote=f78019b5… local=f78019b5…  match=True (sha256)
kwt_reference.py           remote=4ba5f479… local=4ba5f479…  match=True (sha256)
```

即本地用来复算的整数模型与评测脚本，与冻结提交完全一致；不是两套实现。

---

## 1. 模型核对：确认是 KWT-1，且 N=256 是对的

### 1.1 官方来源

- 仓库：`https://github.com/ARM-software/keyword-transformer`，commit `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30`（与 `KWT1_INT16_NUMERICAL_CONTRACT.md` 固定值一致）
- 权重目录：`models_data_v2_12_labels/kwt1/best_weights`
- **核对方法**：下载官方 `best_weights.index` 并计算 SHA-256

```
官方文件 SHA-256 = 5a60a0fa78a1855572084a42669768e2998d37e7d93c833962960fdb0db70fbc
模型导出清单记录   = 5a60a0fa78a1855572084a42669768e2998d37e7d93c833962960fdb0db70fbc
```

**逐字节一致** → 我们用的就是官方 KWT-1 预训练权重，不是重训、不是微调、不是 KWT-2/3。

### 1.2 关于 “FFN 隐藏维度 128 vs 256”

这是本轮最关键的核对项，结论如下：

1. **官方 README 的表格写的是 mlp-dim = 128**；
2. 但**官方发布的 KWT-1 checkpoint 自带 `flags.json`** 写的是：

```json
"num_layers": 12,
"d_model": 64,
"mlp_dim": 256,
"heads": 1,
"attention_type": "time"
```

3. 官方 `model_summary.txt` 显示总参数 **607,308**，与 README 表格里的 “607K” 一致——说明 `mlp_dim=256` 才是这份 checkpoint 的真实结构；
4. 比赛官方要求文档 `docs/REQUIREMENTS.md` 第 16 行写的是 **“FFN 64→256→64”**；
5. 因此 **N=256 正确，README 表格的 128 是过时/错误信息**。我们没有改模型、没有改层数、没有改维度。

### 1.3 维度对照

| 对象 | 本交付包 | 官方 KWT-1 | 一致 |
|---|---|---|---|
| X | [99, 64] | 98 帧 + 1 distill token，d_model=64 | ✅ |
| W | [64, 256] | FFN1 64→256 | ✅ |
| bias | [256] | 256 | ✅ |
| Y | [99, 256] | 99×256 | ✅ |
| 层数 | 12 | 12 | ✅ |

---

## 2. 数据来源链路（哈希闭环）

| 环节 | SHA-256 | 校验 |
|---|---|---|
| 模型导出清单 `model_export_manifest.json` | `e2a17b6b…3cb901` | = INT16 向量 manifest 的 `source_manifest_sha256` ✅ |
| 原始音频 `source_audio.wav` | `d72dd7e4…2ae27a` | = 导出清单 `input_sha256` ✅ |
| FP32 层数据 `layer_00.npz` | `5be944c1…0e21ce` | = INT16 manifest `source_npz_sha256` ✅ |
| INT16 向量 manifest | `107e6ae9…d429161` | = 归档 FP32 交叉校验里记录的 manifest ✅ |
| 量化配置 `int16_config.json` | `4dab987e…21d6a5` | = 合同文档固定值 ✅ |

即：**同一模型、同一权重、同一条音频、同一份量化配置**，没有混用其他模型输出。

---

## 3. 计算与判定方法

### 3.1 官方公式

`docs/REQUIREMENTS.md` 第 26 行：

```
NRMSE_l = RMS(Y_decoded - Y_float) / max(RMS(Y_float), 1e-8)
```

- 按层把全部元素汇总后再相除（不是逐样本比值取平均）；
- 12 层最大值 ≤ 3%；
- 解码结果必须有限。

### 3.2 INT16 路径（按数值合同）

```
qx = clip(RNE(X·2^12), -32767, 32767)
qw = clip(RNE(W·2^16), -32767, 32767)
qb = clip(RNE(b·2^28), -2^31, 2^31-1)
acc = Σ(k=0..63) qx·qw          # 38 位，带边界检查
acc = acc + qb                   # bias 只加一次
qy  = clip(RNE_SHIFT_RIGHT(acc, 28 - y_frac), -32767, 32767)
Y_decoded = qy / 2^y_frac
```

`y_frac`：层 00、03–10 为 13；层 01、02、11 为 12。

### 3.3 FP32 参考

用的是模型 `y_float`（FP32 FFN1 输出），**不是**把 INT16 Golden 反量化后冒充浮点参考。

---

## 4. 实测结果

### 4.1 12 层汇总

| 层 | golden mismatch | 算术-only NRMSE（下界） | 实测 vs FP32 | 归档 vs FP32 | 最坏上界 | ≤3% |
|---:|---:|---:|---:|---:|---:|:--:|
| 00 | 0 | 5.838e-05 | **9.449e-05** | 9.449e-05 | 1.508e-03 | ✅ |
| 01 | 0 | 1.124e-04 | — | 1.345e-04 | 1.530e-03 | ✅ |
| 02 | 0 | 1.308e-04 | — | **1.549e-04** | 1.734e-03 | ✅ |
| 03 | 0 | 7.305e-05 | — | 1.191e-04 | 1.853e-03 | ✅ |
| 04 | 0 | 8.281e-05 | — | 1.294e-04 | 1.979e-03 | ✅ |
| 05 | 0 | 7.995e-05 | — | 1.247e-04 | 1.846e-03 | ✅ |
| 06 | 0 | 8.936e-05 | — | 1.352e-04 | 1.991e-03 | ✅ |
| 07 | 0 | 8.018e-05 | — | 1.234e-04 | 1.836e-03 | ✅ |
| 08 | 0 | 8.237e-05 | — | 1.297e-04 | 1.939e-03 | ✅ |
| 09 | 0 | 7.192e-05 | — | 1.184e-04 | 1.859e-03 | ✅ |
| 10 | 0 | 5.988e-05 | — | 1.043e-04 | 1.716e-03 | ✅ |
| 11 | 0 | 9.276e-05 | — | 1.189e-04 | 1.564e-03 | ✅ |

- **实测 vs FP32**：本轮用本机真实 FP32 参考算出的值（只有 layer 00）。
- **归档 vs FP32**：2026-11-02 用完整 FP32 包算出的 12 层结果，记录在 `int16_fp32_crosscheck.json`，其中 `model_dense_vs_fp32_nrmse ≈ 8e-08` 证明参考确是模型 dense 输出。
- **最坏上界**：见 4.3。

### 4.2 layer 00 误差分解（实测）

| 分量 | NRMSE |
|---|---|
| 输入/权重量化（Y_arith vs Y_float） | 7.451e-05 |
| 输出重定点和舍入（Y_decoded vs Y_arith） | 5.838e-05 |
| 合计（Y_decoded vs Y_float） | **9.449e-05** |

最大绝对误差 2.435e-04；无饱和。

### 4.3 全 12 层最坏情况上界（本轮的严格推导）

因为量化是 RNE 且 manifest 记录 **x/w/bias/mac/y 饱和次数全部为 0**，所以

```
|X_float - X_deq| ≤ 0.5·2^-12
|W_float - W_deq| ≤ 0.5·2^-16
|b_float - b_deq| ≤ 0.5·2^-28
```

用 Frobenius 范数做三角不等式，得到 `RMS(Y_float - Y_decoded)` 的保守上界，再除以 `RMS(Y_decoded) - 上界`：

| 层 | 上界 |
|---:|---:|
| 00–11 | 1.51e-03 ~ 1.99e-03（最大 0.199%） |

这个上界比实测/归档值保守约 10–20 倍，**仍远小于 3%**。

---

## 5. 3% 门槛判定（仅本样本，非官方成绩）

| 口径 | 12 层最大值 | 结论 |
|---|---|---|
| 本轮实测（1 层） | 9.449e-05 = 0.0094% | 通过 |
| 归档完整 12 层（1 样本） | 1.549e-04 = 0.0155% | 通过 |
| 最坏情况严格上界（12 层） | 1.99e-03 = 0.199% | 通过 |

**结论：在本样本上，INT16 数值格式有约 15–200 倍于 3% 门槛的余量。**

---

## 6. 缺什么 / 最短补齐方法

### 6.1 缺失文件（本机与服务器均未找到）

| 文件 | 数量 | 哈希来源 |
|---|---|---|
| `layer_01.npz … layer_11.npz` | 11 个 | `model_export_manifest.json` 的 `layers[].sha256`（例如 layer 11 = `ed8ef048…4b35e1`） |
| `fp32_12_layer_pack_summary.json` | 1 个 | 归档记录 `fa14709485abc1ad6a36254834dc38b2af0fc9d98f66308c19e649509e426ee1` |
| `fp32_layerXX/expected.bin` | 12 个 | `int16_fp32_crosscheck.json` 的 `fp32_expected_sha256` |

同时本机环境：Python 3.7.0 + numpy 1.15.1，**没有 TensorFlow / tflite_runtime**，无法自己重跑模型导出。

配置一致性**已核对完毕**（见 0.1 节）：交付包镜像是 2026-11-02 用
`int16_config.json`（SHA-256 `4dab987e…21d6a5`，候选 `layer_max_abs`）生成的，
与冻结的 `int16_frozen_d7329f2.json`（候选 `rtl_int48_fixed`）在
**12 层 `(x_frac, w_frac, y_frac, bias_bits)` 上完全一致**；
差别只有累加器宽度（38 → 48），本数据下不触发截断，重跑结果不变。
因此本页数值可以直接按冻结配置引用。

### 6.2 最短补齐路径（二选一）

**A. 取回 FP32 包（最快，几分钟）**
从 2026-11-02 出包的那台机器（导出清单里记为 `C:\Users\Lenovo\…`）或备份中取回上面 24 个文件，放到任意目录，然后：

```bash
python run_nrmse.py \
  --vectors <int16_vectors 目录> \
  --npz <含 layer_00.npz … layer_11.npz 的目录> \
  --archived <int16_fp32_crosscheck.json> \
  --out <输出目录>
```

12 层就会全部变成 “measured”，无需改任何代码。

**B. 重新导出 FP32（需要环境）**
在 TensorFlow 2.4.0 + tensorflow-addons 0.12.1 环境里，用官方 repo `237e4097` + 同一条 `750e3e75_nohash_0.wav`，跑现有 `export_int16_vectors.py` 的输入阶段（或 `int16_round01.py`）重新生成 12 层 npz。

**B 不可行的原因**：本机装 TF 2.4 需要 ~400 MB 依赖，且必须保证预处理与官方逐位一致，本轮按要求未做大规模环境安装。

### 6.3 关于 600 样本

官方 600 样本清单**尚未公布**（`REQUIREMENTS.md` 第 17 行：组委会统一选取、结束后公布）。因此任何当前的 600 样本结果都只能叫“本地 600 样本预评估”，且我们目前只有 1 条带 FP32 参考的样本。

---

## 7. 哪些能写进报告，哪些只能算预评估

### 可以正式写入（来源、参考、方法全部可信）

1. 模型身份：官方 KWT-1、commit `237e4097`、checkpoint index 哈希与 GitHub 一致；
2. 结构：FFN 64→256→64、12 层、单头、PostNorm；N=256 与官方 `flags.json` 及赛题要求一致；
3. **数值模型与复现脚本已冻结**（commit `bbff21cf`，四个文件路径见文首）；
4. layer 00 单样本实测 NRMSE = **9.449e-05**（0.0094%），最大绝对误差 2.435e-04；
5. 12 层 INT16 Golden 独立重算 **0 mismatch**、0 饱和（这是 RTL↔软件数值模型一致性，不是量化精度验收）；
6. 12 层最坏情况上界 **≤ 0.199%**。

### 只能算“本地预评估”（不得写成绩）

1. 12 层 NRMSE 数值（仅 1 条样本，`split=unverified`，非官方 600 样本）；
2. 归档的 12 层数值需标注“2026-11-02 归档、FP32 包当前不在本机”。

### 明确不写

- ❌ “官方 600 样本精度通过”
- ❌ “12 层 NRMSE 全部实测评测通过”（只有 1 条样本，9 层是归档值）

---

## 8. 复现

```bash
cd D:\KWT1-Accelerator\final4_report_20261111\nrmse_verification
python run_nrmse.py ^
  --vectors  ..\numeric_format_audit\src\software\precision\results\int16_vectors ^
  --npz      D:\KWT1-Accelerator\tmp\fp32_first_synthesis_20261024\software\kwt1-real-ffn1-layer00-handoff-2026-10-23 ^
  --archived ..\numeric_format_audit\src\software\precision\results\int16_fp32_crosscheck.json ^
  --out      .
```

产物：
- `layer_nrmse.csv`（12 层逐层结果）
- `sample_manifest.csv`（样本与模型清单）
- `hash_check.csv`（48 个向量文件哈希核对）
- `summary.json`、`run.log`、`SHA256SUMS.txt`
