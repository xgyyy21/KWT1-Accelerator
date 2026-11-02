# KWT-1 Control Interface v3（硬件侧提案）

日期：2026-11-02  
状态：硬件 RTL/TB 已按此语义实现；等待软件与平台侧复核，不是正式 E203 ABI

## 1. 范围和编码

本合同描述 standalone NICE Wrapper 的行为。临时 mock 编码仍为 `opcode=7'h7b`、`funct7=0`、`funct3=0..4`，不能据此认为公开或比赛 E203 已译码、CPU 可发射该指令。

| funct3 | 操作 | `rs1` | `rs2` | 正常应答 |
|---:|---|---|---|---|
| 0 | CFG_WRITE | 32-bit byte offset | 写值 | `rd=0, err=0` 表示配置写已接受 |
| 1 | CFG_READ | 32-bit byte offset | 忽略 | `rd=配置值, err=0` |
| 2 | START | 忽略 | 忽略 | `rd=0, err=0` 只表示命令已接受 |
| 3 | STATUS | 忽略 | 忽略 | `rd[2:0]={ERROR,DONE,BUSY}`，高位为 0 |
| 4 | CLEAR | `rs1[0]` 清 DONE；`rs1[1]` 清 ERROR | 忽略 | `rd=0, err=0` 表示清除命令已接受 |

配置地址必须是 32-bit、4-byte 对齐的 byte offset，且高位为 0。只有下表寄存器可被 CFG_READ/CFG_WRITE 访问；CTRL/STATUS 不允许作为通用配置寄存器访问。

| Offset | 名称 | CFG_READ | CFG_WRITE | 含义 |
|---:|---|---|---|---|
| `0x08` | SRC_A | 是 | 是 | X 基地址，当前内部为 16-bit word address |
| `0x0C` | SRC_B | 是 | 是 | W 基地址，当前内部为 16-bit word address |
| `0x10` | DST | 是 | 是 | Y 基地址，当前内部为 16-bit word address |
| `0x14` | M | 是 | 是 | 输出行数 |
| `0x18` | K | 是 | 是 | 归约维度 |
| `0x1C` | N | 是 | 是 | 输出列数 |
| `0x20` | BIAS | 是 | 是 | bias 基地址，当前内部为 16-bit word address |

其他/未对齐/带非零高位地址，以及 CFG_WRITE 到 CTRL/STATUS、CFG_READ CTRL/STATUS，均返回 `nice_rsp_err=1`，不访问内部寄存器。

## 2. 命令错误与作业错误

- **命令错误**通过该条 NICE 响应的 `nice_rsp_err=1` 表示，包括非法编码/地址，以及 BUSY 或 START 保护期间的 CFG_WRITE、START、CLEAR。命令错误本身不置位 STATUS.ERROR。
- **作业错误**来自加速器执行结果，由内部状态寄存器粘滞保存并通过 STATUS.ERROR 表示；读取 STATUS 不清除任何状态。
- BUSY 时 CFG_READ 和 STATUS 仍可用；BUSY 时所有写类命令都拒绝。
- START 被接受后立即返回命令应答，但不代表任务完成。`start_guard` 从 START 接受一直保持到 `engine_done` 或 `engine_error`，保护 `engine_busy` 尚未拉高的窗口和整个任务期间。保护期间重复 START/配置写/CLEAR 报命令错误，不额外置位作业 ERROR。
- 一个已接受的新 START 会按当前 `ai_engine_regs` 行为清除上次的 DONE/ERROR 粘滞状态。软件也可以在空闲时先显式 CLEAR；不要求必须 CLEAR 才能启动下一任务。
- CLEAR 在空闲时只按 `rs1[1:0]` 选择清除位，其他 `rs1` 位和 `rs2` 忽略。`CLEAR(3)` 在没有同周期新完成/错误事件时使 STATUS 为 0。若 CLEAR 与 DONE/ERROR 事件同周期发生，事件优先，状态保持置位；待事件源消失后再 CLEAR。
- 复位清除控制状态和在途 NICE 响应，但不清除 SRAM 内容。此原型没有宣称支持硬件 abort。

## 3. DONE、CPU 读回与错误边界

STATUS 的 DONE 只表示当前 accelerator 内部任务完成；CPU 读取输出前仍需平台确认 System Bus 写完成、共享内存可见性和缓存维护/屏障规则。当前 NICE ICB 数据通道 inactive，矩阵数据使用独立 16-bit System Bus；FP32 低/高半字分两次传输。

当前 wrapper/System Bus 端口没有总线 error、timeout 或 abort 输入，不能把这些故障纳入已完成的错误语义。CPU 轮询超时是软件侧放弃等待，不等同于硬件取消任务。

## 4. 测试要求及本轮实现

`tb/kwt1_e203_nice_wrapper_tb.sv` 覆盖寄存器权限、非法指令、忙时策略、START-to-BUSY 窗口、命令错误不污染作业 ERROR、CLEAR 同周期事件优先级、读响应背压、复位期间 NICE 信号抑制和 1×1 FP32 写回。

`tb/kwt1_e203_nice_wrapper_continuous_tb.sv` 覆盖不复位、不清 SRAM 的两次不同地址任务、START 后轮询、System Bus 背压和 16-bit 写回。测试使用 mock opcode，不代表真实 E203 CPU 已运行。

## 5. 待三方确认

1. 确认 `nice_rsp_err` 在真实 E203 CPU 侧的可观察行为，以及驱动如何判断命令错误。
2. 确认真实自定义指令编码和汇编/编译器发射方式。
3. 复核 START 清除旧 DONE/ERROR 的选择；尤其作业错误后的安全重试策略。
4. 确认平台 byte/word 地址转换、System Bus 写完成、DONE 后 CPU 可见性和缓存维护规则。
5. 若合同通过评审，再将本提案标记为联合冻结的 v3；在此之前它仍是硬件侧实现提案。
