# Speech Commands v0.02 验证音频获取记录（2026-10-16）

## 状态

**已取得一条来自 TensorFlow 官方归档传输的真实 WAV，并由固定版 KWT-1 源码的划分函数判为 `validation`。尚未拿到归档内原始 `validation_list.txt`，因此该样本仍是 `provisional`，不得作为已确认的官方验证样本，也不得用它宣称比赛精度合格。**

可用文件：

- 候选音频：`runs/input_validation/provisional/750e3e75_nohash_0.wav`
- 来源与哈希记录：`runs/input_validation/provisional/candidate.json`
- 提取脚本：`work/data_acquisition/extract_candidate.py`
- 对固定上游源码的复核脚本：`work/data_acquisition/verify_upstream_split.py`；实际输出 `pinned_source_which_set validation` 与 `official_list_membership_still_unchecked True`

## 来源与划分依据

1. [TensorFlow Datasets 官方构建器](https://github.com/tensorflow/datasets/blob/master/tensorflow_datasets/datasets/speech_commands/speech_commands_dataset_builder.py) 指向 `speech_commands_v0.02.tar.gz`，并明确从归档里的 `validation_list.txt` 和 `testing_list.txt` 取得划分。它把十个目标词以外的普通词记为 `_unknown_`。本样本的 `eight` 文件夹因此对应 `_unknown_`，其标签不影响测试 KWT-1 的 FFN 数值路径。
2. [Google Research KWS 数据准备说明](https://github.com/google-research/google-research/blob/master/kws_streaming/experiments/kws_experiments_30k_12_labels.md) 使用的 HTTPS 归档是 `https://storage.googleapis.com/download.tensorflow.org/data/speech_commands_v0.02.tar.gz`；本次请求的正是这一地址。
3. 固定 KWT-1 提交 `237e4097afd4f6851e0b82f0a8d65c2dfe8eae30` 的 [输入数据源码](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/kws_streaming/data/input_data.py) 中，`which_set` 删除文件名的 `_nohash_...` 后缀，取 SHA-1，映射到百分比。固定的 [flags.json](https://github.com/ARM-software/keyword-transformer/blob/237e4097afd4f6851e0b82f0a8d65c2dfe8eae30/models_data_v2_12_labels/kwt1/flags.json) 是 `split_data=1, validation_percentage=10, testing_percentage=10`。直接调用本地固定源码 `which_set("eight/750e3e75_nohash_0.wav",10,10)`，得到 `validation`；复写算法所得百分比约 `2.448351699474094`，二者一致。
4. [Google Research 维护者对划分的说明](https://github.com/google-research/google-research/issues/378) 表示 `kws_streaming` 的数据读取分支沿用原 Speech Commands 的划分，让测试名单与数据包的 `testing_list.txt` 一致。**这不是对本条验证音频的逐条清单证明。**

## 实际读取与校验值

Google Cloud Storage 的 HEAD 返回：对象长度 `2,428,923,189` 字节；`x-goog-generation=1523475715344020`；ETag/MD5 十六进制 `6b74f3901214cb2c2934e98196829835`。本地只请求前 `0–10,485,759` 字节，90 秒超时后实际收到 `2,158,483` 字节，前缀 SHA-256 为 `c3e218586d410c199925aa0646f0b138e7b75d3e4cdb5e802c517db708abce28`。该速度约 24 KB/s；完整归档在当前线路上不适合本轮等待。

从这段不完整但可解压的 gzip 前缀中，TAR 成员 `./eight/750e3e75_nohash_0.wav` 完整，WAV 文件大小 `32,044` 字节，SHA-256 为 `d72dd7e4654e12b92a29c1bb247ef30886b632a7a14424ab4abb85e6272ae27a`。解码头为单声道、PCM16、16 kHz、16,000 帧，恰好 1 秒。这个 WAV 的字节级哈希已存入 `candidate.json`，但**整个 2.43 GB 归档的 SHA-256 暂未在本地验证**。

## 完成正式确认的命令

需要在网络顺畅、空间足够的环境下载完整归档。以下命令在本项目根目录运行（Windows `cmd`/PowerShell 均可；现有 2.16 MB 前缀不是完整归档，不能改名当作完整文件）。

```text
curl.exe -fL --retry 5 --continue-at - -o work\data_acquisition\speech_commands_v0.02.tar.gz https://storage.googleapis.com/download.tensorflow.org/data/speech_commands_v0.02.tar.gz
third_party\venv38\Scripts\python.exe work\data_acquisition\confirm_with_list.py work\data_acquisition\speech_commands_v0.02.tar.gz runs\input_validation\provisional\candidate.json runs\input_validation\confirmed
```

第二条命令会先核对归档长度 `2,428,923,189` 和 [TorchAudio 数据集加载器源码固定的 SHA-256](https://github.com/pytorch/audio/blob/main/src/torchaudio/datasets/speechcommands.py) `af14739ee7dc311471de98f5f9d2c9191b18aedfe957f4a6ff791c709868ff58`，然后查原始 `validation_list.txt` 是否逐行包含 `eight/750e3e75_nohash_0.wav`，并比对完整归档内的 WAV 哈希。只有全部通过，才写入 `runs/input_validation/confirmed/manifest.json`、`validation_list.txt` 和已确认 WAV。

## 精度评估边界

- 当前 `provisional` 音频只用于**人工排查**WAV 解码及来源链。现有 `kwt_reference.py` 只接受 `train / validation / test / synthetic-smoke`，没有“待确认”枚举；在清单核对通过前，**先不让这条音频进入导出或精度流程**，尤其不能伪写 `--split validation`。
- 即使正式确认，**单条 `eight` 音频不能测总体精度**。KWT 对 `_unknown_` 按比例取样，且比赛的量化精度阈值需要足量、覆盖多类别的规定验证样本及与浮点基线相同的评分口径。
- 一旦硬件数值格式和验证音频批次确定，再做模型级精度统计；本次工作只解决可追溯样本的获取路径，不提供任何精度结论。
