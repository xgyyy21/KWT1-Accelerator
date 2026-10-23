# KWT-1 内部控制接口 v1

版本：`control_interface_v1.1-internal-2026-10-24`
状态：**可复现的硬件内部寄存器候选；不是正式 E203 NICE 指令编码或 MMIO 地址表**

## 1. 两条通道的职责

- **NICE 控制面**：配置基地址和矩阵尺寸，发出 START，读取 BUSY/DONE/ERROR。
- **System Bus 数据面**：DMA 读取 X/W/bias 半字，并把 Y 半字写回外部存储。

当前 RTL 顶层为 `rtl/fp32_accelerator_top.sv`。`nice_req_*`、`nice_rsp_*`、`sys_req_*` 和 `sys_rsp_*` 是协议中立的内部端口，平台包装器必须把它们转换成真实 E203 NICE/ICB（或最终指定的总线）信号，不能直接宣称已经完成 E203 接入。

## 2. 内部寄存器选择码

寄存器访问使用 `nice_req_valid`/`nice_req_write`；写请求在 `nice_req_ready=1` 时接受，读请求在随后一个内部周期产生 `nice_rsp_valid`。当前接口没有 `rsp_ready`，因此 E203 包装器必须负责响应消费和停顿转换。

| 选择码 | 名称 | 写入含义 | 读取含义 |
|---:|---|---|---|
| `0x00` | CTRL | bit0 START；bit1 清 DONE；bit2 清 ERROR | 读回 0 |
| `0x04` | STATUS | 忽略 | bit0 BUSY；bit1 DONE；bit2 ERROR |
| `0x08` | SRC_A | X 外部基址（16 位字地址） | 当前值 |
| `0x0c` | SRC_B | W 外部基址（16 位字地址） | 当前值 |
| `0x10` | DST | Y 外部基址（16 位字地址） | 当前值 |
| `0x14` | M | 行数，低 16 位 | 当前值 |
| `0x18` | K | K 维长度，低 16 位 | 当前值 |
| `0x1c` | N | 列数，低 16 位 | 当前值 |
| `0x20` | BIAS_BASE | bias 外部基址（16 位字地址） | 当前值 |

地址选择码是内部寄存器选择，不是已冻结的物理 MMIO 偏移。正式平台地址、NICE 指令 opcode/操作数和访问权限必须由 E203/SoC 负责人确认后另行发布带提交号的版本。

## 3. 状态与启动规则

1. 复位清零配置、`engine_start`、sticky DONE 和 sticky ERROR。
2. 只有在 `BUSY=0` 且没有本拍启动脉冲时，CTRL[0]=1 才产生一个周期的 `engine_start`。
3. BUSY 期间写配置被忽略；BUSY 期间重新 START 置 sticky ERROR，不会重启当前任务。
4. 新 START 清除上一个任务的 sticky DONE/ERROR，但不替代底层错误恢复流程。
5. DONE 在最后一个结果半字被数据面接受之后才由顶层事件置位；`compute_done` 或 `result_last` 不能单独作为整任务完成信号。
6. 软件必须先检查 ERROR，再把 DONE 视为成功；DONE 和 ERROR 同时出现时按失败处理。
7. 当前无中断、无 ABORT、无错误码、无软件恢复位；总线错误/超时/复位策略属于待冻结的平台扩展。

## 4. System Bus 内部握手

- 请求：`sys_req_valid && sys_req_ready` 接受一次读或写。
- 读：最多一个 outstanding read；稍后用 `sys_rsp_valid/sys_rsp_rdata` 返回一个 16 位字。
- 写：`sys_req_ready` 表示写请求已到达当前原型的约定可见点；真实平台若有 posted write，包装器必须提供 drain/fence，不能直接把 ready 当成 CPU 已可见。
- 无 `rsp_ready`：平台包装器必须保证响应被一次性消费，或在外层补齐握手。
- 无 byte-enable、burst、transaction ID 和标准 bus error 输入；这些都是 E203/SoC 适配的待定项。

## 5. 推荐的驱动时序（候选）

`确认空闲/无错 → 搬运 X/W/bias → fence → 写 SRC_A/SRC_B/BIAS_BASE/DST/M/K/N → 读回校验 → START 一次 → 轮询 STATUS → ERROR 优先判断 → DONE 后执行平台可见性 fence → 读取 Y`。

当前流程可用于原型和 testbench，不能替代真实 E203 驱动。连续任务还需验证：完成后不复位整机即可重新装载参数、旧 DONE/ERROR 被清理、SRAM/缓存无状态污染。

## 6. 版本与证据

本接口对应 hardware 分支中 `rtl/fp32_accelerator_top.sv` 及 `rtl/files.f` 的固定快照；真实 layer00 结果包的 SHA-256 为 `86238127a80a2f1726d9968698c57a676dd065f9419dd69988dfe07cfdd4db20`。软件侧已独立核验该归档的 25,344 个输出和 50,688 条写回记录，但没有重新运行完整 RTL；因此本文件不宣称 E203/SoC 或 PPA 已通过。
