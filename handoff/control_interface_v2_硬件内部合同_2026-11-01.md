# control_interface_v2：硬件内部控制合同

## 范围

本文件定义当前协议中立 RTL 可验证的寄存器行为。它不是最终 E203 自定义指令编码，也不替代平台 NICE/ICB 的正式接口说明。

## 寄存器字节偏移

| 偏移 | 名称 | 访问 | 说明 |
|---:|---|---|---|
| `0x00` | CTRL | W | bit0 START，bit1 CLEAR_DONE，bit2 CLEAR_ERROR |
| `0x04` | STATUS | R | bit0 BUSY，bit1 DONE，bit2 ERROR |
| `0x08` | SRC_A | RW | X 基地址，16-bit word address |
| `0x0C` | SRC_B | RW | W 基地址，16-bit word address |
| `0x10` | DST | RW | Y 基地址，16-bit word address |
| `0x14` | M | RW | 输出行数 |
| `0x18` | K | RW | 归约维度 |
| `0x1C` | N | RW | 输出列数 |
| `0x20` | BIAS | RW | bias 基地址，16-bit word address |

## 控制规则

- START 仅在非 BUSY 且配置已锁存时接受；接受后产生一个启动脉冲。
- BUSY 期间重复 START 置 ERROR，不重新装载或清空 SRAM。
- 完成后 DONE 保持，直到 CLEAR_DONE 或下一次任务按内部规则重新开始。
- CLEAR_ERROR 清除错误粘滞位；总线异常、非法配置和超时不得静默成功。
- 连续任务必须重新写入 X/W/bias 配置并验证上一任务的部分和不会泄漏。

## 外部映射边界

当前 `fp32_nice_control_adapter` 把通用 NICE 请求映射到上述寄存器，`fp32_tile_soc_bus_adapter` 把内部 16-bit 数据请求映射到通用 System Bus。真实 E203 接入时，还需由平台包装层确定指令字段、ICB 信号命名、地址转换、错误码和响应时序。

