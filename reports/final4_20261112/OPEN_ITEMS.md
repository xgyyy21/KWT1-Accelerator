# 未完成事项登记（2026-11-11）

## OPEN-1 整机门级程序级仿真（暂停，未完成）

**状态：未完成，暂停。不写 PASS。**

### 已经做实的部分

| 项 | 结果 | 证据 |
|---|---|---|
| ITCM 位交织 | 确认存在，已修正 | `RAMSP4KX64.v`：`mux=A[2:0]`、`row=A[11:3]`，行内 bit `8*i+mux` = 字 bit `i`；重打包后打印 `MODEL_MEM0=1900c7f700c7ffff` ×8 |
| ROM 黑盒 | 确认存在 | `ROM1KX32.v` 32 条 `assign Q[i]=Q[i]`；已改为 `assign Q=mem[A]` 并全量重编，仍无效 |
| 时钟 | 正常 | `hfe=cce=aone=9130`（hfclk / core_clk / clk_aon 各 9130 个上升沿） |
| CPU 复位 | 可用 UCLI 拉干净 | `force ...u_e203_reset_ctrl.rst_n 1'b1` → `rstcore=1` |
| 复现命令 | `simv_rom6 -ucli < f5.do` | `~/kwt1_final4_realgate_20261111/` |

### 卡住的位置

> 复位/时钟/预装/ROM 全部干净后，`u_sram_wrap_32KX64` 的 `CS/WE_BAR/ADDRESS`
> 仍从复位释放第一个周期起为 X，`fetches=0`，最后 `KWT CPU WATCHDOG`。

最可能位置：ITCM 包装层内部的时钟门控/复位使能单元（X 传播）。
未验证的下一步：`$dumpvars` + UCLI driver 追踪 `u_sram_wrap_32KX64.CS` 的驱动源。

### 重新接续时需要的东西

- 目录：`~/kwt1_final4_realgate_20261111/`
- 模型：`RAMSP4KX64_itcm.v`（位交织预装）、`ROM1KX32_boot.v`（已删自赋值）
- filelist：`gate_rom.f`
- 监视器：`trace_monitor.v`（打印 hfe/cce/aone/rstcore/cs/web/addr）
- 强制脚本：`f5.do`
- 编译命令见 `GATE_DEBUG.md` 第 5.2 节（必须新 `-o` 名字，VCS 会因时钟偏移跳过重编）
- 结论文件：`full_layer_test/GATE_DEBUG.md`

### 对交付的影响

官方要求不需要整机门级跑完整程序。综合前后功能一致性用以下组合证明：

1. RTL SoC 仿真（`kwt_smoke`，`x3=1`）
2. 加速器块级门级 TB（K64 / K256 PASS）
3. LEC（RTL vs 网表形式等价，待做）

报告中**不得**出现"Final4 网表门级功能 PASS"或"SDF PASS"。
