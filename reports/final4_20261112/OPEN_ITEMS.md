# 未完成事项登记（2026-11-11，更新 2026-11-13）

## OPEN-0 12 层加速器 RTL 功能验证（2026-11-13 已完成，关闭）

**状态：完成，12/12 层 PASS。**

| 项 | 结果 | 证据 |
|---|---|---|
| 对象 | 综合前 `int16_accelerator_top_newfix.sv`（SHA-256 `2257fc3e…`） | `~/kwt1_final4_full_layer_20261111/` |
| 层数 | 12/12 `FULL_LAYER PASS` | `~/kwt1_final4_layer12_20261113/run_all.log`、`result_s15.txt`、`result_s16.txt` |
| 每层 | 12,672 字与 Golden 0 失配；非法 `0x8000` 被拒；`CTRL_ERRORS=0`；743,159 周期；退出码 0 | `work15|work16/run_l*.log` |
| 汇总 | `LAYER12_RTL_RESULT_20261113.md`、`per_layer_12_rtl_20261113.csv` | 本目录 |

边界：门级仍只有 L00/L01；整机 SoC 未 PASS。

## OPEN-1 整机门级程序级仿真（2026-11-12 有重大进展，仍未 PASS）

**状态：未 PASS。不写 PASS。**

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

### 2026-11-12 更新：已跑到程序结束，但自检失败

启动问题修复后，最新门级整机运行 `~/kwt1_cpubus_diag_20261112_fix1/run/sim_fix10.log`（2026-11-12 20:56）结果：

| 项 | 观测值 |
|---|---|
| 执行 | 4,516 条指令，`[RESULT] EXIT_PC=0x800003f0 cyc=12193 itcm=4516 dtcm=0 shared=1120` |
| MMIO 配置 | CPU 写 `0x11000000`；`[ACC_TRACE] m=2 k=64 n=2 a=a0001000 b=a0002000 bias=a0003000 dst=a0004000` |
| 加速器 | `state=12`、`enger=1`、`sticky=0`，向 `0xa0004000` 写回 4 个 32 位字 |
| 状态读回 | CPU 读 `0x11000004` 得到 `0x00000004` |
| 判定 | 程序按 `status & 2` 判完成位，未满足 → `x3=2` → `TEST FAIL x3=00000002` |

待定位：`0x11000004` 读回值 `4` 与程序期望的完成位 `2` 不一致，是寄存器映射偏移、STATUS 位定义还是写回数据比较问题，尚未区分。**下一步**：抓 `u_kwt` 内 MMIO 寄存器的读数据与 `accel_done`，并对照 `kwt_smoke` 的 `program_listing.txt` 第 50–90 行确认判据。

### 2026-11-13 根因初判：读回的 4 是错误位

`assets/int16_system_bus_control.sv` 第 77 行：

```verilog
A_STATUS: s_icb_rsp_rdata = {29'd0, error_sticky, engine_error, done_sticky, engine_done, engine_busy};
```

位定义：bit0=`engine_busy`、bit1=`engine_done`、bit2=`error_sticky`、bit3=`engine_error`。

因此 `0x11000004 = 0x4` 表示 **error_sticky=1、done=0**——硬件报告的是错误，不是完成。程序的 `andi x7,x5,2`（测 done 位）自然永远不成立，轮询 100,000 次后跳 `fail`，`x3=2`。

同一次运行下发的任务参数是 **M=2 / K=64 / N=32 / shift=3**（`program_listing.txt` 第 43–58 行：`sw` 到 `0x18/0x1C/0x20/0x24`），与所有已通过的块级配置 **M=99 / K=64 / N=256、shift 15/16** 不同；`[ACC_TRACE]` 内部还显示 `n=2`，与程序写入的 32 不符。

下一步二选一：
1. 查 `int16_system_bus_control.sv` 里 N 寄存器（`A_N=8'h20`）的写入路径，确认 `n=2` 的来源；或
2. 把 SoC 程序改成已验证的合法形状 M=99/K=64/N=256（需重新编译程序镜像与数据段），再跑一次整机。

### 2026-11-13 更新：合法形状已跑通前半程（任务未跑完）

已把 SoC 程序改成合法形状并重跑：

- 新镜像 `~/kwt1_final4_soc_rtl_int_20261113/program/kwt_l00_m99k64n256.verilog`（M=99、K=64、N=256、shift=15；x/w/bias/y 用 layer-00 已验证向量）；
- CPU 执行到写 START（`t=2.34267 ms`），`[ACC_TRACE]` 显示 `m=99 k=64 a=a0001000 b=a0002000 bias=a0003000 dst=a0004000`；
- CPU 轮询 `0x11000004` 读到 `0x1`（busy），状态位判据正确；
- 但 TB 18 ms 时限内任务未结束（看门狗终止），只能给下界：**任务窗口 > 782,857 拍 @50 MHz**，即 **≤191 tasks/s @150 MHz**。
- TB 改动仅 `#15000000`→`#18000000`，备份 `tb_soc_cpubus.sv.bak_20261113`；日志 `run/sim_l00_m99c.log`。

### 2026-11-13 更新：整机 RTL 级 TB 绑定阻塞

同一 TB `tb_soc_cpubus.sv` 换到综合前 RTL 源（`files_soc_newfix.f`）后，VCS 在 `-XMRE` 阶段报 `token 'u_sram_wrap_32XK64' cannot be resolved`。原因是 TB 用网表专用层次 `...u_e203_itcm_ram.u_sram_wrap_32XK64` 预装 ITCM；RTL 侧 ITCM 由 `assets/kwt1_sram_bank.sv`（`RAMSP8KX32 u_macro`）组成，没有该层。要跑整机 RTL 需重写 ITCM/DTCM 预装路径，属大规模调试，本轮不开展。

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

1. 加速器 RTL 12 层功能验证（12/12 PASS，2026-11-13）
2. 加速器块级门级 TB（L00/L01 与 RTL 逐位 0 差异；K64 / K256 PASS）
3. LEC（RTL vs 网表形式等价，待做；本次未做）

报告中**不得**出现"Final4 网表门级功能 PASS"、"整机 SoC 联调 PASS"或"SDF PASS"。
