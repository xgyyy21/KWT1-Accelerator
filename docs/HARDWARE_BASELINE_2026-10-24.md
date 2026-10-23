# KWT-1 硬件固定基线（2026-10-24）

## 固定内容

- 顶层：`rtl/fp32_accelerator_top.sv`
- RTL 文件列表：`rtl/files.f`
- 竞赛整层 testbench：`tb/fp32_competition_ffn1_tb.sv`
- 源码哈希清单：`docs/evidence/real_ffn1_layer00_source_manifest.json`
- 分支：`hardware`

本次导入的是 2026-10-23 真实 KWT-1 layer00 FFN1 仿真所用的源快照，而不是旧的整数阵列基线。真实归档包位于开发机 `D:\competition\handoff\real_ffn1_layer00_rtl_2026-10-23.zip`，SHA-256：

`86238127a80a2f1726d9968698c57a676dd065f9419dd69988dfe07cfdd4db20`

## 已有证据

- Icarus/vvp 进程退出码均为 0。
- 真实 layer00：`99×64 × 64×256`，25,344/25,344 输出逐位匹配，50,688/50,688 写回半字匹配。
- 208 个 tile、每 tile 2 个 K 块，末尾 3 行尾块已覆盖。
- 软件侧独立核验的是归档证据和参考重算；软件没有重新运行完整 RTL。

## 本次仓库验证

导入后应至少执行：

```powershell
iverilog -g2012 -s fp32_competition_ffn1_tb -o build/fp32_competition_ffn1.vvp -f rtl/files.f tb/fp32_competition_ffn1_tb.sv
vvp build/fp32_competition_ffn1.vvp +X_FILE=<x.mem> +W_FILE=<w.mem> +BIAS_FILE=<bias.mem> +EXPECTED_FILE=<expected.mem> +OUT_DIR=<new-output-dir>
```

上面的命令只在提供真实输入文件后才是完整整层复现；没有实际运行的结果不能写成 PASS。当前固定基线仍不包括真实 E203 NICE 包装、SoC 物理地址窗口、SRAM 宏时序和综合 PPA。

## 下一步

1. 由平台负责人确认 NICE 指令映射、System Bus/ICB 端口、物理地址和 fence 规则。
2. 完成 E203 wrapper 与 SoC SRAM 适配，并用同一份输入做平台级回归。
3. 用真实第 1 层及后续层参数做连续任务，检查状态清理和结果可见性。
4. 将本固定版本交综合侧做可综合性、面积和 150 MHz 探索性评估。
