# KWT-1 官方参考数据提取：独立审计（2026-10-16）

审计范围：只读检查 `software/KWT_REFERENCE.md`、`software/kwt_reference.py`、`software/tests/test_kwt_reference_static.py`、本地 `third_party/` 与上游固定提交的源码和依赖。**未运行真实模型，未生成官方 12 层参考数据。**

## 一句话结论

提取思路与上游固定提交的 KWT-1 后归一化前向路径相符；当前真正阻断运行的是本地缺少官方源码/权重、Python 3.8/TensorFlow 2.4 兼容环境和合法原始音频。脚本的图构建、权重恢复、层名定位与分类输出复核还需要在真实环境做一次冒烟测试，静态检查不能替代。

## 当前实际状态

1. `third_party/` 是空目录；没有 `keyword-transformer` 源码，也没有 `kwt1/best_weights`。本地无法进行 `check_checkout()` 后的任何模型步骤。
2. 系统 `py -0p` 报告没有已安装的 Python，`python` 解析到 WindowsApps 占位程序；Codex 自带 Python 是 3.12，`pip show tensorflow tensorflow-addons` 均未找到。它可以跑不依赖 TensorFlow 的 NumPy 静态测试，不适合上游旧模型。
3. `software/KWT_REFERENCE.md` 已明示这一局限。`software/tests/test_kwt_reference_static.py` 仅验证 WAV 缩放和错误模型维度拒绝；没有检查真实权重恢复、`build_probe()` 的 Keras 图连接、12 个导出矩阵或最后分类输出一致性。

## 与上游源码的逐点核对

1. [固定版 `transformer_utils.py`](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/kws_streaming/models/transformer_utils.py) 的 `TransformerBlock.call` 在 postnorm 分支做 `attention → dropout → layernorm1(inputs + attention) → Dense → GELU → Dense → dropout → layernorm2`。当前 `build_probe()` 复制这一顺序，把 `layernorm1` 输出作为 `x`，第一 Dense 作为 `y_float`，与赛题的 FFN 第一线性层定义一致。`KWSTransformer.call` 在进入各编码层前做投影、分类 token 拼接和位置编码；脚本亦然。
2. [固定版 `kws_transformer.py`](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/kws_streaming/models/kws_transformer.py) 的时间注意力路径在末尾以一个 `Sequential(Dense(label_count))` 分类头处理 class token。脚本复用模型最后一层分类头，并比较官方 `predict` 与探针 `predict`；这是正确的关键交叉检查。但未真实执行，不能保证在该旧 Keras 版本中层名查找、加载状态对象和新图都能跑通。
3. 固定 `kwt1/flags.json` 明确为 12 层、`d_model=64`、`mlp_dim=256`、`heads=1`、`preprocess=raw`、`desired_samples=16000`，和脚本形状检查相符。上游 README 的 KWT-1 介绍表曾写 `mlp-dim=128`，**与这个具体权重目录的 flags 不一致**；此项目应以赛题指定的提交、目录及 flags 为准。参见[固定 flags](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/models_data_v2_12_labels/kwt1/flags.json)。
4. [上游 SpeechFeatures](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/kws_streaming/layers/speech_features.py) 在训练模式下有随机时间扰动和 SpecAugment 的分支。脚本设置 `sp_time_shift_ms=0`、`sp_resample=0`、`use_spec_augment=0`、`use_spec_cutout=0`、`training=False`，并重复推理对比以捕捉不稳定值。数据读取流程里的 `time_shift_ms`、`resample` 不在这个直接喂 `raw-npy` 的脚本中执行；若要按官方划分评测，原始音频样本来源与前处理必须另行记录。
5. `PINNED_BLOBS` 和 `git rev-parse HEAD` 对官方来源的校验很严格。优点是避免悄悄混入别的模型；要求将仓库精确定位到该提交，不能直接用 main 分支。若用 ZIP，需确认压缩包内权重确实是完整 checkpoint，而非外部占位文件。上述文件存在性和哈希只能在真正下载后验证。

## 兼容环境的具体风险

1. [上游 `requirements.txt`](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/requirements.txt) 写 `tensorflow==2.4.0rc1`、`numpy==1.19.5`，但 `tensorflow_addons` **没有固定版本**。当前 [PyPI 的 2.4.0rc1 版本页](https://pypi.org/project/tensorflow/2.4.0rc1/) 返回 404；可访问的 [TensorFlow 2.4.0 正式版](https://pypi.org/project/tensorflow/2.4.0/)提供 Windows CPython 3.8 wheel。若安装正式版，需要把“与上游测试的 rc1 不完全相同”记入运行清单。
2. [TensorFlow Addons 官方兼容矩阵](https://github.com/tensorflow/addons/blob/v0.12.1/README.md)列出 Addons `0.12.1` 与 TensorFlow 2.4、Python 3.8 兼容；[其 PyPI 发布页](https://pypi.org/project/tensorflow-addons/0.12.1/)有 Windows CPython 3.8 wheel。**建议作为候选锁版本**，最终以实际导入和探针通过为准；不要运行 `pip install -r requirements.txt` 后任由 pip 选择最新版 Addons。
3. 旧 TensorFlow 对 Python 3.12 没有对应轮子。隔离的 64 位 Python 3.8 环境是现实起点；不应在自带 3.12 环境中强行升级整个模型栈后声称与指定版本等价。

## 优先下一步（无需硬件资料）

1. 在受控目录获取指定的官方源码和 `best_weights`，先运行 `check_checkout()` 核对提交或关键文件 blob 哈希，并把文件/权重哈希留存。当前 `third_party` 为空，这一步尚未完成。
2. 建独立 Python 3.8 环境；优先尝试官方要求版本，若 `2.4.0rc1` 无法获取，记录原因后试 `tensorflow==2.4.0`、`numpy==1.19.5`、`tensorflow-addons==0.12.1`。验证 `import tensorflow`, `import tensorflow_addons`, 版本号，然后才运行脚本。其它上游依赖按报错安装并最终冻结清单。
3. 用一条**确知来源**的 16 kHz、16000 采样合法音频做冒烟测试。核对 12 个 `.npz`、每个数组形状、`manifest.json` 的 `classifier_max_abs_error` 与各层 `max_abs_numpy_vs_dense`；这一步若失败，优先修图连接/层名/加载问题，不应跳过校验。
4. 在更多**验证划分**样本上重复导出，并保存输入来源、模型与依赖版本。单个 WAV 冒烟测试不证明官方 12 层最大 NRMSE 或最终比赛成绩。

## 可交给根任务的风险优先级

- **P0：外部资源/环境缺失。** 现阶段无法完成真实模型导出，不能把合成 NPZ 叫官方参考。
- **P1：旧依赖可安装性。** 原 rc1 版本页已无法访问，Addons 必须选兼容版；应准确记录替代版本。
- **P1：探针只做静态验证。** 真实 checkpoint 上的 Keras 图和 `predict` 一致性尚未验证，需要冒烟运行后才能承诺 12 层。
- **P2：官方数据来源。** 自选 WAV 可测试程序，但多样本精度需使用规定划分与标签流程，不能混用测试集调参数。
