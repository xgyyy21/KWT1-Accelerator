# KWT-1 真实权重冒烟测试记录（仍需合法样本验证）

日期：2026-10-16。这里记录实际执行过的步骤；本文件不是比赛精度报告。

## 指定材料

- 官方源码：`ARM-software/keyword-transformer`，目标提交 `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30`。`git ls-remote ... HEAD` 已返回该提交。完整仓库约有 313.7 MiB 原始 blob；网络中断了完整克隆，因此本次根据 GitHub 的固定提交树 [`kwt_tree.json`](kwt_tree.json) 只下载 KWT-1 运行所需文件到 `third_party/kwt_pinned_sparse`，逐个核对 Git blob SHA-1 与文件大小。
- 权重位置：`models_data_v2_12_labels/kwt1/best_weights.index` 与 `.data-00000-of-00001`。两者已取到并通过固定提交的 Git blob 校验；SHA-256 记录在导出 `manifest.json`。`software/kwt_reference.py` 启动时还会核查模型源码、配置与这两份权重的固定 Git blob 哈希。
- 数据：已生成 `runs/input_smoke/zeros_16k.npy`，恰好 16000 个 `float32` 零值。这是**合成波形，只能测试程序和模型加载**，不能用于比赛的精度评估或称为合法验证样本。

## 隔离环境

- 工程内 `third_party/venv38` 为 Python 3.8.20 隔离环境。
- 实际导入成功：TensorFlow 2.4.0、TensorFlow Addons 0.12.1、NumPy 1.19.5。`uv pip check` 返回全部已装包依赖兼容。
- 全部已装包版本记录在 [`kwt_env_freeze.txt`](kwt_env_freeze.txt)；这份清单记录当前环境，不保证逐项都与上游旧发行时完全一致。
- 上游 `requirements.txt` 原写 `tensorflow==2.4.0rc1`。目前安装的是正式版 2.4.0，**不是上游精确的 rc1 运行环境**；必须以真实 checkpoint 恢复、分类器与探针一致性、12 层 `X@W+b` 检查作为后续验证。
- 初次安装把 `protobuf` 解到 5.29.6，旧 TensorFlow 导入报生成描述符不兼容。已改为 `protobuf==3.20.3`、`tensorboard==2.4.1`，随后实际导入成功。
- 用 `uv` 操作此环境时应附 `--cache-dir third_party/uv-cache`，避免默认缓存落在受限的 Windows 临时目录。

## 实际跑通的检查

1. `work/run_sparse_reference.py --check-import` 成功导入未改动的固定版 `kws_transformer.py`；`--check-build` 用该 `flags.json` 构建 `(1,16000) → (1,12)` 模型。稀疏入口只为空闲的模型**注册表**放入占位，避免上游 `models.py` 顺带导入所有其他模型；KWT 自身的前向代码、SpeechFeatures、`utils.parse` 与权重仍是固定版文件。
2. 用 `third_party/venv38/Scripts/python.exe work/run_sparse_reference.py --repo third_party/kwt_pinned_sparse --raw-npy runs/input_smoke/zeros_16k.npy --output runs/reference_smoke/zero_audio_verified` 实际加载 `best_weights`，导出 12 个 `layer_XX.npz`。各层 `x/w/b/y_float` 为 `(99,64)/(64,256)/(256,)/(99,256)`；清单中的分类器与探针最大绝对差为 **0**，所有层的 NumPy `X@W+b` 与 Dense 输出最大绝对差为 **0**。
3. TensorFlow 曾打印 checkpoint 对象引用不一致的警告。为排除 FFN1 权重误取，导出器现逐张量直接读取 checkpoint，检查 **12 层共 24 个 FFN1 kernel/bias 数组与导出值完全相等**；独立脚本 [`verify_checkpoint_weights.py`](verify_checkpoint_weights.py) 又检查了一次。警告仍需如实保留在本地运行日志 `zero_verified.log`（运行产物不纳入源码包）；非 FFN1 的其余模型变量未在本次逐张量遍历对照。
4. 两次独立运行的 12 层 `x/w/b/y_float` 经 [`verify_smoke_determinism.py`](verify_smoke_determinism.py) 确认逐数组完全一致。已将第 0 层送入现有打包器，并用 `.mem` 回读检查 25,344 个整数输出的编码一致性；这仍不是 RTL 结果。
5. 候选格式扫描工具在这条**合成零波形**上能跑完 12 层。原型 `Q16.8` 的本地最大 NRMSE 为 **3.786%**；该数值只用于发现当前原型不宜直接定稿，**不是合法验证集或比赛精度**，也不用于选择最终量化格式。

## 尚未完成

1. 准备确知来源及划分的合法 Speech Commands 音频，用训练划分标定，用验证划分做多样本本地 12 层精度扫描。测试划分不用于选格式；零波形不能替代这些样本。
2. 与硬件同学冻结数值、内存与控制协议，再做真正的逐位 RTL 对拍与 E203 SoC 验证。当前 `.mem` 自比只核对文件编解码。
3. 若后来可取得上游原 `tensorflow==2.4.0rc1` 环境或完整仓库，可在同一输入上复核本次 TF 2.4.0/稀疏导入的输出。当前检查充分支持**软件冒烟通过**，不能替代官方未知评测。
