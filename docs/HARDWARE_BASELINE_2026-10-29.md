# 2026-10-29：PE 算术流水化试改前的基线

本次在实时远程 `hardware=0b04a55f8902f5969077fb376423b7c31853b9a3` 基础上，保留本地 `a4e810d17fa9187ade80bbcd65843346fd89f2b3` 的 checkpoint 证据，导入当前 SRAM 验证成果。主目录保持 `rtl/`、`tb/`、`scripts/`；不修改 `main`、`software`、`integration` 分支，不强制推送。

## 交接入口

- [本轮总说明](../handoff/sram_baseline_2026-10-29/README.md)
- [给软件同学](../handoff/sram_baseline_2026-10-29/SOFTWARE.md)
- [给综合同学](../handoff/sram_baseline_2026-10-29/SYNTHESIS.md)
- [源文件 SHA-256](../handoff/sram_baseline_2026-10-29/published_source_manifest.csv)
- [双完整任务结果](../handoff/sram_baseline_2026-10-29/evidence/sram_two_layers_reference_check_2026-10-29_v1/comparison_summary.json)
- [本次导入后核查](../handoff/sram_baseline_2026-10-29/publication_checks/README.md)
- [历史真实模型 layer00 材料](../handoff/real_ffn1_layer00_rtl_2026-10-23/README.md)
- [历史 10月22日来源补全](../handoff/hardware_history_2026-10-22/README.md)

原始资料包和工具环境仍在开发机，本次 Git 发布为去除生成二进制和模型/音频的解包证据。历史目录的旧“未提交”文字只反映当时状态；当前以本提交及各 `github_export_manifest.csv` 为准。

## 状态

已实现：FP32 主计算路径、DMA/控制原型、24组16-bit宏引脚路径；独立总线故障 guard 候选模块。

已仿真通过：两个完整矩阵连续任务，31,680输出、63,360半字写回；本次导入后又实际运行五组针对性回归，5通过/0失败。主 RTL 与原双完整任务仿真源码哈希一致，导入后只重算软件参考，未重复完整 RTL 仿真。

软件侧已独立核验：历史单PE、阵列、合成整层和真实layer00范围按各原始报告保留。本轮新SRAM连续任务材料尚未获独立签收。

等待确认：真实E203 NICE/System Bus、地址窗口/缓存可见性、目标工艺库和宏时序条件。

尚未实现：FP32算术内部真正分级流水、真实E203/SoC接入、故障guard接入顶层及完整DMA中止/排空、正式PPA。宏模式Verilator前端lint仍以110个warning退出1，不能称为综合PASS。综合同学报告K32单PE Yosys/ABC成功，不代表完整顶层或150MHz已通过。

后续可以从本基线创建独立PE试验分支。保留当前算术行为和可复现证据，待新乘法/加法流水及PE、阵列、整层回归完成，再比较综合/STA。本次不实施PE算术流水改写。
