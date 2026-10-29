# 完整 FFN1：全 +1.0 输入的真实 RTL 验证

本包固定 2026-10-21 的实际源码与仿真证据。旧 Git 基线为 `a4e810d`，本轮有未提交 RTL/TB 修改，不能仅检出旧提交复现；请使用本包的 `sources/` 及 `source_manifest.json`。本轮未提交、未推送。

## 结果

`99×64 × 64×256 + bias` 全尺寸任务实际运行完毕，Icarus 退出码 0：208 个 tile、25,344 个实际输出、50,688 次唯一半字写回全部检查通过；最后 3 行的尾块通过。所有输入/权重/bias 均为 FP32 +1.0，输出均为 65.0（`0x42820000`）。

固定软件参考模型本地复算并逐项核对：25,344/25,344 位级匹配。软件负责人独立验收尚未进行。

## 可直接交给软件侧

- `ffn1_output.csv`：25,344 行最终实际存储结果，字段为 `row,column,word_address,result_bits,expected_bits,match`。
- `ffn1_writeback.csv`：50,688 行实际总线写握手，字段为 `cycle,tile_id,row,column,word_address,half,actual_word`；`half=0` 为低字，`half=1` 为高字。
- `ffn1_tiles.csv`：208 行实际 tile 启动描述及周期。
- `ffn1_x.mem`、`ffn1_w.mem`、`ffn1_bias.mem`：本次仿真实际初始化的输入，低 16 位字优先、内部半字地址。
- `ffn1.compile.log`、`ffn1.run.log`：原始编译与完整实际运行日志。原始 PowerShell 重定向日志为 UTF-16；读取时应识别 BOM。
- `process_completion.json`：对真实 vvp 进程的退出码和 CPU/实际耗时观测。实际耗时 1,531.06 秒，CPU 1,447.48 秒。
- `resource_samples.jsonl`：运行后半段每约 15 秒的资源/进度采样；不是从启动起的完整资源曲线。完整 tile 进度在 `ffn1.run.log` 中。
- `sources/`、`source_manifest.json`：精确 RTL/TB 快照及指纹；`tool_version.log` 为工具版本。
- `software_reference/fp32_reference.py`：来自软件 `d11d169ea6f7b8500d6a2186c803d0f1a5eba709` 的归档参考模型；`software_expected_output.csv` 为该模型生成的期望值，不能当作 RTL 实测值。
- `summary.json`：全量 CSV、软件参考与 DONE/写回检查结果。
- `affected_regression_link.json`：本轮受影响 20 项回归及源码哈希关联，回归材料在相邻 `ffn1_prerequisites_2026-10-21_v2/`。
- `imported_run_provenance.json`：原始命令、编译产物指纹和证据导入说明；收集脚本没有假装重新执行原始仿真。
- `SHA256SUMS.txt`：本包全部文件指纹，清单自身除外。

结果 CSV 的 cycle 来自 TB 的 `progress_cycle`。最后写握手为 2,587,777，DONE 观测为 2,587,779。日志中的 `cycles=2587777` 是 START 寄存器写任务返回后的等待循环计数，与 progress_cycle 的起点不同；本包不将该数字包装成正式 SoC 周期或吞吐量。

## 从固定源码重跑

从本包目录执行，输出必须为尚不存在的新目录；需 Python 3.10+ 和 Icarus Verilog（本机为 14.0 devel）：

```powershell
& 'C:\Program Files\Lenovo\ModelMgr\Plugins\Image\python.exe' -B Replay.py --replay --output D:/competition/build/ffn1_replay_new --iverilog D:/competition/.tools/iverilog/bin/iverilog.exe --vvp D:/competition/.tools/iverilog/bin/vvp.exe
```

脚本首先验证归档哈希，然后从本包 `sources/` 重新编译、运行全部 208 个 tile，再核对 CSV 与固定软件模型。不会提交或推送，不覆盖本包。完整重跑仍约需数十分钟，实际耗时取决于机器。

也可从 `sources/` 手动执行：

```powershell
iverilog -g2012 -s fp32_competition_ffn1_tb -o <existing-build-directory>/ffn1.vvp -f rtl/files.f tb/fp32_competition_ffn1_tb.sv
vvp -i <existing-build-directory>/ffn1.vvp +OUT_DIR=<existing-output-directory>
```

## 验证边界

本例不证明不同数值/真实模型权重的整层功能、完整 FFN2、十二层参数切换、E203 NICE/System Bus 平台协议、CPU Cache 可见性、平台 SRAM 宏、正式故障恢复或物理 PPA。全 1 输入无法充分揭露输入行列交换；后续应添加位置相关的非同值整层测试。

FP32 算术仍为组合函数加延迟寄存器；8+4 拍功能延迟不等于完成了物理切分和 150 MHz 时序。`$fatal` 不可综合和 Icarus `always_*` 敏感列表提示保留在编译日志中，不据此宣称综合通过。
