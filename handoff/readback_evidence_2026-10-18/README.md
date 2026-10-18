# 缓存读回交接证据包（2026-10-18）

本包只验证 `matrix_cache_manager` 局部读回，不验证 PE、DMA、SRAM 宏或 E203。

## 三份 CSV，不混淆版本

| 文件 | 含义 | 文件 SHA-256 |
|---|---|---|
| `previous_repository_word_readback.csv` | `acfae72` 原仓库 blob，LF，保留失败版本供审计 | `6d7de5bfb22f4b817921a47cc79982a23ef8a3d4c45f679d7d8344d76c463250` |
| `../word_readback.csv` | 软件已收到并复核的历史本地新版，原字节不改 | `d7ba2ee7ae5678552899008b292398df861a6da28d06fa13bfa28dd53e732a1b` |
| `replay/word_readback.csv` | 本轮以固定 Git 源码和输入重新仿真的新记录 | `d1ecc874018a5a1806646523bccc1f4a7687ccd2942aa121488a66daca5b9d56` |

旧仓库 blob 换成 CRLF 后为 `61adcaf0e057e060a945e5dca11c11746221950809013805988261674c46272b`，不是历史新版。旧版三个输入哈希错误真实存在；本轮不删改旧失败结论，也不宣称问题由软件换输入引起。

历史新版声明 `6e0bd88+dirty`、全 RTL/TB 指纹 `7c42767d...`。旧说明记录的方法是：将 `rtl/`、`tb/` 下 `.sv/.v/.f` 按相对路径排序，每项为 `<文件 SHA-256><两个空格><相对路径>`，以 LF 连接，对 UTF-8 内容做 SHA-256。**目前未恢复当时完整 dirty 源码集合，不能独立重算该指纹，也不能声称历史 CSV 已有完整复现证据。**当时两个实际编译文件的已记录哈希与本轮固定 Git blob 相同，但不证明整个工程快照相同。

## 固定来源与本轮快照

- RTL/testbench：`acfae7282f2d16f6fe8df476efed147f23df4b71`。
- 软件输入：`d11aa3d51e81f0f070f2014229032e0098851922` 的 `software/examples/fp32_hand_image/`。
- 提取方式：`git -c core.autocrlf=false archive COMMIT`，不使用 checkout 换行转换后的文件。
- 编译用源码只有 `sources/rtl/matrix_cache_manager.sv` 和 `sources/tb/word_readback_tb.sv`，filelist 为 `readback.f`。
- 两个源码的原始 SHA-256 分别是 `ad1db76b9df18621d31ae8aae11c9bc5ee30e7dd1baa2caaf7dd3cd4680f8838`、`d2e4dd150409a897e1140cd1f6ddc935972861c217e13ff3e0f1714e612bd382`。
- 本轮 `rtl_snapshot_sha256=9906d8936968464109ab5fc532c09f315f55da5877d34adabb12e57a28bb6042` **只覆盖实际编译的两份源码**：按包内 `sources/` 路径排序，`<小写文件SHA-256><两个空格><包内相对路径>`，LF 连接、无末尾 LF、UTF-8 无 BOM，再做 SHA-256。它与历史全工程指纹不是同一统计范围。

`provenance.json` 给出这次编译源码和输入的逐文件哈希。`fixed_commit_source_inventory.json` 列出固定 RTL 提交内全部 52 个 RTL/TB `.sv/.v/.f` 文件，供进一步审阅，但不冒充旧 dirty 快照。

## 输入资料

- `historical_inputs/`：原本机实际路径中的九组 `.bin/.mem` 原字节副本。
- `historical_input_inventory.json`：逐文件大小、SHA-256、固定软件来源路径，以及与 `d11aa3d` 的比较。
- `inputs/`：固定 `d11aa3d` blob 的九组 `.bin/.mem` 及 `manifest.json`，用于本轮复跑。九组 `.bin` 与历史原文件逐字节一致；`.mem` 只有原 CRLF 与固定 LF 的差异，16 位字内容一致。
- 固定软件 `manifest.json` 原始哈希：`148ac9b305c34dafd033ea33d98b4f0a13edbf1306c66d29c7926ed348941e93`。

因此其他机器不需要访问 `D:/competition/...`，可以直接使用包内文件复跑。

## 一键复跑

在仓库根目录运行，工具路径换成自己机器上 Icarus 的实际位置：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass `
  -File handoff/readback_evidence_2026-10-18/Replay-Readback.ps1 `
  -Iverilog 'D:/competition/.tools/iverilog/bin/iverilog.exe' `
  -Vvp 'D:/competition/.tools/iverilog/bin/vvp.exe'
```

默认写入仓库 `build/readback_replay/`，不覆盖包内历史记录；也可用 `-OutputDirectory` 指定新目录。脚本先检查输入/源码哈希及 `.bin/.mem` 字序，编译并仿真，再核对 144 个元素、9 组覆盖、读回值、低高字重组和一拍读延迟。

等价编译命令（工作目录必须为本包目录）：

```powershell
iverilog -g2012 -s word_readback_tb -o <输出目录>/word_readback_tb.vvp -f readback.f
```

完整 vvp 参数（包括九个实际输入哈希）见 `replay/run_report.json` 的 `simulation_arguments`；脚本从原文件自动计算参数，不手工抄哈希。

## 实际测试结果与日志

本轮在两个独立输出目录实际运行两次，均为：

```text
CACHE_READBACK_ONLY_PASS rows=144 groups=9
CSV_SHA256=d1ecc874018a5a1806646523bccc1f4a7687ccd2942aa121488a66daca5b9d56
```

`word_readback_tb` 日志写 `PASS rows=145`，该数值含表头；有效数据为 144 条。

- `replay/compile.log`：编译日志（空文件表示本次无诊断输出，退出码为 0）。
- `replay/simulation.log`：实际仿真日志。
- `replay/iverilog_version.log`、`replay/vvp_version.log`：Icarus 14.0 (devel) 完整版本输出。
- `replay/run_report.json`：本轮来源、命令参数、工具版本和 CSV 哈希。
- `historical_vs_replay.json`：144 行的 17 个非来源字段全部相同；路径、RTL revision、快照字段单独区分，不能据此证明旧源码身份。
- `SHA256SUMS.txt`：本包交付文件的原字节哈希（不含自身及生成的 `.vvp`）。

软件同学可以在固定软件分支工作区运行自己的严格检查器：

```powershell
python -m software.check_word_readback --csv <本证据包>/replay/word_readback.csv --image-dir software/examples/fp32_hand_image
```

**本机未运行软件 Python 检查器**：当前 Python 启动器不可用，不能写成 PASS。本机实跑的是 Icarus 和包内 PowerShell 的读回/来源检查；请软件侧从固定提交抽取后独立复核。
