# INT16 DMA 请求边界寄存化交接

日期：2026-11-05

目标分支：`hardware`

分支路径：<https://github.com/xgyyy21/KWT1-Accelerator/tree/hardware>

## 修改目标

针对综合侧联合时序报告中 `SS 0.99 V/-40°C` 的跨块 setup 违规，切断：

```text
matrix_n/current_row/current_k
  -> 地址乘加
  -> adapter 地址窗口判断
  -> shared SRAM controller 状态更新
```

本次只改 DMA 命令边界，不改 PE、权重 tile cache、INT16 数值合同、System Bus 宽度或 SRAM wrapper。

## RTL 修改

修改文件：

```text
rtl/int16_accelerator_top.sv
```

新增完整命令 pending 寄存器：

```text
master_cmd_pending_q
master_cmd_addr_q
master_cmd_read_q
master_cmd_wdata_q
master_cmd_wmask_q
```

请求状态先生成并锁存完整命令，下一拍才由寄存器驱动 `m_icb_cmd_*`。状态机只在真实的：

```text
m_icb_cmd_valid && m_icb_cmd_ready
```

成立后进入等待响应状态。反压期间地址、读写属性、写数据和掩码全部保持。

测试平台新增反压保持检查：

```text
tb/int16_accelerator_top_tb.sv
tb/int16_software_handoff_tb.sv
```

如果 `valid=1 && ready=0` 期间任一命令字段变化，testbench 立即失败。

## 本地验证结果

工具：Icarus Verilog 14.0 devel；Verilator 5.050 lint。

- 顶层连续任务：PASS；K=64 尾 tile、K=256、任务间 cache 重新装载、总线错误后 cache 失效均通过。
- 12 层 INT16 Golden：12/12 PASS，304,128 个输出逐位匹配。
- layer00：25,344 个输出匹配，12,672 次写回，71,808 条命令和响应。
- layer00 本地行为级周期：529,456；旧版本约447,959。增加的周期来自命令边界寄存化，不能用本地周期推断服务器最终性能。
- INT16 PE：PASS。
- E203 最小 adapter/地址边界：PASS，命令和响应配对完整。
- Verilator lint：退出0；warning为已有位宽扩展、空 trace 端口等提示，没有新增 error。

本地证据目录：

```text
handoff/evidence/int16_cmd_boundary_layer00_2026-11-05/
handoff/evidence/int16_cmd_boundary_12layer_2026-11-05/
handoff/evidence/int16_cmd_boundary_top_2026-11-05/
handoff/evidence/int16_cmd_boundary_pe_2026-11-05/
handoff/evidence/int16_cmd_boundary_e203_2026-11-05/
handoff/evidence/int16_cmd_boundary_verilator_2026-11-05.log
```

## 尚不能在本地确认的内容

本机没有 Yosys、Slang 或 DC，因此不能确认：

1. 新命令寄存器是否消除了真实 accelerator→shared controller 的 setup 违规；
2. cache→PE、adapter→共享 SRAM 控制器的实际 PVT slack；
3. max-transition、扇出、复位 recovery/removal 和 CTS/RC 影响；
4. 真实 E203、共享 SRAM 宏和完整 SoC 下的最终周期。

## 请综合侧服务器复核

请基于当前工作区改动重新生成 accelerator 映射网表，并与共享控制器、真实 RAMSP 宏放在同一联合顶层、同一时钟和三组候选 PVT 下复核：

- `master_cmd_addr_q`/`master_cmd_pending_q` 到共享控制器的路径；
- adapter 地址窗口检查和 ready 反馈路径；
- 命令反压时 payload 保持；
- 命令/响应单 outstanding 约束；
- SS -40°C 的原违规路径是否转为正 slack；
- 真实 E203 CPU layer00 功能与完整装载到写回周期。

如果命令寄存化后仍有 setup 违规，下一步再改为行基址、K 步长和 pair 地址寄存器的增量地址生成，避免每条请求重新综合 64 位乘法。不要先改 PE 或增加 PE。

本文件与本轮 RTL/TB 改动一起固定到 `hardware` 分支；最终 commit SHA 以 GitHub 提交记录为准。
