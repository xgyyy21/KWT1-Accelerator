# FP32 SRAM baseline before PE arithmetic pipelining

固定日期：2026-10-29。分支：`hardware`。本目录是进入 PE 算术内部流水化试验前的硬件基线。

## 从哪里开始

- 软件同学：[SOFTWARE.md](SOFTWARE.md)
- 综合同学：[SYNTHESIS.md](SYNTHESIS.md)
- 本次源码清单：[published_source_manifest.csv](published_source_manifest.csv)
- 本次解包证据清单：[published_evidence_manifest.csv](published_evidence_manifest.csv)
- Git 导出来源：[publication_provenance.json](publication_provenance.json)
- 原本机资料包版本：[original_package_metadata/VERSION.json](original_package_metadata/VERSION.json)
- [导入后的实际核查](publication_checks/README.md)
- [历史真实模型 layer00](../real_ffn1_layer00_rtl_2026-10-23/README.md) 与 [10月22日来源补全](../hardware_history_2026-10-22/README.md)：本轮补传的历史证据，不是新仿真；Git 版本完整性清单为各自的 `github_export_manifest.csv`，省略项见 `github_export_omissions.json`。

版本以包含本目录的 Git 提交固定。源清单绑定的是仓库根目录的 `rtl/`、`tb/`、`scripts/`，保留原始字节，不改编码。主 RTL 与双完整矩阵实际编译快照一致；本轮没有把 FP32 算术改为真正内部流水。

本次先读取 GitHub 实时 `hardware=0b04a55f8902f5969077fb376423b7c31853b9a3`，与本地 checkpoint 提交 `a4e810d17fa9187ade80bbcd65843346fd89f2b3` 合并。保留了远程真实模型整层 TB 的输入文件、输出/写回/tile 检查和进度日志。随后导入已本地验证的 SRAM 路径、valid 时钟使能优化、针对性 TB 及证据；没有修改 `main`。

## 已有结果及范围

| 内容 | 证据和状态 |
|---|---|
| 两完整形状连续任务 | 非均匀合成输入，不复位/不清 SRAM；31,680 输出、63,360 半字写回匹配；260 tile；Verilator 编译/运行退出码 0 |
| 16-bit SRAM、控制与异常 | 五组针对性测试通过，失败 0；Icarus 编译/运行退出码 0 |
| 软件参考复算 | 固定 `fp32_reference.py` 对归档双任务结果核验通过；不等于软件侧独立重跑 RTL |
| 宏模式综合前端 lint | Verilator 定义 SYNTHESIS、USE_SRAM_MACROS=1，退出码 1；110 warning，不能标为综合 PASS |
| 总线超时 | 独立 `rtl/prototype/fp32_bus_fault_guard.sv` 原型通过；未接入主顶层 |
| 真实平台/物理时序 | 未集成 E203，未使用厂商 SRAM 时序模型，无目标库 STA/正式 PPA |

两个矩阵是独立任务：第二个任务重新装载不同 X/W/bias，**不是完整 FFN 推理的上下层数据连接**。本轮新增证据尚未获得软件侧独立签收，历史单 PE 或真实 layer00 验收范围不自动扩展到当前版本。

## 归档路径

- `evidence/sram_two_layers_verilator_2026-10-29_v1/`：实际运行日志、命令、工具版本、输入、输出、写回、tile 与控制轨迹，以及当时编译源码。
- `evidence/sram_two_layers_reference_check_2026-10-29_v1/`：软件参考复算结果、固定参考模型/检查器和哈希。
- `evidence/sram_exceptions_verified_2026-10-29_v2/`：五组测试日志、退出码、命令、异常真实轨迹和源码。
- `evidence/sram_macro_mode_lint_2026-10-29_v1/`：宏模式 lint 命令、版本、完整 warning 与退出码。
- `constraints/fp32_sram_exploratory.sdc`：150 MHz 探索时钟，缺少平台 IO 和 SRAM 库条件，不是 signoff 约束。

为遵守仓库忽略规则，未上传本机 `.tools/`、`.vvp`、Verilator `obj_dir`、可执行文件或两个约 49 MiB 的 ZIP。证据源目录的 `build/` 在此映射为 `evidence/`，所有未上传构建产物及其原始哈希详列于 [excluded_generated_files.json](excluded_generated_files.json)。原 `evidence_sha256.csv` 保留不修改，它会列出本机完整档案中的这些被省略文件；Git 交付完整性以 `published_evidence_manifest.csv` 为准，不可把缺少的二进制误报为本轮 Git 包损坏。

主办方 11 页 SRAM 图片保留在本机，Git 只发布整理文档及 `sram_manual_local_fingerprints.json`。不上传工艺库、宏模型许可证、完整数据集、模型权重或凭据。

原交接说明与原资料包 manifest 保存在 `docs/`、`original_package_metadata/`，其中本机目录和“未提交”描述是生成当时状态。当前 Git 路径与版本以本 README 为准，历史文件没有重写成新仿真记录。已归档仿真日志第二任务仍有 `PROGRESS SRAM FFN1` 固定显示标签，以 `JOB PASS id=1 M=99 K=256 N=64` 和实际 CSV 为准。

## 后续 PE 改动原则

先从本次固定提交新建试验分支；不直接覆盖基线。保持数值合同、非融合乘加顺序及 8+4 拍接口合同，真正切分算术而非仅延迟最终结果。修改后依次验证独立乘法/加法、PE、阵列和完整任务，并请综合侧用一致版本重新评估；是否满足 150 MHz 仍由目标工艺库 STA 判定。
