# hand_2x2 单 PE 原始轨迹：软件侧第一轮逐事件对拍

日期：2026-10-19。此报告记录一次已执行的核验；不代表正式 19 列轨迹合同、阵列或 SoC 验收。

## 固定证据与来源

- 硬件证据：[资料包](https://github.com/xgyyy21/KWT1-Accelerator/tree/13a924ca77be7016e61d87cc83981752838cf8e2/handoff/fp32_hand_2x2_pe_material_2026-10-19)，提交 `13a924ca77be7016e61d87cc83981752838cf8e2`。
- 软件工作区：`software` 分支，HEAD `d11d169ea6f7b8500d6a2186c803d0f1a5eba709`；核验前工作区干净。
- 硬件原始轨迹：`replay/pe_trace_raw.csv`，18 列、12 条记录；证据包 `SHA256SUMS.txt` 给出的 SHA-256 为 `01e8c7fd1d96f4f1b7e5455171ed87be7936580bd02b228fea7b95361dba3169`。从 GitHub 已登录页面读取原始文本并恢复其 CRLF 换行后，本地副本哈希与该值一致。未改动仓库中的原始文件。
- 软件黄金轨迹：`software/examples/fp32_hand_image/expected_traces.json`，本地 SHA-256 为 `a85bb5b7d334841acab94740290933bd3a991b881acf8782615cb8c43f73553b`。
- 已阅读证据包 README、`SHA256SUMS.txt`、`pe_hand_2x2.f`、仿真日志、testbench 和 PE RTL 的相关事件生成代码。证据包中的 `rtl/fp32_math_pkg.sv` 清单哈希 `f9b2ff813b51aba48914ce181c3840d40bd3bbd4f5b2ad0c89a3f4acadb888fe` 与本地缓存的同一源码内容哈希一致。PE RTL 与 testbench 的清单哈希只在 GitHub 清单中读取，未另行下载并计算。

## 实际执行

使用临时只读脚本 `C:\Users\Lenovo\Documents\Codex\_kwt1_temp\compare_pe_raw_once.py`，读取哈希匹配的 CSV、本软件提交的黄金轨迹及 `software.fp32_reference.multiply_bits/add_bits`，按 `(row, column, event, trace_k)` 对齐事件。脚本和 JSON 运行结果放在仓库外的 `C:\Users\Lenovo\Documents\Codex\_kwt1_temp\`，未修改生产参考模型或正式轨迹协议。

执行命令：

```powershell
& 'C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' 'C:\Users\Lenovo\Documents\Codex\_kwt1_temp\compare_pe_raw_once.py'
& 'C:\Users\Lenovo\.cache\codex-runtimes\codex-primary-runtime\dependencies\python\python.exe' -m unittest software.tests.test_compare_pe_trace software.tests.test_fp32_reference
```

第一条命令退出码 0；第二条运行 19 项测试，全部通过。比较结果：

| 检查范围 | 实际结果 |
| --- | --- |
| 事件数量与身份 | 4 个输出单元、8 个 MAC、4 个 bias；12/12 身份匹配，无缺失或重复；44 个身份字段检查通过 |
| 软件黄金位模式 | X、W、乘积、累加前后值、bias、结果中适用的 56 个 FP32 原始位模式字段全部匹配 |
| 从轨迹实际输入独立重算 | 独立乘法、加法与累加关系共 36 个中间结果检查通过；未使用 FMA |
| 首个不一致项 | 无 |

testbench 中的 DUT 是 `fp32_pe_mac`，并非软件生成轨迹的适配器。它对四个输出单元依次送入 K=0、1 的 X/W，在 `@(posedge clk); #1` 后读取 DUT 的 `trace_valid`、`trace_bias_valid` 及数值端口；原始 CSV 的 `capture_kind=rtl_model_raw` 是 testbench 写入的固定标签。PE RTL 将输入乘法交给 `fp32_mul`，待独立的累加加法完成后输出 MAC trace，最终再输出 bias trace。硬件仿真日志含 8 条 MAC、4 条 bias 和 `fp32_pe_hand_2x2_tb PASS cells=4 mac_events=8 bias_events=4`。交接文件给出了 Icarus Verilog 复现命令，但未随包保存可独立核对的工具版本输出。本轮**读取了该日志，没有独立重跑硬件仿真**。

## 结论与边界

本轮软件独立复核通过：这份真实 testbench 从单 PE RTL 端口采样的 **K=2、2×2 hand_2x2 原始轨迹**，在已核验的事件身份和 FP32 数值字段上，与软件候选参考逐位一致。CSV 为原始 18 列，不能直接送入现有严格的 19 列比较器，也不能把 `rtl_model_raw` 改称已正式交付的 `rtl_measured`。本轮未验证乘法 8 拍、加法 4 拍的精确周期合同，未验证 K=32 跨块 SRAM 保存/恢复、8×16 阵列、DMA、SoC 或特殊值规则。后续仍需双方确认正式轨迹字段映射、有效信号时序及更多用例。
