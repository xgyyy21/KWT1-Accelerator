# 单 PE 专项验证包（2026-10-20）

本包为真实 `fp32_pe_mac` 的功能仿真材料。结果以 `replay/run_report.json` 和同次运行日志为准；生成前的说明不构成 PASS。未提交、未推送，不提供虚构的 GitHub 链接。

## 范围和文件

- `hand_2x2`：用新的 K=32 容量测试框架重跑旧 K=2 算例，作为检查测试框架的基线。
- `rounding_nonfused`：实际运行软件提供的非融合舍入用例。乘法和加法分别舍入应得正零，而融合第二次 MAC 会留下非零负数。
- `k32_boundary`：实际容量 K=32 的同一 PE，执行总 K=64 的两个块。第一块末尾保留 +2，第二块先加 -3，再于全部乘加结束后加一次 +0.25，应得 -0.75。第一个块完成后等待 9 拍，不复位、不清零，记录部分和稳定性。
- `finite_boundaries_hardware_added`：硬件侧新增的有限值边界输入，由固定软件参考生成黄金；不冒称为软件已经确认的新向量。包含正负零、次正规数、最小正规数附近的乘法、累加、bias 和抵消。
- `fp32_boundary_vectors.txt`：固定软件整数参考生成的有限且不溢出加法/乘法输入与黄金，含定向和固定种子随机样本。覆盖统计见 `boundary_vector_coverage.json`，不是全 FP32 穷尽证明。

每个 PE 用例位于 `replay/<case_id>/`，包含正式 19 列 `pe_trace.csv`、`signal_trace.csv`、`simulation.log`、`compile.log`、软件原版比较报告、实际输入校验和 `timing_and_boundary_report.json`。跨块报告明确区分 DUT 的块内 k 与导出的全局 k。

`sources/`、`filelist.f`、`provenance.json` 固定实际编译源码及哈希；`replay/commands.json` 和工具版本文件记录实际运行环境。`inputs/` 保留固定软件提交的原始文件；新增硬件边界向量单独放在 `boundary_inputs/`，采用自己的 manifest 和黄金 JSON 哈希，不能混用软件原始两份文件的哈希。

软件来源固定为 `d11d169ea6f7b8500d6a2186c803d0f1a5eba709`。对原有三组向量，manifest SHA-256 为 `148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93`；黄金 JSON 为 `a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b`。新增向量哈希见 `cases.json` 和实际 CSV，不冒充双方旧约定文件。

## 周期、结构和验收边界

采样为上升沿后 #1 ns、非阻塞赋值完成之后；解除复位后首上升沿为 cycle=1。每个可执行仿真只复位一次，各逻辑输出之间不复位 cycle。乘法接受到缓冲写入检查 8 拍，加法发起到累加提交检查 4 拍；两级之间还存在调度等待，不能推断每个输入固定 12 拍后输出。

`trace_valid` 表示 MAC 提交，`trace_bias_valid` 表示最终 bias 提交；后者与 `result_valid/done` 同沿。以有效信号写正式事件；周期级信号另存辅助 CSV。输入有 valid 空泡，K=64 的块间等待包含 9 拍 enable=0；不将这称为任意阶段全流水停使能验证。

新增 TB 中 `BLOCK_K=32`。逻辑全局 `k=实际块编号*32+trace_k`，`tile_id=k//32`；bias 属于最后块。脚本同时检查块内 k 次序、实际驱动的块编号、接受/乘法/加法次数和跨块连续性，不是仅给连续 64 项贴标签。

这次证明的是 PE 累加寄存器跨块保持，不是 SRAM 保存/读回/恢复。单个物理 PE 依次计算多个逻辑输出，不是阵列并行运算。尚未覆盖数组、整层、E203 或真实平台接入、综合时序面积功耗。8/4 拍的延迟寄存器行为也不证明组合浮点算术已拆成物理时序合格的流水级。

有限且各步不溢出的 binary32 范围内采用 RNE、非融合、K 升序、正零初始化、bias 一次、逐渐下溢、正负零逐位区分。NaN/Inf/溢出不在目前双方合同内。边界样本通过不等于所有有限 FP32 输入都已验证。软件原版比较器保留 `BIT-EXACT-CANDIDATE` 名称，本地通过不替代软件负责人独立验收。

`prior_contract.md` 原样保存上一轮 K=2 的历史合同说明；本包扩展范围和新增输入身份以本说明和 `cases.json` 为准，不将旧合同里的“K=2 本轮范围”误用于新测试。

## 复现

需要 Python 3.10+、Icarus Verilog，无需 NumPy、不依赖网络。从本目录执行，工具路径按环境替换，输出目录须尚不存在：

```powershell
python -B .\Replay-Special.py --replay --output D:\your_work\pe_special_replay_new `
  --iverilog C:\your_tools\iverilog.exe --vvp C:\your_tools\vvp.exe
```

先校验包内 `SHA256SUMS.txt`，再编译、仿真、显式启用 `--compare-tile-id` 的逐事件比较和周期/跨块检查。复现输出保存在新目录，不覆盖原交付证据。软件额外输入是硬件新增黄金，仍需双方独立确认。包内原始 `.mem/.bin` 和源码应按原始字节保留，后续 Git 导入须验证行尾转换不会改变哈希。
