# control_interface_v1：内部原型版（未冻结为真实 E203 NICE）

版本：`v1.0-internal-2026-10-20`

## 内部选择码

| 选择码 | 名称 | 含义 |
|---:|---|---|
| `0x00` | CTRL | bit0 START；bit1 清 DONE；bit2 清 ERROR |
| `0x04` | STATUS | bit0 BUSY；bit1 DONE；bit2 ERROR |
| `0x08` | SRC_A | X 的 16 位字基址 |
| `0x0c` | SRC_B | W 的 16 位字基址 |
| `0x10` | DST | Y 的 16 位字基址 |
| `0x14` | M | 行数 |
| `0x18` | K | K 长度 |
| `0x1c` | N | 列数 |
| `0x20` | BIAS_BASE | bias 的 16 位字基址 |

这些是 RTL 内部选择码，不是 MMIO 物理地址，也不是已经分配的 E203 指令编码。

## 原型握手

- NICE 内部请求包含 valid、write、addr、wdata；读请求产生一次响应。
- System Bus 数据面为 16 位数据、16 位字地址模型。
- 读请求接受后延迟返回；写请求在 ready 握手时接受。
- 当前顶层只允许一个未决读请求。
- DONE 在最后一个结果半字写握手之后产生；真实平台还需确认写缓冲是否已经 drain。
- BUSY 时改写配置或重复 START 属于错误路径，现有原型保持 ERROR。

## 尚未冻结

真实 E203 NICE 指令编码、操作数/返回值映射、System Bus 主设备适配、写响应、byte-enable、异常返回、超时、DMA 停止和 CPU 结果可见性均等待平台资料。
