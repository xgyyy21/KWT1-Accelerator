# KWT-1 真实模型 layer 00 FFN1：RTL 仿真证据

日期：2026-10-23（Asia/Shanghai）。

## 本次任务与当前结果

本目录保存真实 KWT-1 第 0 层 FFN1 的一次硬件仿真：
`X[99,64] × W[64,256] + bias[256] → Y[99,256]`。

本次实际结果已经完成：Icarus/vvp 进程退出码为 0，独立 checker 退出码为 0；
`comparison_summary.json` 记录 25,344/25,344 个输出逐位匹配、50,688 个写回半字检查通过、
208 个 tile、每 tile 2 个 K 块、尾部 3 行处理正确。软件同学仍需独立复核，
因此这是一项硬件侧 PASS，不是双方联合验收完成。

本次不改动原 RTL/TB；从当前工程复制固定源码快照后，在快照内重新编译，
使用新生成的 `.vvp` 执行，不复用此前人造输入测试的输出。
项目根目录本次检查不属于 Git 工作区，因此源码版本由 `source_manifest.json`
记录的 SHA-256 标识，不虚构 Git 提交号。未执行 commit 或 push。

## 输入来源

- 原始交付包的逐字节副本：`software_input.zip`。
- 完整输入和软件说明：`inputs/`，保留原文件与原 `SHA256SUMS.txt`。
- 本轮入口及镜像一致性检查：`input_validation.json`。
- 固定软件参考：`software_reference/fp32_reference.py`，SHA-256 为
  `45daa2c620dcd512ffa2380141cf762477ea25846fc0328027827cfa3842fefb`。

软件交付使用真实预训练权重与一条音频的真实层输入。
本轮不重新运行 TensorFlow，也不重新核验上游 checkpoint；来源边界沿用原交付说明。
音频仍标为 `split=unverified`，不得声称是已核实的正式验证集样本。

## 入口核对结论

实际 TB：`sources/tb/fp32_competition_ffn1_tb.sv`。
顶层：`fp32_accelerator_top`，`STRICT_COMPETITION_SHAPES=1`。

| 参数 | 实际传入文件 | 数量 | TB 入口 |
| --- | --- | ---: | --- |
| `+X_FILE` | `inputs/x_fp32.mem` | 6,336 | 32 位数组，`$readmemh` |
| `+W_FILE` | `inputs/w_fp32.mem` | 16,384 | 32 位数组，`$readmemh` |
| `+BIAS_FILE` | `inputs/bias_fp32.mem` | 256 | 32 位数组，`$readmemh` |
| `+EXPECTED_FILE` | `inputs/expected_fp32.mem` | 25,344 | 32 位数组，仅用于核对 |

四份入口文本均须每行 8 位十六进制。不能将每行 4 位的 16 位 `.mem` 直接传给它们。
TB 的 `write_fp32` 随后把每个 FP32 元素拆为低半字、高半字，装入内部 16 位存储模型。
独立 checker 会把仿真实际保存的 `ffn1_x.mem / ffn1_w.mem / ffn1_bias.mem`
重新组合，并与软件原始 `.bin` 比较，防止悄悄使用默认全 1 数据。

内部示例基址：X=0，W=100000，bias=200000，Y=210000。
单位全部是 **16 位字地址**，窗口不重叠；不是字节地址，更不是真实 E203 物理地址。
W 按 `[k,j]` 行主序读取，不转置。

现有 TB 顶部保留了“默认全 1”说明与默认数组初始化；本轮实际参数覆盖它们。
是否确实装入真实数据，以 `commands.json` 和实际装载快照的逐位复核为准。

## 证据文件

