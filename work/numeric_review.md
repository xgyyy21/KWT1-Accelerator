# KWT-1 软件数值链路独立审查（2026-10-16）

范围：只读审查模型提取、定点参考模型、任务打包、12 层误差统计及官方本科 3% 判据。赛题事实以 `work/contest_audit.md` 记录的[官方赛题指南](https://mp.weixin.qq.com/s/XQrz5_71pYRwk-U0qIl4SA)第 4–7、10–11 页为准。本报告不把合成零音频或本地自造样本当成赛题精度验证。

## 已确认的正确之处

- 固定版上游 `TransformerBlock.call` 是 attention → 残差 → 第一 LayerNorm → FFN1 Dense → GELU → 第二 Dense → 残差 → 第二 LayerNorm；`software/kwt_reference.py` 的 `build_probe()` 在第一 LayerNorm 后取 `x`，在 FFN1 Dense 后、GELU 前取 `y_float`，形状分别为 99×64 与 99×256。探针分类输出与原模型比对，12 层第一 Dense 的 24 个核/偏置张量与 checkpoint 逐元素核对，且 `x @ w + b` 与 `y_float` 比对。已运行的真实权重零音频冒烟记录位于 `runs/reference_smoke/zero_audio_verified/manifest.json`。这支持当前**样本的层提取与权重恢复**，不代表音频样本来自规定验证划分。
- `software/ffn1_numeric.py` 对当前原型的舍入、饱和、累加顺序与二补数范围有明确且一致的定义；正常位宽下的 `int64` 中间结果有 `FixedPointSpec.validate()` 的范围保护。`software/precision/study.py` 与 `software/evaluate_layers.py` 使用的逐层统计式 `sqrt(SSE/N) / max(sqrt(reference_square_sum/N), 1e-8)` 与官方本科 12 层最大 NRMSE 公式一致。
- `software/pack_tensors.py` 的 `w[k,column]`、行优先顺序与 16 位低字在前的打包、解包互逆，现有单元测试覆盖负数、32/48 位和偏置广播。这是**原型存储格式**，仍待硬件同学确定总线/地址格式。

## 需处理的具体风险

### P1：无 `.git` 的稀疏源码目录未在每次运行时全面验明固定提交

**证据：** `software/kwt_reference.py` 的 `PINNED_BLOBS` 只有 `transformer_utils.py`、`kws_transformer.py`、flags 和两个 checkpoint 文件；`check_checkout()` 仅对这 5 个文件核哈希，且仅在目录有 `.git` 时检查 HEAD。当前 `third_party/kwt_pinned_sparse` 没有 `.git`。实际前向推理还导入 `kws_streaming/layers/speech_features.py`、`magnitude_rdft_mel.py`、`dct.py`、`normalizer.py` 等文件。若这些依赖在获取后被误改，检查仍会通过，导出清单仍会写固定的 `upstream_commit`。`work/fetch_kwt_sparse.py` 已在**下载时**对每个 blob 验证，但提取器在**每次运行时**没有保持这一保证。即使有 `.git`，HEAD 相同也不能排除未提交的源码修改。

**影响：** 改动后的预处理或层行为可能生成偏离指定模型的参考数据，探针与“原模型”的自洽比对仍可能通过。

**建议：** 为实际运行所需的全部上游源码建立固定提交 blob 哈希清单，提取前逐文件重算校验；对于完整 Git checkout，额外拒绝关键依赖的工作树修改。清单版本/摘要写入导出 manifest。至少先覆盖已下载的全部 `.py` 文件，不仅两份 Transformer 定义。

### P1：现有示例 Q16.8 原型在真实权重的合成零音频冒烟中已出现大于 3% 的层误差

**证据：** `runs/precision/synthetic_zero_study.json` 中 `existing_prototype_q16_8` 的第 06 层 NRMSE 为 `0.0378561217`（约 3.786%），第 05 层为 `0.0301901669`；全部记录的饱和计数为 0。报告的 `sample_directories=1`，输入是合成全零波形，非 Speech Commands 验证样本。

**影响：** 这不是比赛成绩，也无法推出真实验证集一定超标；但已经说明“零饱和”和“16 位输入/权重”不能保证 3% 要求，默认 Q16.8 不适合未经验证就交给 RTL 冻结。误差很可能主要来自量化步长，而非溢出；这一归因只是由饱和计数为 0 得到的推断，应以更多样本分析确认。

**建议：** 使用合法训练划分做无梯度标定、验证划分选型，先在 12 层真实音频样本上扫描小数位/各层或每通道尺度，再和硬件面积/存储成本一起确定格式。任何格式冻结前都要跑完整 12 层与逐任务检查。

### P2：只有逐层汇总误差，没有官方性能抽测所要求的逐任务误差检查

**证据：** `software/precision/study.py` 的 `evaluate()` 按层累计所有样本的 SSE 与参考平方和，最后取 12 层最大值；`software/evaluate_layers.py` 同理。官方指南第 10–11 页另规定：性能测试抽取的 12 次 FFN1 任务须**每一次单独**满足 3% 门槛。汇总值小于 3% 不蕴含每次任务均小于 3%。

**影响：** 使用当前报告作为全部精度验收会遗漏单次任务失败；12 次性能任务及其耗时/写回也无法由合并后的误差反推。

**建议：** 增加 `(sample_id, layer)` 每次任务的 NRMSE 与布尔门槛记录，和现有逐层汇总表分开；在真实抽测任务确定前，可先报告本地样本的最坏单次误差，不能称其为最终抽测结果。

### P2：单任务打包工具信任任意 `y_float`，可报告虚假的零误差

**证据：** `software/pack_tensors.py` 的 `create_task_pack()` 在 NPZ 含 `y_float` 时直接将其作为 `reference`，仅检查其形状及 `normalized_rmse()` 的有限值；没有像 `software/evaluate_layers.py` 与 `software/precision/study.py` 一样验证 `y_float ≈ x @ w + b`。例如 `x=[[0.25]]、w=[[1.0]]、b=[0]`，采用零小数位格式时定点输出为 0；若错误地写入 `y_float=[[0.0]]`，打包清单会给出 NRMSE 0%，而真实浮点结果应为 0.25。

**影响：** 单任务示例或交给硬件的验收包可能带着错误浮点参考，且打包输出的误差数字看上去完全合格。

**建议：** 在打包前调用与 12 层评估相同的浮点参考一致性校验；同时保存 `max_abs_numpy_vs_dense` 或明确标记未验证来源。

### P2：音频加载入口与指定上游数据管线尚未完全对齐

**证据：** `software/kwt_reference.py` 的 WAV 入口只接受恰好 16000 帧的 mono PCM16，并自行按 32768 转浮点；固定上游 `kws_streaming/data/input_data.py` 使用 `tf.audio.decode_wav(... desired_samples=16000)`，对短/长音频按此参数补齐/截断，还负责官方数据划分与标签类别的选择。当前 `.npy` 入口由调用者自行生成，未附带从数据集文件名到上游划分与原始 WAV 的复核链。两者对**已接受的 16000 帧 PCM16**应一致，但目前没有对整套官方样本入口的验证。

**影响：** 非恰好 16000 帧、但上游能够处理的合法数据会被拒绝；若外部预处理不同，同一 WAV 的导出 `x` 也可能与指定管线不一致。不能仅靠给一个文件打“validation”标签证明它按上游规则进入验证集。

**建议：** 构建数据集清单时调用或复现上游 `which_set`/标签映射；用上游 `decode_wav(desired_samples)` 与当前加载器对普通、边界长度 WAV 做逐样本对比。将原始 WAV 相对路径、哈希、来源划分与转换脚本版本写入导出 manifest。

## 与进行中的来源门禁修复衔接

审查时 `software/precision/study.py` 和 `software/evaluate_layers.py` 的 `local_3_percent_screen` 只要求每个目录有 12 层 NPZ，尚不要求原始样本确属允许的验证划分。因此一个自造的 12 层目录也可能得到 `true`。此问题已报告主任务，由来源门禁工作同步修改两处统计器；合并后请确认合成和无 manifest 的样本只能显示冒烟数值、不能给“3% 验证通过”。

## 审查边界

- 没有真实 Speech Commands V2 验证集；不能判断最终 3% 能否达成。
- 没有硬件 RTL 或协议冻结文件；不能声称软件与 RTL 已逐位一致，也不能审核实际吞吐/面积/功耗。
- 已有全零波形冒烟证明指定权重可运行及软件链路基本通畅，不能替代官方样本覆盖。
