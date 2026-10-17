# KWT-1 第一线性层参考数据提取

本脚本是 PC 端离线工具，不是 E203 驱动。它使用赛题指定的 ARM Keyword Transformer 源码提交 `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30` 和 `kwt1/best_weights`，对**一条**原始音频输入导出 12 个编码层的 FFN 第一线性层数据。无需另写 MFCC、注意力或 LayerNorm 公式。

## 输出是什么

每次运行生成 `layer_00.npz` 到 `layer_11.npz`。每个文件包含：

| 键 | 形状 | 含义 |
|---|---:|---|
| `x` | `(99, 64)` | 该层第一线性层输入：注意力残差之后、第一处 LayerNorm 之后的值 |
| `w` | `(64, 256)` | 该层第一 Dense 的权重 |
| `b` | `(256,)` | 该层第一 Dense 的偏置 |
| `y_float` | `(99, 256)` | **GELU 之前**的官方 TensorFlow Dense 输出 |

`manifest.json` 记录源码提交、30 个运行时源码/配置/权重文件的固定哈希清单摘要与核验数量、输入与权重文件哈希、Python 库版本、推理配置覆盖项、逐层 `X @ W + b` 误差，以及每个 NPZ 的 SHA-256。还会记录由操作者声明的样本划分 `split` 和来源编号 `source_id`。哈希能检查文件是否改变；划分声明仍要和原始数据集的清单核对。原始 `flags.json` 是训练配置，启用了 SpecAugment；脚本显式关闭音频增强和训练模式，并对同一音频重复推理，检查中间结果稳定。随后它重走官方模型层对象中的前向计算，核对最后的分类输出与原模型相同；若不相同，**不会导出**数据。另检查 `x @ w + b` 与 TensorFlow Dense 输出数值接近。由于 NumPy 和 TensorFlow 的矩阵乘法规约顺序可能不同，这项检查是容差比较，不要求浮点位级相同。

这组文件可供数值模型、量化搜索、硬件模块测试共同使用。它只代表你输入的这一条样本；比赛要求的 12 层精度验证必须在更多合法样本上重复，不能用一个样本的结果代替最终评测。

## 运行前准备