- `source_manifest.json`、`sources/`：固定 RTL、TB、文件列表及源码哈希。
- `iverilog_version.log`、`vvp_version.log`：实际工具版本输出。
- `commands.json`：真实执行参数、工作目录、PID、时间、退出码与日志哈希。
- `simulation/compile.log`、`simulation/ffn1_real_layer00.vvp`：编译日志与实际运行产物。
- `simulation/ffn1.run.log`、`process_completion.json`：原生仿真日志、真实进程退出码。
- `simulation/ffn1_output.csv`：最终存储模型中读出的实际 FP32 输出。
- `simulation/ffn1_writeback.csv`：实际总线模型接受的写回事务，不是软件生成的期望轨迹。
- `simulation/ffn1_tiles.csv`：实际输出 tile 启动记录。
- `simulation/ffn1_x.mem / ffn1_w.mem / ffn1_bias.mem`：本轮实际装载的输入快照。
- `checker.log`、`comparison_summary.json`：独立核对结果及首个差异（如有）。
- `final_checker_recheck.json`：在归档材料生成前再次运行 checker 的退出码和日志指纹。
- `checker_unit_tests.log`：检查程序的合成数据单元测试，不属于 RTL 仿真 PASS。
- `SHA256SUMS.txt`：任务完成后生成的完整包内文件哈希清单，不包含清单自身。

Icarus 编译退出码为 0。编译日志包含重复的 `System task ($fatal) cannot be synthesized in an always_ff process` 警告，来自 `fp32_pe_mac.sv` 中用于仿真断言的 `$fatal`。这不影响本次功能仿真结果，但本轮并未进行综合，也不把编译成功误称为可综合性、面积或 PPA 通过。

## 独立检查范围

最终结果直接与软件原始 `inputs/expected.bin` 的 25,344 个位模式比较，
不把硬件 CSV 的 `match` 或 `expected_bits` 栏当成正确答案。
写回检查覆盖 50,688 个半字的地址、坐标、低高顺序、数据、唯一性和完整性，
并核对写回重组结果与最终存储读出一致。

另检查 208 个输出 tile、每个 tile 的两个 K 块描述、尾部 3 行、
642,048 次输入半字读统计，以及 DONE 晚于最后接受的写回事务。
这里只依据实际输出、写回、tile 描述和 TB 断言检查 K 分块行为，
不额外声称记录了全层逐 MAC 内部事件。

最后使用固定软件参考从 X/W/bias 重新计算 expected，
检查软件交付的期望镜像本身与双方约定的逐次舍入运算一致。
这是硬件侧本地复核，不等于软件同学独立重跑 RTL。

检查脚本的负例测试故意修改内存中的证据副本，确认能够拒绝错误输出、
重复坐标、缺失输出、缺失写回、错误地址、错误半字、错误尾行、缺少 K 块和过早 DONE；
不会改写真实仿真证据文件。

## 复核与复现

已有结果的独立复核（Python 仅需标准库）：

```powershell
& '<python.exe>' -B '<本目录>/Check-RealFfn1Layer00.py' `
  --package '<本目录>' --recompute-reference --negative-controls
```

在原工程中全新重跑（输出目录必须尚不存在）：

```powershell
& '<python.exe>' -B 'scripts/Run-RealFfn1Layer00.py' `
  --input-zip 'handoff/kwt1-real-ffn1-layer00-handoff-2026-10-23(1).zip' `
  --output '<全新结果目录>'
```

`Run-RealFfn1Layer00.py` 的包内副本用于记录本轮执行程序；
直接放在包根目录执行时，其工程根目录推导不适用，不应这样调用。
离开原工程复现时，使用 `sources/`、`inputs/`，参照 `commands.json`：
在 `sources/` 目录执行 `iverilog -g2012 -s fp32_competition_ffn1_tb -f rtl/files.f tb/fp32_competition_ffn1_tb.sv -o <新产物>`，
然后用 vvp 运行新产物，传入四个 32 位输入文件和一个全新的 `+OUT_DIR`。
路径可调整，但输入与源码文件的哈希必须相同；不要覆盖归档仿真输出。

## 未验证与等待确认

- 本轮是内部协议原型，不是真实 E203 NICE/System Bus 接入。
- DONE 检查仅指 TB 存储模型接受写回之后；不是 CPU 缓存可见性保证。
- 不是物理 SRAM 宏验证，不代表算术电路物理流水、150 MHz、面积或功耗达标。
- 不覆盖 FFN2、完整 12 层推理、多音频准确率和正式数据集精度。
- 软件同学对本轮新结果的独立验收：等待交付后复核。
