# 12 层加速器 RTL 功能验证结果（2026-11-13）

## 结论

**12/12 层在加速器 RTL（综合前）上实际跑通，每层 12,672 个 32 位输出字与软件 Golden 逐字比较，0 失配。**

- 验证对象：综合前 RTL `int16_accelerator_top_newfix.sv`
  - SHA-256 `2257fc3eabf058d575a8f39d57de03ab42d8a2a9d2745f74ab3eace7e300a923`
  - 与 L00/L01 综合前后一致性验证所用 RTL 为同一文件（哈希相同）。
- 测试平台：`~/kwt1_final4_rtl_gate_compare_20261113/rtl_tb.sv`
  - 原始 TB SHA-256 `8575e8cc89f1286a8337f1632b7f0b5f184b421e9c8947a44f9cf14a028e4a3e`
  - 按层移位拆成两个只跑单层的变体：`tb_s15.sv`（右移 15）、`tb_s16.sv`（右移 16）
- 向量：`~/kwt1_cpu12_bundle_20261105/vectors/layer_00..11/` 的 `x.mem / w.mem / bias.mem / y_expected.mem`，按 32 位打包成 hex。
- 运行目录：`~/kwt1_final4_layer12_20261113/`

## 每层结果

| 层 | 右移 | M | K | N | 周期 | 比较字数 | 与 Golden 失配 | 非法任务被拒 | 控制错误 | 退出码 | 结果 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 00 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 01 | 16 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 02 | 16 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 03 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 04 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 05 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 06 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 07 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 08 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 09 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 10 | 15 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |
| 11 | 16 | 99 | 64 | 256 | 743,159 | 12,672 | 0 | 是 | 0 | 0 | FULL_LAYER PASS |

机器可读版本：`per_layer_12_rtl_20261113.csv`。

每层日志里同时有：

```
LAYER n mismatches=0 / 12672
ILLEGAL done=0 error=1 cycles=0     <- 0x8000 保留码任务被硬件拒绝
CTRL_ERRORS=0 OTHER_CMDS=0
FULL_LAYER PASS
```

## 复现

```bash
cd ~/kwt1_final4_layer12_20261113
bash run_layers.sh                       # 12 层全跑，~1.3 s CPU/层
cat result_s15.txt result_s16.txt        # 逐层结果
```

脚本行为：从 12 层 INT16 包生成 32 位 hex → 按层移位把向量拷进 `work15`/`work16` → 跑单层 TB → 打印 `LAYER/MISMATCH/ILLEGAL/CTRL` 四项。

## 口径边界（重要）

1. 这是**综合前 RTL** 的实际仿真结果，不是软件 Golden 复算，也不是门级结果。
2. 门级目前只有 L00/L01 的直接比较（见 `FINAL4_REPORT_READY_20261113.md`），**12 层门级未跑**。
3. 本结果只覆盖加速器块级接口（MMIO 配置 + 共享 SRAM 输入 + 写回），**不代表整机 SoC 联调通过**。
4. 每层使用同一任务形状 M=99 / K=64 / N=256（FFN1），未改 M/K/N、未改数值格式、未改冻结 RTL。
