# KWT-1 硬件侧增量材料包

日期：2026-10-22

本包在此前交付材料基础上，补齐软件侧增量验收报告指出的四项来源/复现证据。原始报告位于 `request/`；旧验收材料和原始证据保留在 `evidence/`，未用新结果覆盖旧文件。

## 新增内容：四项来源证据

1. **非均匀 FFN1 实际仿真的进程退出码**：见 `evidence/provenance/nonuniform_rerun/`。其中保存重新运行命令、运行日志、进程完成记录、输入/二进制指纹和重新对拍结果。它用于补齐此前只保存 `$finish`/PASS 文本、未保存启动进程退出码的缺口。此项只在进程结束并完成对拍后标为通过。
2. **全 1 FFN1 的可复现编译产物**：见 `evidence/provenance/full_one_recompile/`。所附 `.vvp` 是从本包内全 1 RTL/TB 源码快照重新编译所得，另附编译命令、工具版本、退出码、日志、源清单和哈希。原历史 `.vvp` 的哈希与重编译产物不同，因此本包不声称二进制逐字节相同；提供的是基于固定源码快照可重建的依据。
3. **回归原始 manifest**：见 `evidence/provenance/regression_manifest/`。补入遗漏的 `ffn1_prerequisites_2026-10-21_v2/SHA256SUMS.txt` 原件副本及关联记录，并核实 manifest 与 summary 的 SHA-256 均与 `affected_regression_link.json` 一致。完整回归证据仍在 `evidence/` 下。
4. **PE 轨迹真实 RTL 来源**：见 `evidence/provenance/pe_trace_provenance.json`。四组实际 CSV 分别绑定到原回归中的编译/仿真/比较命令、日志、对拍报告以及 RTL/TB 源码哈希；合计 13,531 个事件。旧轨迹与新轨迹数值相同、来源标签不同本身不是证据；本文件补充的是归档执行记录和源指纹。没有记录到对应 Git commit，因此按哈希识别的源码快照描述，不虚称某个提交生成了轨迹。

## 既有验证材料与结论边界

- `evidence/ffn1_full_layer_2026-10-21/`：全 1 FFN1 完整输出、写回、输入、来源和检查记录。
- `evidence/ffn1_full_layer_varied_2026-10-22/`：非均匀有限 FP32 输入的整层输出/写回及软件参考逐位检查，25,344 个输出、50,688 个写回半字。
- 四组 PE 轨迹：合计 13,531 个事件；软件侧报告的独立数值核验通过是软件侧复核结论。本包的归档 RTL 仿真证据不等同于软件同学重新运行 RTL。
- 128 PE checkpoint、K=256 以及受影响回归材料照旧保留；checkpoint 是 RTL/TB 中的存储行为模型，不等同于真实 SRAM 或 SoC 接入。

本包不宣称 E203/NICE/System Bus 接入、真实模型权重推理、完整平台验证或正式 PPA 已完成。软件报告指出的这些事项仍需后续平台与模型条件具备后推进。

## 完整性

包内 `SHA256SUMS.txt` 是本包文件校验清单，`archive_manifest.json` 记录归档清单。生成 ZIP 后另在交付说明中给出 ZIP 本身 SHA-256。请解压后先核验文件清单，再使用各子目录 README 中的复现说明。

本包尚未提交或推送到 GitHub。
