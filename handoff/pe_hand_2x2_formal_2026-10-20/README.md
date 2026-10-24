# 发给软件同学：hand_2x2 正式 19 列单 PE 联调包

日期：2026-10-20。已按 2026-10-19 软件回复修正本轮合同范围，详见 `CONTRACT.md`。

## 交付文件

| 路径 | 用途 |
|---|---|
| `replay/pe_trace.csv` | 本轮真实 `fp32_pe_mac` 仿真产生的正式 19 列事件轨迹 |
| `replay/simulation.log` | 同一次运行的完整日志，含输入接受、乘法边界、加法发起和 MAC/bias 提交 |
| `replay/signal_trace.csv` | 周期级辅助信号记录，不是替代正式事件 CSV |
| `replay/compare_report.json`、`compare.log` | 软件原版比较器的结果，启用 `--compare-tile-id` |
| `replay/timing_report.json` | 采样对齐和 8/4 周期功能边界的独立检查 |
| `replay/input_validation.json` | 实际加载的 `.mem/.bin`、哈希及与黄金 manifest 的对应关系 |
| `inputs/` | Git 原始字节导出的软件输入、manifest、黄金 JSON 等；TB 实际只读取 x/w/bias 三个 `.mem` |
| `sources/rtl/`、`sources/tb/` | 实际编译使用的源码快照，不依赖本机后续修改 |
| `filelist.f` | 本次编译文件列表 |
| `provenance.json` | 硬件基线、dirty 状态、精确源码哈希、软件提交及黄金哈希 |
| `replay/commands.json` | 本次实际运行命令及工作目录 |
| `replay/iverilog_version.log`、`vvp_version.log`、`python_version.json` | 工具版本 |
| `replay/compile.log` | 编译输出，保留警告 |
| `replay/software_checker_tests.log` | 本轮实际执行的软件比较器、CSV 生成器、逐步轨迹生成器测试；未运行依赖 NumPy 的完整软件测试集 |
| `replay/negative_checker_report.json` | 对复制品人为破坏字段的比较器负向测试，不属于硬件实测证据 |
| `replay/run_report.json` | 本次范围、结果及尚未验证事项 |
| `historical_18col/` | 原硬件提交中的旧资料包，原样保留，不与本轮来源混用 |
| `software_snapshot/` | 固定软件提交原版比较工具及其必要依赖/测试/黄金文件 |
| `SHA256SUMS.txt` | 包内文件原始字节 SHA-256，不包含校验清单自身 |

## 复现

需要 Python 3.10+、Icarus Verilog；无需 NumPy，不需要重新联网下载。将整个目录拷贝后执行：

```powershell
python -B .\Replay.py --replay --output D:\your_work\pe_replay_new `
  --iverilog C:\your_tools\iverilog.exe --vvp C:\your_tools\vvp.exe
```

`--output` 必须是尚不存在的新目录，不覆盖原交付物。复跑先验证 `SHA256SUMS.txt`、输入哈希和源码哈希，再编译、仿真、对拍和检查时序。具体原始命令另见 `replay/commands.json`。

只做软件独立比较时，可在 `software_snapshot` 目录执行（路径可按环境调整）：

```powershell
python -B -m software.compare_pe_trace `
  --expected software/examples/fp32_hand_image/expected_pe_trace_demo.csv `
  --actual ../replay/pe_trace.csv --case-id hand_2x2 --compare-tile-id `
  --report ../../your_new_compare_report.json
```

## 通过范围与边界

- 正式轨迹目标为 19 列、8 个 MAC 事件、4 个 bias 事件。以本包实际生成的报告和日志为准，不把预期写作实测。
- 数值比较使用软件原版工具，保留其 `BIT-EXACT-CANDIDATE` 原始结果名称；软件负责人独立验收尚待完成。
- 只覆盖 K=2 单 PE。K=32 跨块、`rounding_nonfused` 专用用例、SRAM 部分和保存恢复、8x16 阵列和 SoC 均未纳入本轮交付结论。
- 合同已明确逐渐下溢和有符号零，但这组输入不能证明这些边界的完整覆盖。NaN、Inf、溢出在合同外。
- 8/4 拍是功能延迟边界证据，不是综合或 150 MHz 物理时序报告。
- 基线硬件提交后新增的正式 TB 尚未提交，因此 CSV 使用 `硬件基线+dirty`。确切源码见本包快照及 `provenance.json`，不能误称已提交新版本。
- 本包仅在本地生成，本次未 commit、push 或改动 main。不能把本地新文件链接冒充 GitHub 已发布链接。

下一步由软件同学独立核对本包；硬件再推进非融合舍入专用用例及 K=32 真正两块执行的证据。
