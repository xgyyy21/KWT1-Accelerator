# KWT-1 `control_interface_v1`（内部候选版）

版本：`control_interface_v1.2-internal-2026-10-25`  
状态：**协议中立的硬件内部控制约定，尚未冻结为 E203 NICE 指令编码或 MMIO 地址表**

## 1. 端口分工

当前顶层：`rtl/fp32_accelerator_top.sv`。

- NICE 控制面：`nice_req_valid/write/addr/wdata`，`nice_req_ready`，`nice_rsp_valid/rdata`。
- System Bus 数据面：`sys_req_valid/write/addr/wdata`，`sys_req_ready`，`sys_rsp_valid/rdata`。
- NICE 只负责控制和状态；矩阵数据由 System Bus/DMA/缓存路径搬运。

## 2. 内部选择码

这些是当前 RTL 内部选择码，不是 E203 物理 MMIO 偏移：

| 选择码 | 名称 | 写入 | 读取 |
|---:|---|---|---|
| `0x00` | CTRL | bit0 START；bit1 清 DONE；bit2 清 ERROR | 0 |
| `0x04` | STATUS | 忽略 | bit0 BUSY；bit1 DONE；bit2 ERROR |
| `0x08` | SRC_A | X 的 16 位字基址 | 当前值 |
| `0x0c` | SRC_B | W 的 16 位字基址 | 当前值 |
| `0x10` | DST | Y 的 16 位字基址 | 当前值 |
| `0x14` | M | 行数，低 16 位 | 当前值 |
| `0x18` | K | K 长度，低 16 位 | 当前值 |
| `0x1c` | N | 列数，低 16 位 | 当前值 |
| `0x20` | BIAS_BASE | bias 的 16 位字基址 | 当前值 |

## 3. 启动与状态候选规则

1. 复位清零配置、START 脉冲、DONE 和 ERROR。
2. 只有 BUSY=0 时，CTRL[0] 才产生一个周期的启动请求。
3. BUSY 期间写配置被忽略；BUSY 期间重复 START 进入 ERROR 路径。
4. 新 START 清除上一次任务的 DONE/ERROR，但不自动修复底层数据面故障。
5. DONE 只有在最后一个结果半字完成内部写回握手后才可置位；真实平台若存在 posted write，必须额外等待 drain/fence。
6. 软件应优先检查 ERROR；DONE 与 ERROR 同时出现时按失败处理。

## 4. System Bus 内部握手

- 请求在 `sys_req_valid && sys_req_ready` 时接受一次读或写。
- 读请求返回一个 16 位字，当前原型最多允许一个未决读。
- 写请求的 `sys_req_ready` 只表示当前原型接受请求，不自动表示 CPU 已看到写入结果。
- 当前内部端口没有 `rsp_ready`、byte-enable、burst、transaction ID 或标准错误码；平台包装器必须补齐或明确约束这些信号。

## 5. 原型驱动顺序

```text
确认空闲/无错
  → 搬运 X/W/bias
  → 平台 fence（待 E203 确认）
  → 写 SRC_A/SRC_B/BIAS_BASE/DST/M/K/N
  → 写 START 一次
  → 轮询 STATUS
  → ERROR 优先判断
  → DONE 后执行结果可见性 fence
  → 读取 Y
```

这只是内部原型流程，不能替代真实 E203 驱动。

## 6. 等待 E203/SoC 确认

- NICE 指令 opcode、操作数和返回值编码。
- NICE 的真实 valid/ready、异常和响应停顿规则。
- System Bus/ICB 端口命名、物理地址窗口、字节地址转换和 Cache 属性。
- 写响应、超时、总线错误码、DMA 停止、ABORT、复位和错误恢复。
- DONE 中断或轮询方式，以及最后一个写回对 CPU 的可见性保证。