1. 在 `third_party/keyword-transformer` 准备[官方仓库](https://github.com/ARM-software/keyword-transformer/tree/237e4097)，定位到上述提交，并确认 `models_data_v2_12_labels/kwt1/best_weights.index` 与 `best_weights.data-00000-of-00001` 都存在。脚本也接受该提交的 GitHub ZIP 解压目录：每次提取前它会核对 30 个运行时源码、配置和权重文件的 Git blob 哈希；Git HEAD 正确但工作树文件被改动也会被拒绝。
2. 使用隔离的 Python 3.8 环境。当前工作区的 `third_party/venv38` 已能导入 TensorFlow `2.4.0`、TensorFlow Addons `0.12.1`、NumPy `1.19.5`，完整已安装版本见 [`../work/kwt_env_freeze.txt`](../work/kwt_env_freeze.txt)。上游原写 TensorFlow `2.4.0rc1`；目前使用的正式版 **不是完全相同的运行环境**，因此仍需实际核对权重与模型输出。Codex 自带 Python 3.12 没有兼容的旧 TensorFlow。
3. 准备一条 16 kHz、单声道、恰好 16,000 个采样的 `float32` NumPy 原始波形文件，或 16 kHz 单声道 16 位 PCM WAV。`.npy` 应包含送进官方模型的**时域音频**，形状 `(16000,)`，不是 MFCC。WAV 短于 16000 帧时补零，长于 16000 帧时取前 16000 帧；已与 TensorFlow 2.4 的 `tf.audio.decode_wav(desired_samples=16000)` 对 8000、16000、17000 帧样例逐元素比对。`--wav` 的解码一致性不代替官方数据划分与完整评测流程。

例如在项目根目录运行：

```powershell
python software/kwt_reference.py `
  --repo third_party/keyword-transformer `
  --raw-npy path/to/one_validation_audio.npy `
  --split validation `
  --source-id 'validation/one_validation_audio.wav' `
  --output runs/reference/sample_0001
```

如果是标准 PCM WAV：

```powershell
python software/kwt_reference.py `
  --repo third_party/keyword-transformer `
  --wav path/to/one_second.wav `
  --split synthetic-smoke `
  --source-id 'local/wav_smoke_001' `
  --output runs/reference/wav_smoke
```

在当前机器上，`python` 命令应替换为自己创建的 TensorFlow 2.4 兼容环境中的解释器路径。脚本会拒绝其他 KWT 版本、形状不符的模型或音频，以及最后分类结果不一致的探针计算。

`--split` 必填，可选 `train`、`validation`、`test`、`unverified`、`synthetic-smoke`。`--source-id` 也必填，填写能在原始数据记录中找到的稳定编号，例如相对音频路径；它不是模型自己推断的。真实音频的原始划分清单尚未核实时，请用 `unverified`；人工生成的波形用 `synthetic-smoke`。两者都不能猜成 `validation`，也都不会使本地验证集筛查通过。旧版本导出的清单没有这两个字段，会标成 `unknown`。测试划分不得用于调候选位宽。

若完整 Git 仓库难以下载，当前工程另有一个**只包含所需文件的固定提交副本** `third_party/kwt_pinned_sparse`：[`fetch_kwt_sparse.py`](../work/fetch_kwt_sparse.py) 可用 `--preset-kwt1` 从固定树索引取回并逐个核对 30 个 Git blob。导出器自身也在每次运行时用 [`kwt_source_integrity.py`](kwt_source_integrity.py)重新核查。上游 `models.py` 在导入 KWT 时还会导入所有无关模型；[`run_sparse_reference.py`](../work/run_sparse_reference.py)只为空闲的模型注册表注入占位，仍使用未修改的 KWT 模型、前处理和权重文件。这个办法已在合成零波形上导出 12 层；若使用完整仓库，优先直接运行上面的正式命令。

## 与硬件同学核对的三件事

1. `w[k,j]` 对应 `x[t,k]`，输出 `y_float[t,j]`。不要把 `w` 转置后当作原始权重。
2. `y_float` 是第一层 Dense **加完偏置但尚未经过 GELU**的输出。
3. `.npz` 保存的是浮点参考；硬件传输的数值编码、地址布局、定点舍入和饱和规则，需要由数值模型与打包脚本另行约定，不能直接把 `.npz` 当作 SRAM 镜像。

## 官方依据

- [赛题指南](https://mp.weixin.qq.com/s/XQrz5_71pYRwk-U0qIl4SA)
- [指定 KWT-1 配置](https://github.com/ARM-software/keyword-transformer/blob/237e4097/models_data_v2_12_labels/kwt1/flags.json)
- [Transformer 前向路径](https://github.com/ARM-software/keyword-transformer/blob/237e4097/kws_streaming/models/transformer_utils.py)
- [模型构建与官方前处理](https://github.com/ARM-software/keyword-transformer/blob/237e4097/kws_streaming/models/kws_transformer.py)

## 当前验证状态

已用指定提交的真实 `best_weights` 和**合成**零波形运行端到端冒烟测试，输出在 `runs/reference_smoke/zero_audio_verified`（生成文件不纳入源码）。得到 12 个形状正确的 NPZ；分类器与探针最大差异为 0，每层 `X@W+b` 与 Dense 输出最大差异为 0；新加入的检查还逐张量证明 12 层共 24 个 FFN1 权重/偏置数组与 checkpoint **完全相同**。两次独立运行的 `x/w/b/y_float` 也逐数组一致。详情见[`../work/real_kwt_bootstrap.md`](../work/real_kwt_bootstrap.md)。

**零波形不是 Speech Commands 验证样本。**这一结果证明提取程序和当前环境可用，不证明任何候选位宽满足赛题 3% 误差要求。当前零波形目录是在新增来源字段之前导出的旧清单，因此精度工具将其标成 `unknown`；即使数值误差很小，也不能显示为通过本地 3% 验证筛查。下一步需要确知来源及划分的合法音频，在训练划分做标定，在验证划分上做多样本 12 层扫描；最终仍以比赛评测为准。
