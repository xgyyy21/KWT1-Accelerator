# 一条真实音频的功能冒烟记录（划分未核实）

日期：2026-10-17。**这不是验证集精度报告，也不是 RTL/SoC 测试。**音频取自 Speech Commands v0.02 官方归档的一个 WAV 成员 `eight/750e3e75_nohash_0.wav`，SHA-256 为 `d72dd7e4654e12b92a29c1bb247ef30886b632a7a14424ab4abb85e6272ae27a`。上游 KWT 的哈希划分函数在所用配置下把该名称分到 `validation`，但尚未取到原始 `validation_list.txt` 直接核对成员，所以在工具清单中**只标 `unverified`**。样本和模型权重不纳入共享源码仓库。

## 做了什么

1. 使用固定 KWT-1 提交 `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30`、固定 `best_weights` 和隔离的 Python 3.8/TensorFlow 2.4.0 环境，运行 `work/run_sparse_reference.py`。提取器先核验 30 个运行时源码/配置/权重文件的固定 Git blob，再对 WAV 做官方前处理，导出 12 个 FFN 第一线性层的 `x/w/b/y_float`。
2. 提取完成：12 个 NPZ；每个 `X[99,64]`、`W[64,256]`、`b[256]`、`Y[99,256]`；24 张 FFN1 权重/偏置张量与 checkpoint 核对；重建的分类输出与官方模型输出最大差异为 0。所导出的每层 `X@W+b` 与 Dense 输出的本地检查最大差异为 0。`manifest.json` 保留各文件与原音频哈希。
3. 用新建的**候选 FP32 非融合顺序参考**把全部 12 层分别打包为 `x/w/b/expected` 字节与 16 位字镜像。第 0 层输入 NPZ 的 SHA-256 为 `5be944c1d4816fdbefb2a4ff124ff7a62da6540cf74d2ab020bea4130e0e21ce`；其 `expected.bin` 共 101,376 字节，SHA-256 为 `24c84d16792bd5ab10bedfce5ebfd84a6305495477672d3144044e1ce33a51c5`。12 层合计 304,128 个 FP32 期望输出。逐层核对了 NPZ 输入哈希、`x/w/b/expected` 的形状、文件大小、`.bin` SHA-256，以及 `.mem` 中每个 16 位字和 `.bin` 的对应关系。本地汇总见 `kwt1-real-audio-smoke/fp32_12_layer_pack_summary.json`，其 `split=unverified`、`valid_precision_claim=false`。这些结果**仍待硬件冻结乘加、舍入和布局后才能作为 RTL 黄金文件**。
4. 用 [`measure_fp32_model_gap.py`](measure_fp32_model_gap.py) 独立检查全部 12 层候选 FP32 结果与 TensorFlow Dense 浮点输出：304,128 个元素中 96,698 个位模式相同；逐层归一化 RMSE 最大为 `9.679577440846806e-8`（第 11 层），全体元素最大绝对差 `7.152557373046875e-7`。第 0 层单独为 25,344 个元素中 7,618 个位模式相同、最大绝对差 `4.76837158203125e-7`、RMSE `4.638602383174627e-8`、归一化 RMSE `7.702763478182769e-8`。完整本地报告是 `fp32_vs_model_unverified.json`。两者不要求逐位相同，因为库和草案可能采用不同求和顺序；这只是**一条未核实划分样本的算术差异检查**，不是模型识别准确率、合法验证集精度或 RTL 正确性。
5. 将现有 Q16.8 **后续量化候选**仅在这一条来源未核实的真实音频上扫描 12 层，最大本地归一化 RMSE 为 `2.3654192107551097%`。报告明确为 `unverified_dataset_membership`、`local_3_percent_screen=false`、`ineligible_sample_provenance`。这一数字不能证明赛题 3% 门槛已通过，也不能替代首版 FP32。

## 复现边界与下一步

- 原始输出在本机独立目录 `C:\Users\Lenovo\Documents\Codex\2026-10-16\kwt1-real-audio-smoke`，未作为待上传源码。脚本与测试在 `software/`、`work/`；固定版本和哈希写在 `software/kwt_runtime_blobs.json` 及各运行清单中。
- 若要把样本升级为真正的验证划分证据，先取得并核对原始数据集的 `validation_list.txt`，保存其来源和哈希，再用多条合法样本做 12 层统计。不能只凭文件名、哈希函数或单一样本声称满足比赛精度。
- 硬件侧仍需确认 FP32 运算边界、外存布局和仿真读入方式；目前没有与这一镜像对应的 RTL 输出或完成计时证据。
