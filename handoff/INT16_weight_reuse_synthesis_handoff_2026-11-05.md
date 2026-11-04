# INT16 layer00 权重 tile 复用：综合侧交接

日期：2026-11-05

## 固定版本

- 分支：`hardware`
- 本次提交：`c4e6eccda5995b0a27d7778caf555d77f1e51dde`
- 对照基线：`df45c9aa84b80fbb1b621fccea59b67bedd05cad`
- 本次提交是基线的直接后继，未改写或覆盖基线。

GitHub：

```text
https://github.com/xgyyy21/KWT1-Accelerator/tree/hardware
https://github.com/xgyyy21/KWT1-Accelerator/commit/c4e6eccda5995b0a27d7778caf555d77f1e51dde
```

## 本次改动

- `rtl/int16_accelerator_top.sv`：K=64 增加 64×16 INT16 权重 tile 缓存，按输出列 tile 装载一次并跨 M 行复用；K=256 保持原路径。
- `tb/int16_accelerator_top_tb.sv`：增加尾 tile、连续任务重新装载和总线错误导致缓存失效检查。
- `tb/int16_software_handoff_tb.sv`：增加 W/bias/Y 事务计数、命令响应计数和 layer00 事务断言。
- `handoff/evidence/int16_weight_reuse_2026-11-04/`：保存 12 层回归、layer00 对拍、adapter/PE 回归、日志和哈希清单。

## 功能证据

- 12 层 INT16 Golden：12/12 PASS，304,128 个输出逐位匹配。
- layer00：25,344 个输出匹配，12,672 次写回，71,808 条命令/响应。
- layer00 事务：W=8,192，bias=256，X=50,688，Y=12,672。
- 与原轨迹相比总 DMA 事务减少约 92.02%；该数字是事务数对比，不是正式平台周期加速结论。
- 本地使用 Icarus Verilog 14.0 devel；尚未完成目标 SRAM 宏、DC、STA、150 MHz 或功耗评估。

## 哈希清单

源码、输入文件哈希清单：

```text
handoff/evidence/int16_weight_reuse_2026-11-04/source_sha256.json
SHA-256: D048B7D0C91FE3B26EA8DDE7EED540A4EF2624A18A94707DF00D4D2DCF2363FF
```

仿真证据哈希清单：

```text
handoff/evidence/int16_weight_reuse_2026-11-04/evidence_sha256.json
SHA-256: 65B7DCEDF6A2968CD4581270457964FBE05FB00371381D57348517CF734CE43E
```

证据目录中的 `.simv/.vvp` 仿真二进制未提交。输入 ZIP 的 SHA-256 为：

```text
ed4b5e51e629e06faca68153743b6cd09505009f213d1e4a456150281bcfb80b
```

## 请综合侧检查

1. 检查 2,048-byte 权重 cache 的综合映射、寄存器/宏数量、面积和实际读端口。
2. 确认 16 lane 每个 MAC 周期的供数没有隐藏多周期或过度复制。
3. 检查 cache→PE 和 PE 内部路径的 setup/hold、扇出和慢角时序。
4. 如在服务器复测 layer00，请记录真实 SRAM 下的 X/W/bias/Y 事务数及完整装载到写回周期。

本交接不把本地行为级仿真周期当作正式 PPA 或平台性能结论。
