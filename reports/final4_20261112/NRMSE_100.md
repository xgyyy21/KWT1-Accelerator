# Speech Commands V2 公开测试集 100 样本本地精度预评估

日期：2026-11-12
位置：`D:\KWT1-Accelerator\final4_report_20261111\nrmse_verification\scv2_100\`
性质：**本地预评估**。不是官方 600 样本评测，不得写成"精度通过"。

---

## 1. 数据与选样规则（固定，可复现）

- 数据包：`D:\KWT1-Accelerator\speech_commands_v0.02.tar.gz`（2.3 GB，105,878 个成员，`testing_list.txt` 11,005 条）
- 划分：只用**官方 `testing_list.txt`**，不碰 train/validation
- 选样（`select_100.py`，无随机数）：
  - 10 个目标词 × 8 条 = 80（在每个词的字母序列表中均匀取点）
  - unknown × 10（10 个目标词以外的词，均匀取点）
  - silence × 10（官方 `_background_noise_` 录音中按等距窗口切 1 秒）
- 只解压这 100 条 WAV（3.04 MB），音频不进仓库
- 5 条短于 1 秒的片段由官方 loader 按 16000 采样补零（与 `input_data.py` 行为一致）

标签分布：`yes/no/up/down/left/right/on/off/stop/go` 各 8，`unknown` 10，`silence` 10。

## 2. 模型与预处理（官方路径，未重实现）

| 项 | 值 |
|---|---|
| 上游 | `ARM-software/keyword-transformer` @ `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30` |
| 运行时文件校验 | **30/30** 通过 Git blob SHA-1 校验（`verify_runtime_blobs`） |
| 权重 | `models_data_v2_12_labels/kwt1/best_weights` |
| FFN1 权重核对 | 12 层 ×（kernel,bias）逐张量 `assert_array_equal` 通过 |
| 结构（checkpoint `flags.json`） | 12 层、d_model=64、**mlp_dim=256**、单头、post-norm |
| 预处理 | 官方 `speech_features.SpeechFeatures`（模型内建 MFCC，raw 输入） |
| 探针一致性 | probe logits vs 官方分类器 `max|Δ| = 0.000e+00` |
| 推理设置 | batch=1、training=False、无 SpecAugment、无蒸馏、无 softmax |

## 3. 数值模型

冻结配置 `int16_frozen_d7329f2.json`，候选 `rtl_int48_fixed`：

- X：signed INT16，`x_frac = 12`
- W：signed INT16，`w_frac = 16`
- bias：signed INT32，尺度 `2^28`，64 次 MAC 后只加一次
- 累加：**48 位**
- 输出：RNE 右移 15/16 位，饱和到 ±32767；`-32768` 保留
- 指标（官方公式，层内汇总）：

```
NRMSE_l = sqrt(Σe²/N) / max(sqrt(Σref²/N), 1e-8)
```

浮点参考是**同一模型、同一层导出的 `y_float`**，不是 INT16 Golden 反量化。

## 4. 结果（100 样本，层内汇总）

| 层 | NRMSE | 3% |
|---:|---:|:--:|
| 00 | **0.006589 (0.659%)** | ✅ |
| 01 | 0.000134 | ✅ |
| 02 | 0.000154 | ✅ |
| 03 | 0.000452 | ✅ |
| 04 | 0.000230 | ✅ |
| 05 | 0.000670 | ✅ |
| 06 | 0.000137 | ✅ |
| 07 | 0.000171 | ✅ |
| 08 | 0.000135 | ✅ |
| 09 | 0.000114 | ✅ |
| 10 | 0.000103 | ✅ |
| 11 | 0.000115 | ✅ |

- **12 层最大值 0.659%（layer 00）**，远低于 3%
- 总元素 100 × 25,344 = **2,534,400** / 层
- 运行时间 25.6 s（100 样本，含模型加载）

## 5. 逐样本分布（重要，不能只看汇总）

| 层 | 中位数 | p95 | 单样本最大 |
|---|---:|---:|---:|
| 00 | 0.000096 | 0.012764 | **0.037786** |
| 03 | 0.000113 | 0.000275 | 0.003112 |
| 05 | 0.000129 | 0.000142 | 0.005883 |
| 其余 | 1e-4 量级 | < 2e-4 | < 1.4e-3 |

- **layer 00 有单样本 NRMSE = 3.78%**（`down/8769c34c_nohash_3.wav`），**单样本已超 3%**；
- 官方口径是"全部样本层内汇总"，该层汇总值 0.659%，因此按官方口径通过；
- 但说明当前冻结配置对**响度较大的样本**余量很小。

## 6. 饱和统计

| 层 | y 饱和次数 | x/w/bias/mac 饱和 |
|---|---:|---|
| 00 | 354 | 0 |
| 03 | 11 | 0 |
| 04 | 4 | 0 |
| 05 | 4 | 0 |
| 07 | 1 | 0 |
| 08 | 1 | 0 |
| 其余 | 0 | 0 |

- 输出饱和是合同允许的行为（饱和到 ±32767），但 layer 00 的 354 次说明 `y_frac=13` 对部分大值样本偏小；
- 输入/权重/偏置/累加器**均未饱和**（48 位充裕）。

## 7. 结论

1. 在 100 条真实 Speech Commands V2 测试样本上，冻结 INT16 配置的 **12 层汇总 NRMSE 最大 0.659%**，满足 3% 门槛；
2. 该结果是**本地预评估**，样本由我们按固定规则选取，**不是组委会 600 样本**；
3. 暴露一个真实风险：单样本最大 3.78%（layer 00），且 layer 00 有 354 次输出饱和——若官方 600 样本包含更多大响度样本，余量会被压缩；
4. 建议（不改冻结配置的前提下）：在 validation 划分上重新标定 `y_frac`，或在报告中如实说明该风险。

## 8. 复现

```bash
# 1) 选样（只解压 100 条）
python select_100.py

# 2) 跑 100 条（TF 2.4.0 + tfa 0.12.1 独立环境）
D:\kwt1_tf240\Scripts\python.exe run_100.py \
  --repo D:\KWT1-Accelerator\tmp\kwt_src\keyword-transformer-237e4097 \
  --work D:\KWT1-Accelerator\tmp\kwt_env \
  --wav-dir D:\KWT1-Accelerator\tmp\scv2_100\wav \
  --manifest D:\KWT1-Accelerator\tmp\scv2_100\sample_manifest_100.csv \
  --config frozen_ref\int16_frozen_d7329f2.json \
  --out scv2_100\full --warmup 10
```

产物：`full/per_layer_100.csv`、`full/per_sample_nrmse_100.csv`、`full/summary_100.json`、`run_100.log`。
